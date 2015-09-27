---
title: "On Dependency Versioning"
date: "2021-09-25T10:58:59+02:00"
summary: "You pin your dependencies, don't you?"
tags:
- development
- devops
- python
- security
---

When I'm talking about "dependencies" here, I'm talking about all the stuff
**around** your code that is **not** your code. Usually, includes stuff like
the following:

* The language. Either your compiler (for languages like Rust or Go) or your
  interpreter (Python, PHP, ...).
* Third-party modules. This may include pip modules for Python (more on that
  later) or crates for Rust.
* The environment the application is running in. If you're hip and using
  container technologies, this includes a complete operating system. This is
  mainly whatever you're basing your image off (`FROM` in your `Dockerfile`),
  plus each package installed via `apt-get` or similar.
* The platform your application will run on. Maybe Kubernetes or AWS ECS, but
  also EC2 would count as a platform dependency.

All these dependencies will be defined somewhere, often in many different
places. In this article, we'll talk about how we handle the *versions* of all
of these dependencies. There are several approaches, each with its
upsides and downsides. The approach you pick will influence the
reproducibility, maintainability, and stability of your deployments. So get it
right!

# Dependency pinning

If you're a Python programmer, you're most likely familiar with the concept of
`requirements.txt` files. For everyone who isn't, here's a short rundown:

