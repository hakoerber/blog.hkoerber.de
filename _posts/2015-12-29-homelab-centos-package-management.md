---
title: Homelab CentOS Package Management
date: 2015-12-29T23:01:18+01:00
tags: homelab package yum saltstack
excerpt: >
    Using a local package repository and automating updates of a dozen machines
---

{% include toc %}

Keeping a dozen virtual machines up-to-date can be quite a task. In this post, I will show how to do it automatically and efficiently using yum-cron, a local mirror with rsync, and saltstack.

I will also describe the setup of a "custom" RPM repository to distribute packages built with the awesome [fpm](https://github.com/jordansissel/fpm)

## Automatic updates with yum-cron

Downloading and applying updates with yum can be automated using yum-cron, which is more or less a wrapper around `yum` that runs peridodically with `cron` (hence the name). The setup is quite straightforward, the good old package+config+service triangle, and can be automated using salt:

```yaml
yum-cron:
  pkg.installed:
    - name: yum-cron

  service.running:
    - name: yum-cron
    - enable: True
    - require:
      - pkg: yum-cron

  file.managed:
    - name: /etc/yum/yum-cron.conf
    - user: root
    - group: root
    - mode: 644
    - source: salt://files/yum-cron.conf
    - require:
      - pkg: yum-cron
    - watch_in:
      - service: yum-cron
```

```ini
[commands]
update_cmd = default
download_updates = yes
apply_updates = yes
random_sleep = 360
```

My actual "production" state can be found [here](https://github.com/hakoerber/salt-states-parameterized/tree/master/package/autoupdate), and a role tying it all together is available [here](https://github.com/hakoerber/salt-roles-parameterized/blob/master/autoupdate.sls), but the above still does what it should.

That's it. yum-cron will update the system nightly at a random time between 0:00 and 6:00.

## The local package repository mirror

Now all servers pull their updates every day and apply them automatically. There is one problem though: Every server contacts some upstream mirror on the internet, which puts unnecessary strain on their and our connection. To remedy this, we will create a local mirror that is updated regularly and that all other servers can pull packages from.

First we have to decide which repositories to mirror. Because all servers are exclusively CentOS7 64bit boxes, only repositories matching this release and architecture will be used. The default repos enabled after installing CentOS are the following:

* `base`
* `updates`
* `extras`

In addition to this, [EPEL](https://fedoraproject.org/wiki/EPEL) is also mirrored because it contains some important packages.

To make managing and updating the repositories easier, I wrote a small python script called [syncrepo](https://github.com/hakoerber/syncrepo). It reads a configuration file (`/etc/syncrepo.conf` in this example) and syncronizes all repositories defined there. The file format is easy to understand and looks like this:

```json
{
    "base": "/srv/www/packages",
    "repos": {
        "centos/7/os": "ftp.fau.de",
        "centos/7/updates": "ftp.fau.de",
        "centos/7/extras": "ftp.fau.de",
        "epel/7/x86_64": "ftp.fau.de"
    }
}
```

`base` refers to the local filesystem path where all files will be stored. `repo` maps the paths of the repositories to the upstream mirrors they will be downloaded from.

The mentinoned mirrors will use about 27GB of space, so we have to make sure there is plenty of space available. This is done by mounting a NFS export from the NAS there.

Now it's time for a first sync:

```shell
root[~]# mkdir -p /srv/www/packages/centos/7/
root[~]# mkdir -p /srv/www/packages/epel/7/
root[~]# /usr/local/bin/syncrepo --config /etc/syncrepo.conf
```

This simply executes the following four commands (one for each repo):

```
rsync $OPTIONS rsync://ftp.fau.de/centos/7/extras/  /srv/www/packages/centos/7/extras
rsync $OPTIONS rsync://ftp.fau.de/centos/7/updates/ /srv/www/packages/centos/7/updates
rsync $OPTIONS rsync://ftp.fau.de/centos/7/os/      /srv/www/packages/centos/7/os
rsync $OPTIONS rsync://ftp.fau.de/epel/7/x86_64/    /srv/www/packages/epel/7/x86_64
```

with OPTIONS being

```
--hard-links --out-format "%t %i %n%L " --stats --recursive --update --delete --delete-after --delay-updates
```

to make updates as atomic as possible and give some sensible output.

This is going to take a while. In the meantime, we can setup a webserver to serve those files over HTTP. I'm going to use nginx here. This can be done using the `repomirror` salt role from the [salt role collection](https://github.com/hakoerber/salt-roles) ([direct link](https://raw.githubusercontent.com/hakoerber/salt-roles/master/repomirror.sls)):

```shell
root[~]# salt-call state.sls roles.repomirror
```

This installs nginx to serve `/srv/www/packages`, configures iptables and sets up rsync and logstash. Yay salt!

For reference, here is an equivalent `nginx.conf`:

```nginx
user nginx;

events {}

http {
    include      /etc/nginx/mime.types;
    default_type application/octet-stream;

    server {
        listen 80 default_server;
        server_name _;
        root /srv/www/packages;

        location / {
            autoindex on;
        }
    }
}
```

If using the salt role, nginx should already be running, otherwise

```shell
root[~]# systemctl start nginx
```

will do it manually. Note that when `/srv/www/packages` is a NFS mount and SELinux is enabled, a boolean needs to be set to allow nginx to use NFS:

```shell
root[~]# setsebool -P httpd_use_nfs=1
```

Now, when `syncrepo` is done, the server is a functioning mirror, ready to distribute packages to clients. The last thing to do is automating a repo sync at a certain interval. Cron is perfect for this. The following line in `/etc/crontab` will run the sync each day at 22:00 with a random one hour max delay, which gives it enough time to finish before the clients retrieve their updates (which is between 0:00 and 6:00 as mentioned above):

```
0 22 * * * root perl -le 'sleep rand 60*60' ; /usr/local/bin/syncrepo --config /etc/syncrepo.conf >>/var/log/syncrepo.log 2>&1
```

That's it. The next thing will be configuring the other servers to use our new local mirror.

## Using the local mirror on the other servers

This task is quite simple: The `baseurl` setting has to be changed to point to the local mirror for all repositories in `/etc/yum.repos.d`. Changing

```
baseurl=http://mirror.centos.org/centos/$releasever/os/$basearch/
```

or

```
mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=os&infra=$infr
```

to

```
baseurl=http://pkg01.lab/centos/$releasever/os/$basearch/
```

does the trick for the `base` repo, and the other repositories are similar. Of course it is super tedious to do this for every single server, so let's use salt to automate the process. The `pkgrepo` state makes this possible:

```yaml
repo-base:
  pkgrepo.managed:
    - name: base
    - humanname: CentOS-$releasever - Base
    - baseurl: http://pkg01.lab/centos/$releasever/os/$basearch/
```

The tricky part is integrating this with reclass. First, the file for `pkg01.lab` has to be extended to define all exported repositories:

```yaml
applications:
  - roles.localrepo

parameters:
  applications:
  localrepo:
      domain: lab
      repos:
      base:
          url: centos/$releasever/os/$basearch
      updates:
          url: centos/$releasever/updates/$basearch
      extras:
          url: centos/$releasever/extras/$basearch
      epel:
          url: epel/$releasever/$basearch
```

Then, the mirror will be "advertised" to all servers on the `.lab` domain:

```yaml
parameters:
  domain:
    lab:
      applications:
        localrepo:
          servers: $<aggregate_list("lab" in node.get('domain', {}).keys() and node.get('applications', {}).get('localrepo', None) is not None; dict(name=node['hostname'], repos=node['applications']['localrepo'].get('repos', [])))>
```

Now, the `repos` role (from [here](https://github.com/hakoerber/salt-roles) [[direct link](https://raw.githubusercontent.com/hakoerber/salt-roles/master/repos.sls)]) parses this information and passes it to the relevant states.

This *would* even work with multiple mirrors exporting different repositories (the logic is there) to form kind of a high availability mirror cluster, but fails because the `pkgrepo` state ignores all URLs for `baseurl` except the first one, even though multiple URLs are supported by yum (see `yum.conf(5)`). Anyways, when using only a single mirror (which should be enough), it works as intended.

## A custom repository for non-default packages

Installing packages manually is always a bit of a bad habit in an automated environment. Updating and uninstalling is a pain, as is keeping an overview of what is installed where. For this reason, installing from packages should be preferred when possible. The problem is that building packages is a nightmare (at least RPMs and DEBs). This is what [fpm](https://github.com/jordansissel/fpm) aims to solve, by providing a way to create packages as easily as possible. This, together with a custom repo to distribute the packages, makes management of custom software much easier. It works like this:

First, a new repository is needed, called `custom`, that contains -- well -- custom packages. On our mirror server:

```shell
root[~]# mkdir -p /srv/www/packages/custom/centos/7/x86_64/
```

Now we need something to put there. As an example, let's package the `syncrepo` script mentioned above. We need a user for building packages (building as root is evil™), and install fpm:

```shell
root[~]# useradd -d /var/build -m build
root[~]# yum install -y ruby-devel gcc rpmbuild createrepo
root[~]# sudo -su build

build[~]$ cd ~
build[~]$ gem install fpm
```

Now, set up the directory structure for building the package and get the code:

```shell
build[~]$ mkdir syncrepo
build[~]$ mkdir syncrepo/package
build[~]$ mkdir syncrepo/upstream
build[~]$ cd syncrepo/upstream
build[~]$ git clone https://github.com/hakoerber/syncrepo
```

A Makefile is used to call fpm:

```makefile
VERSION=1.0
DESCRIPTION="Script to create and maintain a local yum package repository"
URL=https://github.com/hakoerber/syncrepo

.PHONY: package
package:
    (cd upstream && git pull origin master)
    fpm \
    -t rpm \
    -s dir \
    --package ./package/ \
    --name $(NAME) \
    --version $(VERSION) \
    --description $(DESCRIPTION) \
    --url $(URL) \
    --force \
    --depends rsync \
    --depends "python34" \
    --exclude "*/.git" \
    --config-files /etc/ \
    ./upstream/syncrepo=/usr/bin/ \
    ./upstream/repos.example=/etc/syncrepo.conf
```

A simple

```shell
build[~/syncrepo]$ make
```

will now build the package and put it into the `package` directory. Nearly done! The only thing left is to make the package available over HTTP. First, it has to be copied into our custom repository:

```shell
root[~]# cp /var/build/syncrepo/package/syncrepo-1.0-1.x86_64.rpm /srv/srv/www/packages/custom/centos/7/x86_64/
```

The last thing that has to be done on the server is building the repository metadata wtth `createrepo` (that was installed above):

```shell
root[~]# createrepo -v --no-database /srv/srv/www/packages/custom/centos/7/x86_64/
```

To make the other servers use the repo, they have to know about it. Let's make salt do this. First, we again have to "advertise" the repo in reclass:

```yaml
parameters:
  applications:
    localrepo:
      domain: lab
      repos:
        ...
        custom:
          url: custom/centos/$releasever/$basearch
```

After the next salt run, all servers will be able to access the custom repo, and we can install `syncrepo` the "clean" way with

```shell
root[~]# yum install -y syncrepo
```

## Conclusion

That's all! Now, every server in the lab gets all its packages from a central, always up-to-date mirror, which speeds up downloading and is much nicer to the upstream mirrors. Also, custom RPMs can be made available to all servers to easily distribute custom or self-maintained software.
