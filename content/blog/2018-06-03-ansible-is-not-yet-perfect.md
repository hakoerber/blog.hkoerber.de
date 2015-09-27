---
date: 2018-06-03
excerpt: A Review of Ansible in Production
tags:
- ansible
- puppet
- config
title: Ansible Is Not (Yet) Perfect
toc: true
---

# Introduction

I have been using Ansible for over a year now, both at work and at home (for example to configure my Kubernetes cluster using [kubespray](https://github.com/kubernetes-incubator/kubespray).

When I first used Ansible, I was blown away by its power and simplicity. And all that by leveraging the existing SSH server, without a new client setup? Awesome!

But over time, I discovered more and more warts and limitations while using Ansible. In this blog post, I will go over all the cases where it falls short of the promises it make and where you start fighting *against* instead of *together with* Ansible.

This post is in no way meant to put down Ansible. When focusing on the bad parts, one might get the impression that there are no good parts. This is absolutely not the case! But by listing its drawbacks, maybe we can come up with ideas how to fix or work around those, benefitting everyone.

This post assumes some familiarity with Ansible. I can recommend the [Getting Started Documentation](http://docs.ansible.com/ansible/latest/user_guide/index.html) for the first steps with Ansilbe.

# Ansible limitations

## YAML as the configuration language

Ansible uses [YAML](http://yaml.org/) for almost all of its configuration. YAML is an excellent choice when you want to express data, similar to JSON. You have dictionaries, lists, scalars, combinations of them and some syntactic sugar to save typing. Easy.

But YAML is not a good language to express program logic.

It is declarative, but without a strict logic you are only poorly implementing a DSL in a data serialization language.

Let's start with a simple example:

```yml
- shell: echo {{ item }}
  with_items:
    - "one"
    - "two"
    - "three"
```

Easy to reason about: This outputs ``one`` ``two`` ``three``. Now, Ansible has a way to express loops using YAML plus Jinja, like this:

```yaml
- shell: echo {{ item }}
  when: item != 'two'
  with_items:
    - "one"
    - "two"
    - "three"
```

If you know Ansible, you most likely know what is going to happen: If will output `one` and `three`, skipping `two`. This is of course the only way the ordering between `when` and `with_items` makes sense, but this is not at all obvious or deducible by only looking at the code. If this was instead done procedurally, it is immediately obvious:

```python
for item in ['one', 'two', 'three'] {
    if item != 'two' {
        shell('echo {item}')
    }
}
```

A similar problem occurs when using `register` together with a loop, like this:

```yaml
shell: echo {{ item }}
with_items:
  - "one"
  - "two"
register: out
```

Usually, ``register`` saves the output of a module into the variable given as its key.
But when using a loop, the structure of `out` differs from one you would get without the loop: Instead of `out` being a dictionary containing the return data, `out[results]` is a list of dictionaries with that data for every invocation of `shell`. Now you know that, and it might make sense, but it is so obscure that you will most likely have to look it up next time (I do every time).

My guess is that YAML was chosen because it is declarative. But Ansible is inherently non-declarative, but rather procedular, at least on a high level.

On the module level declarativeness makes a lot of sense. I do not actually care how that file gets its content and permissions, or how that package is installed. I just want to tell Ansible to make it so, and its job is to figure it out. So, YAML might actually be a good decision for module invokation:

```yaml
- copy:
    dest: /etc/foo.bar
    content: 'Hey!'
    owner: foo
    group: foo
    mode: 0644
```

If is immediately obvious what is going to happen, apart from the not-so-obvious name of `copy` for the module. In the end, I am going to end up with a file that has the exact properties I specified above. Nice.

There is another configuration management system that uses YAML together with Jinja for its syntax: [SaltStack](https://saltstack.com/). The difference is the ordering of the "rendering pipeline": Ansible first parses the files as YAML, and then applies Jinja to certain parts (e.g. the ``when`` key). SaltStack's files are Jinja-templated YAML files, so it first passes the file through the Jinja engine and then parses the output as YAML.

This approach makes for a much more powerful syntax, because you actually have a turing complete language (Jinja) to write your declarations (YAML). It's also less magic: If you know Jinja well enough, it's easy to reason about the code without knowing SaltStack internals.

The problem: You can shoot yourself in the foot, and SaltStack placed your target right next to your foot. There is a thin line between "That makes sense!" and "This is messy!". Take the following code as an example, taken from my salt forumla to set up Nginx together with LetsEncrypt (link [here](https://github.com/hakoerber/salt-nginx-letsencrypt)):

```jinja
{% for domain in params.domains %}
letsencrypt-keydir-{{ domain.name }}:
  file.directory:
    - name: {{ nginx_map.acme.home }}/{{ domain.name }}
    - user: {{ nginx_map.acme.user }}
    - group: {{ nginx_map.acme.user }}
    - mode: '0750'
    - require:
        - user: acme
{% endfor %}
```

This is quite easy to understand. But down the rabbithole it goes, and you stumble upon something like this in a different file:

```jinja
{% if params.get('manage_certs', True) %}
{% set no_commoncert = [] %}
{% for domain in params.domains %}
{% if domain.get('ssl_cert', false) %}
{% set main_name = domain.names[0] %}
{% do no_commoncert.append(1) %}
nginx-pkidir-{{ main_name }}:
  file.directory:
    - name: {{ nginx_map.conf.confdir }}/{{ nginx_map.pki.pkidir }}/{{ main_name }}
    - user: root
    - group: {{ defaults.rootgroup }}
    - mode: 700
    - require:
      - file: nginx-pkidir
{% endif %}
{% endfor %}
{% endif %}
```

Whatever it does, I think we can agree that this is not nice to read.

In the end, I think that YAML is simply not a good abstraction for configuration management files, and using Jinja as a crutch to get more functionality out of a data description language makes it even worse.

Configuration management needs a touring complete language with a declarative way to use modules. From this, you can generate a declaration of your desired configuration, that can then be used to configure your system. Complete declarativeness for the language, even though it is often touted as the end goal of CMSs, is not possible. Even the Puppet DSL has loops and conditions.

In a way, a strictly functional language might be the best way to go. [NixOS](https://nixos.org/) is a really promising and interesting candidate.

## Release engineering

Ansible moves fast and breaks lots of things. This is simply not a good feature for a configuration management system.

For the ``package`` module, ``state: installed`` is now called ``state: present``

One bug that let to a lot of frustration for me and my team was a ``RecursionError`` caused by too many (>20) ``import_role`` statements in a playbook. It was introduced around version 2.0, fixed in version 2.3, resurfaced in version 2.4, and finally fixed for good (hopefully) in version 2.5.

This does not give me a lot of confidence in the Ansible release engineering. I know that it is a very hard job, and you always have to weigh stability against new features. But it is my impression that the Ansible team leans a bit too much on the latter side, introducting breakage and forcing me to adapt my roles and modules every few releases.

## Inventory and Host Variables

Ansible has a concept of host and group specific variables. There are a lot of places where you can set variables, and their precedence is strictly defined (look at the list in the [official documentation](http://docs.ansible.com/ansible/latest/user_guide/playbooks_variables.html#variable-precedence-where-should-i-put-a-variable)!).

The problem with that is the merging strategy: Nested values are not merged, but the later ones overwrite the pervious ones. This means that custom roles cannot have a "main" key, e.g. `postgresql_config` for a PostgreSQL role, but have to pollute the top-level variable space with a prefixed list of variables, like this (taken from [here](https://github.com/ANXS/postgresql/blob/master/defaults/main.yml)):

```yaml
postgresql_version: 9.6
postgresql_encoding: "UTF-8"
postgresql_data_checksums: false
postgresql_pwfile: ""
```

This is simply ugly, and not the way YAML is meant to be used. Also, assume you have the following situation: You have a number of servers, and a number of admins that have access to the server, like this:

```yaml
admins:
  - name: "hannes"
    sudo: true
    sshpubkey: ssh-rsa ...
  - name: ...
```

Now, you want to add a new guy to your list of users, but only for a few servers (you do not want the new guys to break production!). In a perfect world, you would go to the ``group_vars`` of those servers, and add the new guy:

```yaml
admins:
  - name: "newguy"
    sudo: false
    sshpubkey: ssh-rsa ...
```

This does not work with Ansible, because the second declaration would overwrite the first, and now only your new guy has access to the servers! The only solution to that problem (as far as I can tell), is to use a differently named key:

```yaml
new_admins:
  - name: "newguy"
    sudo: false
    sshpubkey: ssh-rsa ...
```

Then, merge those keys in the role you use to create users:

```yaml
- user:
    name: "{{ item.name }}"
    state: present
  with_items: "{{ admins + new_admins }}"
```

This does not scale: As soon as you need another distinct access rule, you have to add **another** key, and the cycle repeats.

## Speed

Simply put, the execution speed of Ansible playbooks is horrendous. This is due to its architecture, which requires SSH connections to all servers you run playbooks on. It might not be a problem for you, but the workarounds that were created (stuff like [ansible-pull](http://docs.ansible.com/ansible/latest/cli/ansible-pull.html) + cron) show that it is a problem for a significant number of people.

## Dry runs

When running Ansible playbooks, you can pass `--dry-run` to the `ansible-playbook` command, and Ansible will show you what would be done, not actually executing anything.

Except that this does not work reliably. This happens most often when you add a YUM/APT repository, to the install a package from that repository. If the repository is not yet present on the server, the (no-op) package installation will fail with a "package not found" error.

There are workarounds, like using ``when: not ansible_check_mode``, but these are still just that: workarounds.

Ansible does not give me the same sense of reliability as e.g. puppet does.

# My opinion

It might sound weird after the above but I have to say: I really like Ansible. Not so much for configuration, but for orchestration. There is simply nothing better.

I love having repetitive tasks written down as code, having them reviewed before running them. Documentation having copy-paste shell snippets now simply link to an Ansible script that does the same, but repeatably, and without accidentially pasting into the wrong terminal window ;)

Slap something like [Rundeck](https://www.rundeck.com/open-source) or [StackStorm](https://stackstorm.com/) in front of Ansible, and you can give fine-grained access to your playbooks to other people, together with logging, auditing, and integration for your favourite tools.

But, Ansible as configuration management tool has not convinced me yet. As old school as it is, Puppet gives me more confidence while using it. Ansible still has a lot to do in that regard, but with lots and lots of people working on Ansible, together with being backed by RedHat, I hope it will get even better in the future!

<!--
---

But, as far as serverless/self-bootstrapping deploys go, it's less common. Ansible has less of a "culture of dependencies"; the simpler, more approachable-looking nature of the Ansible playbook format seems to lend itself to people one-offing whatever they need rather than looking for best-practices solutions that already exist. Because of this, there's no real Berkshelf equivalent for Ansible. The tooling doesn't exist, outside of Tower (sorta), because nobody wants it, and nobody wants it because the tooling doesn't exist. So the people who are doing with Ansible something similar to the Chef Zero stuff I mentioned above are mostly home-rolling it. (I just use a S3 bucket as a Minimart berkshelf endpoint and move on with my day.)

Last-mile configuration is also tricky. In my Chef Zero stuff, I use CloudFormation metadata to provide Chef attributes. You can do something similar with Ansible...but it's duct-tapey. There are times when simple is better; IMO, Ansible's core tooling errs too far on that side and the ecosystem has not caught up to make more rigorous approaches really viable.

 Calling that "serverless" is something of an abuse of the term. You can call it "push-based" rather than "pull-based" (a Chef/Puppet model), but there is definitely a "server" to be had--it's the machine running SSH and with the canonical datastore. It is--and this is one of many reasons I don't like Ansible very much--just a pretty poor server and often the developer's workstation.

"Serverless" would be more like what I described with regards to Chef Zero, where a machine, as it bootstraps, is able to fetch its playbooks from somewhere and self-execute with some sort of sourceable configuration data. The standard Ansible workflow is not only not "serverless", but it is antithetical to cloud-friendly scaling and fault-tolerance practices. (Think about how you're going to manage auto-scaling groups with it. It hurts.)

 Sure. But that's pretty awful. ansible-pull relies on a git repository, which relies on key provisioning, which means that you need to configuration-manage your configuration management and you don't have a stump-dumb, easy solution for it in any major cloud. And you have no dependency management (submodules, at best, are not dependency management), so I hope that you've vendored (which is gross) all of your dependencies.

This really is what I do for a living. I'm speaking from a position of entirely too extensive experience when I say that Ansible has no good solution here in common use. If I thought Ansible was good enough for me to be spending a lot of time with (it's not, and I advocate that clients not use it if they have a choice), I'd have probably already had to write it.

As far as machine images go, they are an optimization, not a core system. Your configuration management systems need to be able to bootstrap from either an AMI, to lay on last-mile (configuration, as opposed to setup, stuff) and converge any updates since the last AMI build, or to start from scratch. And that is another weakness of Ansible; writing idempotent Ansible scripts is significantly harder than it needs to be.
-->
