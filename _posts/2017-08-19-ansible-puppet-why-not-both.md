---
title: Ansible or Puppet? Why not both!
date: 2017-12-22 09:58:25+02:00
tags: ansible puppet config
excerpt: Using the right tool for the right job
---

{% include toc %}

# Introduction

At the [7th DevOps Camp](https://devops-camp.de/devops-camp-12-14-mai-2017/) in May 2017 I listened to a very interesting talk by [Frank Prechtel](https://twitter.com/frankprechtel) and [Andreas Heidoetting](https://www.xing.com/profile/andreas_heidoetting) called "Welche Software für Infrastructure as Code? --- Puppet vs. Chef vs. Ansible vs. Saltstack - welches Tool für welchen Einsatzzweck?" (Which software for Infrastructure as Code? --- Puppet vs. Chef vs. Ansible vs. Saltstack - which tool for what use case?).

In that talk, they arranged those tools along two axes:

* *Procedural* vs. *Declarative*
* *Client-Server* vs *Client-only*

Ansible and Puppet differ on both of those metrics, which Ansible being a procedular client-only system and puppet being a declarative system following a client-server architecture.

In this post, I will focus on the first point, and how the differences lead to each system being stronger than the other in different problem domains.

First, let's look into the concept of "state" applied to configuration management

# State

Configuration management is all about managing state. The state encompasses everything you can think of on the target system: Contents and permissions of files, what processes are running, what packages are installed, users, groups, network configuration, device management and much more, you get the idea.

Now, you generally have a number of "target" states; there are simply the different server roles you have. You might have web servers, database servers, storage servers, and so on. Every server in one of those roles only differs minimally from other servers of the same class. For example, network configuration might be slightly different (IP addresses).

It is in your interest to always assert which state a system is in. We call the discrepancy between the actual state and the declared state "configuration drift". Configuration drift can generally be intoduced two different ways:

* Your actual state changes, and those changes were not introduced by the management system. This is usually the case when you change something on your systems manually (i.e. SSH into them)

* Your declared state changes, without those changes being applied to the systems. This happens when you neglect to do a configuration run after changing your configuration system.

The first point can be remedied by making the declared states as all-encompassing as possible, and as flexible as possible. When it's easier to go through your configuration mangement system to make changes --- even small ones --- there is not need to SSH into a box.

To remedy the second point, you need to apply all changes in the declared state to your systems as easily as possible, preferably automatically. Setting up a CI pipeline that runs your configuration management on every commit in the configuration repository makes sure that configuration drift does not begin to creep up.

To sum it up, any configuration management system benefits from the following:

* Broad scope, i.e. you can tune every parameter of the managed system
* Flexibility, i.e. you can easily adapt the system to new requirements (new things to manage)
* Speed, i.e. applying the declared state takes as little time as possible

# Procedural vs. Declarative

Now that we have a good idea of what "state" is, we can draw the destinction between the procedural and the declarative approch.

In the context of configuration management systems, "prodecural" vs "declarative" relate to *how* the system brings the managed entity (most often a server) into a new state. So, it's not about what you get in the end (state-wise), but the way there.

The descriptions here are very theoretical, and do not apply cleanly to the real world (spoiler: No configuration management system fits perfectly into one of those categories). Nevertheless, thinking about those two extremes helps with understanding the strenghts for each system (more on that later)

## Declarative

A declarative approach means we have to *declare* (duh) the state we want to have on the system (often in some kind of DSL), and the configuration management system's task is to transition whatever state it finds into the declared state.

We define the target state (green), and do not have to care about whatever state there currently is on the system, nor about state transitions. This is all in the tool's hands.

{% digraph some graph title %}
rank = same
rankdir = LR
ranksep = 1.5
margin = 0.5

node [
    color = black
    fontsize = 14
    shape = box
    fontname = sans
    margin = "0.5,0.3"
]

edge [
    color = black
    fontsize = 14
    shape = plaintext
    fontname = sans
    style = dashed
]

"target state" [
    fillcolor = green
    style = filled
]

"state 1" -> "target state"
"state 2" -> "target state"
"state 3" -> "target state"
{% enddigraph %}


The cool thing about the declarative approach is that it scales lineary with the number of states: When you introduce a new system with a new target state, you only have to write one declaration for that system, and you're done. It also gives you a nice sense of confidence: When our declaration is sufficently comprehensive, we can be certain that our system is in line with our configuration.

The big problem with that approach is the complexity it brings to the tool itself. The tool has to ananlyize each resource it is expected to bring into the desired state and figure out the steps it has to take. This might not directly impact you (it's more of a problem for the guys writing the config management tool), but this complexity might (and does, in my experience) leak into the use of that system, through leaky abstractions.

Also, to be really useful, a declarative configuration management system needs to be all-encompassing. Let me tell you why.

You might have experienced the following scenario: Assume you have some kind of `conf.d` directory. This is common to split configuration of a program into several files. Two examples that come to my mind are cron (`/etc/cron.d`) and rsyslog (`/etc/rsyslog.d`). There are usually three ways how configuration files might end up in that directory:

* defaults, installed with the package itself
* files from other packages (this is done extensively with `/etc/logrotate.d`
* files from your configuration management system

To actually be sure that, regardless of what's currently in that directory, you end up with the files you want, your configuration management tool has to "take over" that whole directory.

Similarly, a true delarative tool would remove all packages from a system that it does not know about. To turn it around, this means that you have to *tell* the system about all packages you want to install.

Now, sometimes this is exactly what you want (you actually want those superfluous packages gone and sometimes you can split a `conf.d` directory into multiple ones) but this case nevertheless shows that the default state of a declarative tool it to "own" the system.

Pros:

* Independence of current states makes it suitable for heterogenous environments
* Confidence in the target state
* Scales linearily with the ammout of different states
* Idempotence "built-in"

Cons:

* The tools need to be quite heavy and complex
* To leverage the whole power, you need to delare your whole system and let the configuration management system "own it"

## Procedural

A procedural system simply applies a set of predefined state transitions (green) to reach a new state:

{% digraph some graph title %}
rank = same
rankdir = LR
ranksep = 1.5
margin = 0.5

node [
    color = black
    fontsize = 14
    shape = box
    fontname = sans
    margin = "0.5,0.3"
]

edge [
    color = green
    fontsize = 14
    shape = plaintext
    fontname = sans
    style = dashed
]

"state" -> "new state"
{% enddigraph %}

With the state transition being predefined, this means that the new state is dependent on the old state. As long as you can be sure of the state of the system, this is not an issue. But, as soon as you have any configuration drift, for example introduced by manual intervention, your have a new state and therefore need a new state transition:

{% digraph some graph title %}
rank = same
rankdir = LR
ranksep = 1.5
margin = 0.5

node [
    color = black
    fontsize = 14
    shape = box
    fontname = sans
    margin = "0.5,0.3"
]

edge [
    color = green
    fontsize = 14
    shape = plaintext
    fontname = sans
    style = dashed
]

"state 1" -> "new state"
"state 2" -> "new state"
{% enddigraph %}

As you can see, the more initial states you have, the more state transitions you have to maintain. Now imagine you have different target states, and watch the complexity exploding:

{% digraph some graph title %}
rank = same
rankdir = LR
ranksep = 1.5
margin = 0.5

node [
    color = black
    fontsize = 14
    shape = box
    fontname = sans
    margin = "0.5,0.3"
]

edge [
    color = green
    fontsize = 14
    shape = plaintext
    fontname = sans
    style = dashed
]

"state 1" -> "new state 1" [headport="w"]
"state 1" -> "new state 2" [headport="w"]
"state 1" -> "new state 3" [headport="w"]
"state 1" -> "new state 4" [headport="w"]
"state 2" -> "new state 1" [headport="w"]
"state 2" -> "new state 2" [headport="w"]
"state 2" -> "new state 3" [headport="w"]
"state 2" -> "new state 4" [headport="w"]
"state 3" -> "new state 1" [headport="w"]
"state 3" -> "new state 2" [headport="w"]
"state 3" -> "new state 3" [headport="w"]
"state 3" -> "new state 4" [headport="w"]
{% enddigraph %}

The upside of the procedural approach is that the state transitions are quite simple. When contrasted with the declarative approach, instead of saying "this is how I want the result to look like", one can simply say "do this!"

Pros

* State transitions are relatively simple

Cons

* Does not tolerate any configuration drift
* Care must be taken for the transitions to be idempotent

# Back to our tools

How do Puppet and Ansible fit into those categories? Well, they both have a part of both.

Ansible, with its concepts of "plays" and "tasks", fits better into the procedural approach, even though most modules are declarative and idempotent. Take the core modules as an example: Both the ``file`` and the ``service`` module define what you want the file or service to look like.

On the other hand, Puppet is --- at its core --- fixated on the declarative approach. Colloquially, if your ``puppet agent`` run changes some resource every time it is run, "you are doing something wrong". Almost all modules you encounter, even third-party ones, give you some kind of interface to define what you want their resource to look like, and do some magic in the background to make it so.

So while both tools can fit both styles, they are not equally suitable for the jobs. Puppet is, hands down, the better declarative tool, but you use a needlessly complex tool when you just want to define state transitions. On the other hand, ansible is much more fitting for the procedural approach, and you will have to jump through a lot of hoops an have to be very careful to use it in a proper declarative manner.

# Which tool to chose

TL;DR: If you have a mutable infrastructure, use Puppet. If you have an immutable infrastructure, use Ansible. If you have both, use both.
