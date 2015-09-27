---
date: 2015-09-27
excerpt: How this blog is run
tags:
- meta
- hexo
- nginx
title: About This Blog
toc: true
---

I am going to start this blog with a post about the blog itself.

In my opinion, simple text files and command line tools is where it's at, so after some googling, I stumbled about Hexo, and just decided to try it out, because I wanted to get experience with blogging and the accompanying software.

[Hexo](https://hexo.io/) is not actually a complete blogging platform, but simply a static site generator. It takes markdown files, and turns them into nice HTML files with CSS and everything. The big advantage of this approach is that you can write those markdown files in whichever way you like.

Also, setup is much easier than with a complete, integrated solution like WordPress. You do not need a database, it's much more lightweight and one can change to another platform more easily. There are far fewer security concerns, too. Static content served by a webserver without and backend for PHP or whatever just provides a very small attack surface.

## The content

Right now, I am writing this with vim as a simple markdown file. The following plugins make this a bit easier:

  * [Goyo.vim](https://github.com/junegunn/goyo.vim)
  * [vim-pencil](https://github.com/reedes/vim-pencil)

The first one makes for distraction-free writing (it simply disables most of the vim UI and resizes the editing area), and the second makes writing prose a breeze. A simple

```vim
:Goyo
:PencilSoft
```

and we are ready to go.

## Hexo

Ok, so much about actually writing the text, but how do convert this text to a nice webpage? This is where Hexo comes into play. The installation is actually as easy as the website makes it look. Hexo is built with Node.js, so this has to be installed beforehand. Then, the following is enough:

```shell
[~/projects]$ npm install hexo-cli -g
[~/projects]$ hexo init blog
[~/projects]$ cd blog
[~/projects]$ npm install
```

I am not going to show all the stuff Hexo is capable off, you can read through [the official documentation](https://hexo.io/docs/) to get a nice overview.

## Serving the content

In the end, we get some publishable HTML files with CSS and everything in the `public/` subfolder. For "production" use, I am simply going to deploy [nginx](http://nginx.org/) to serve these static files. All of this is deployed on a dedicated blogging virtual machine on my home server. Because I do not have a publicly reachable IPv4 address (yay CGNAT!), a small [DigitalOcean](https://www.digitalocean.com/) droplet serves as a reverse proxy over a VPN.

Because the content is simply a static web page, there is no need for a database or web framework or anything, and serving the content is super fast! The following nginx configuration is enough, assuming your Hexo root is in `/var/lib/hexo/blog` and is readable by group `hexo`:

```
/etc/nginx/nginx.conf
```
```nginx
user nginx hexo;
worker_processes auto;

http {
    access_log /var/log/nginx/access.log main;
    error_log  /var/log/nginx/error.log  warn;

    default_type application/octet-stream;

    include /etc/nginx/mime.types;
    include /etc/nginx/conf.d/*.conf;

    server {
        listen 80 default_server;
        server_name _;
        root /var/lib/hexo/blog/public;

        location / {
        }
    }
}
```


## Automating the deployment

I'm lazy. Right now, I would have to log into my blogging VM, use the `hexo` command to create a new blog post, actually write the post, and generate the static files manually. No preview to ensure that I didn't screw up markdown syntax, no version control.

Version control is of course always a good idea when you are working with text files. I prefer [git](https://git-scm.com/) as VCS, and I though about using git as a simple deployment tool for the blog. I envisioned a workflow like this on my local machine:

  * run `hexo new "new post"` to create a new post
  * edit the post in `source/_posts/`
  * commit the new file to git and push it to the blogging server

To achieve this, I initialized a new git repository in the hexo blog directory, created a bare repository on the blogging server, and configured the local repository to push to the remote one.

On the remote server, there is a decicated `hexo` user with the home directory in `/var/lib/hexo`. In there, the direcotry `blog.git/` is the bare repository mentioned above, and `blog/` is configured to always checkout the `master` branch, so these files can be served by nginx.

The following git hook ([more info here](https://git-scm.com/book/en/v2/Customizing-Git-Git-Hooks)) is used to always update the web root when there are new commits on the `master` branch:

```
/var/lib/hexo/blog.git/hooks/post-receive
```
```shell
#!/usr/bin/env bash

_logfile="$HOME/hook.log"

echo "update hook $(date +%FT%T)" >> "$_logfile"
git --work-tree="$HOME/blog" --git-dir="$HOME/blog.git" checkout master --force &>> "$_logfile"
hexo generate --cwd "$HOME/blog" &>> "$_logfile"
```

Because I don't really care about the commit messages in this case, I also wrote a little bash script on the local machine to automatically make a new commit and push it to the remote server:

```
~/bin/publish-blog
```
```shell
#!/usr/bin/env bash

cd ~/projects/blog || exit 1
git commit --message="Update $(date +%F)"
git push server master
```


This assumes the local blog repository is in `~/projects/blog` and the remote is simply called `server`.

Now with a simple

```shell
[~/projects]$ git add <post>
[~/projects]$ publish-blog
```

a new post is pushed to the server, the static content is generated and can be accessed over the internet. As everything is in git, a post can easily be removed with `git revert`.

## Preview server

While editing a post, it is quite helpful to have a local preview of blog, so you can view if everything looks as it should before publishing. This functionality is already built into Hexo, with the following command we start a web server on the local machine to view our blog which is automatically updates when we make changes:

```shell
[~]$ (cd ~/projects/blog && hexo server --ip 127.0.0.1)
```

Now you can get a nice preview by going to `http://localhost:4000` in your browser.