When you use third-party libraries in Python, your first destination will most
likely be [https://pypi.org/](PyPI), the Python Package Index. It's a huge
collection of hundreds of thousands of Python libraries. To use one of those,
you'd use the [pip command-line tool](https://pypi.org/project/pip/), which
downloads and installs these libraries to your machine:

```bash
pip install requests
```

This would install the super helpful
[requests](https://docs.python-requests.org/en/latest/) library, which makes
HTTP requests much easier than the Python standard libraries'
[urllib](https://docs.python.org/3/library/urllib.html).

Now imagine the following scenario: You finished developing your application,
using requests as seen above. All is well. Until, a few days/weeks/months
later, you (or someone else) revisit the project. You run the `pip` command
again. But in the meantime, the requests project released a new version that
is incompatible with the version you originally coded against. Boom, something
breaks, and someone is sad and/or angry.

How could we have prevented this? By *pinning* the requests library to
a certain version. This can be done with `pip`:

```bash
pip install requests==2.26.0
```

Now, of course, remembering this version is hard, and it gets even worse when
you use more libraries. But `pip` provides a way to generate a file containing
all libraries and their dependencies: `pip freeze`. The convention is to save
this list into a file called `requirements.txt`:

```bash
pip freeze > ./requirements.txt
```

This is what the `requirements.txt` file looks like:

```
certifi==2021.5.30
charset-normalizer==2.0.6
idna==3.2
requests==2.26.0
urllib3==1.26.7
```

As you can see, apart from the `requests` library, there are also other
libraries. Those are dependencies of "`requests`" itself, so-called "transitive"
dependencies.

So now you commit this `requirements.txt` to your git repo. When you revisit
the project later, you can use `pip` to get the exact versions specified
initially:

```
pip install -r ./requirements.txt
```

And wohooo, no breakage!

This is what dependency pinning means: Specifying the exact version of all
your dependencies. Something similar to Python's `requirements.txt` exists
in almost all languages:

* In NPM, this would be the [`package-lock.json`](https://docs.npmjs.com/cli/v7/configuring-npm/package-lock-json)
* Go calls it `go.sum`
* Rust uses [`Cargo.lock`](https://doc.rust-lang.org/cargo/guide/cargo-toml-vs-cargo-lock.html)
## Why?

Now that we know what dependency pinning is, the question is: Why? What's the benefit? Or rather: What happens if we don't pin our dependencies?

As said above, without dependency pinning, a later build might break, even
though nothing was changed in the code itself. But even worse, *when* it
breaks, there is no way to go back to a known-good state. The only hope
is that you still have the build artifact laying around (e.g. the old
Docker image).

On a more abstract note, the **time** of the build now is an
implicit **input** of your build. As soon as you've built an artifact,
there is no way to reproduce that exact artifact ever again.

This makes rollbacks impossible, so your only way is to "fail forward",
to adapt your code to the new versions or work around the issue.

If you adhere to the concepts of "everything as code" and "everything
should be tracked in version control", this is not desirable, as there
is a very important aspect of your application that is not tracked in
code or version control.

Dependency pinning solves all of those problems. If a new version of a
dependency breaks, you just go back to a known-good state in git and rebuild.
Solving update issues become a simple `git revert`. You can even go back
in time and recreate your application from one year ago (maybe
to show progress to management, or maybe just for fun).

Additionally, you gain *visibility*: It's always clear which versions of
all of your dependencies you are currently using. This helps with security
analysis and also eases development. You can be sure which version you're
coding against.

It also makes it possible to hold back updates explicitly. Let's say the
`requests` library from above releases a new major version that breaks
compatibility (which it's allowed to do when adhering to
[semver](https://semver.org/lang/de/)!. Without pinning, we'd have to update
our code to use the new API right then and there. If we pin our dependencies,
we can selectively hold back this update until we get around to updating our
code.

## But ...

... dependency pinning comes with a huge drawback: If you don't update the
pinned dependencies, no-one else will. That's kind of the idea of the whole
thing, but it also means that all versions are permanently getting more and
more out of date. It's on you to update those dependencies.

And in my experience, no-one will. As long as updating is a manual process,
it's just not going to happen. I've seen 30-lines `requirements.txt` files
that have not been updated in **years**. You can be sure that at least 50% of
those libraries have released at least one update that you should **urgently**
use, e.g. due to some security issues that have been fixed in the meantime.

So, why does no-one (including myself) update their `requirements.txt` (or all
the other places where you pin your versions)? First, it's just not "fun".
Think about it: At best, you don't immediately break something. At worst, you
break the whole build. There is the benefit of increased security and
bug fixes, but that is not immediately visible.

And that's the second reason: If you have the choice between dependency
updates and working on a new feature, you're automatically inclined to do the
latter because this will sound much better in the next standup. This is
a function of the popular approach to security updates. They do not have an
immediate benefit. The actual benefit is something **not happening**, which is
very hard to sell. And 95% of the time you get lucky, so you don't see the
benefit even in hindsight.

This is not something a single developer can do something about. It's
a cultural thing: Features sell, features are visible. "Security" is something
that just costs time and money, and "nothing will happen to us" anyway.

So what's the remedy? Well, we're all using computers after all, and computers
are very good at doing what we tell them. So let our computers update the pins
for us! I don't mean to open a regular Jira ticket so you don't forget to
update your dependencies manually. I'm talking about complete automation, with
maybe a short, super simple manual review step in the end (pull requests!).

It could be a simple script that runs regularly (via CI) and checks all your
dependencies against the latest upstream version. If there is a new version
available, it updates it in your git repository and creates a pull request.

The big issue here is confidence: How do you know that the new version is not
going to break? Well, the only sane way to handle this is with a comprehensive
test suite. And I'm not just talking about unit tests. What you need is a test
suite that you can hand your build artifact and it's going to tell you "yes"
or "no". If you're confident in that test, you can also be confident that
dependency updates are not going to break your application.

# In Practice

I actually have something like that for my personal "cloud". It's a very ugly,
very bespoke Python script that runs daily via Drone CI and checks all
dependencies against their latest upstream versions. It opens a pull request
in my Gitea instance if there are updates available. This way, I can decide
when and what to update. I don't have a testing suite as it's just for me, and
I don't really care if my Nextcloud is down for a few hours until I get around
to fixing it. But you get the idea.

If you want to take a look, here is the script:
[Link](https://code.hkoerber.de/hannes/_snippets/src/branch/master/autoupdate.py).
As you can see, it's very bespoke. It's also quite horrible code (or rather
"grown organically"). The thing is: **It does not matter**. It's still 100%
better than not doing automated updates at all. And as there is still the manual
step of merging the pull request, I can catch any errors that arise. Here is a
screenshot of a merge request that is produced by that script:

<hr>

{{< figure src=/assets/images/dependency_pinning/merge_request.png caption="An automatically generated merge request in Gitea">}}

<hr>

In a more important environment, you'd of course also have a testing step as
described above. Also, it might be possible to first deploy to a separate
staging environment, so you can be extra sure that nothing will go wrong. The
thing is, you should have all of this *anyway*. A test suite and a testing
environment are crucial for any serious application development, so you might
already have one ;)

# Examples of Dependencies

So, what should be pinned? We already talked about the obvious stuff above:
Programming libraries. But there is more:

* The docker base image, i.e. whatever follows the `FROM` in the `Dockerfile`. You're
  hopefully not using the `latest` tag, but a more specific one. This tag needs to
  be updated as well!
* Any packages you install. This also means that you have to pin the packages you
  install via APT:

  ```Dockerfile
  FROM docker.io/debian:bullseye-20210902

  RUN apt-get update && apt-get install -y \
    git=1:2.30.2-1 \
    python3-django=2:2.2.24-1 \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*
  ```
* Your configuration management and IaC tooling. Yes, you should track the Ansible
  and Terraform versions you're using in git.
* Any software you use in your CI pipeline, e.g. the used Docker containers for
  GitLab CI or Drone.
* Any external services you use. Let's say you're on AWS and using ECS Fargate.
  You should track (and automatically update) the [Fargate Platform
  Version](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/platform_versions.html)!

# Conclusion

Pinning your dependencies is not an easy task. Together with the automation, you'll
have to spend considerable time to get it going. But as soon as everything is
set up, there is not much left to do, as most of the work will be done by your
automation system. You can then reap the benefits that pinned versions bring:
Reproducibility, visibility, stability, and confidence in your application.
