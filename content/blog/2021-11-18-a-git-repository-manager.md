---
title: "A Git Repository Manager — in Rust"
date: "2021-12-04T12:43:42+01:00"
description: "Managing multiple repositories in a single place &emdash; with Rust"
tags:
- rust
- git
- tools
---

I'm heavily using git both at work at for my personal projects. Over time, I
ended up with a quite substantial amount of git repositories. For now, I've
just been managing them manually. This worked well, but when setting up a new
machine, I'd have to either restore a backup or do a lot of `git clone`s
manually.

I'm also a huge proponent of $whatever-as-code, especially Terraform. I like to
just have a configuration plus a tool that takes that configuration to
configure $whatever.

So, I decided to build a tool to do that: Have a config of my git repositories,
and the tool makes sure that everything is cloned & configured correctly. And
so, the [git repository manager
(GRM)](https://github.com/hakoerber/git-repo-manager) was born.

I chose [Rust](https://www.rust-lang.org/) for this project. I already used
Rust for a few very small projects (<100 LOC), and for the backend of a
[package list application](https://github.com/hakoerber/packager). I'm really
fond of a lot of aspects (see [this blogpost about error handling]({{< relref
"./2021-09-26-error-handling-rust-vs-go.md" >}}) for example).

To be honest, the project is 50% "scratching my own itch" and 50% "I want to
learn Rust and need a project". I think it succeeded for both, as I'm
dogfooding GRM right now, both at home and at work, and I'm also starting to
get a good grasp of Rust.

In the meantime, GRM gained a few additional capabilities. For example, you can
generate a configuration from an existing tree of git repositories (would be
quite a hassle to do this manually). Also, I wrote some code to manage [`git
worktrees`](https://git-scm.com/docs/git-worktree), which makes it much easier
to juggle multiple branches at the same time.

In the following, I'll list the resources I used while learning rust and
writing GRM, and a few lessons about Rust in particular.

# Resources I used

The [rust book](https://doc.rust-lang.org/book/) is absolutely awesome. It's
like a tutorial through the rust language that will also act as a reference for
later when you look up concepts. I read it once from start to finish in the
beginning. Of course, I couldn't remember everything, but it was good to
already have heard of some concepts when I encountered them later on.

I also cross-read the [Rustomonicon](https://doc.rust-lang.org/nomicon/), which
aims to explain in detail how `unsafe` works in rust. I haven't used `unsafe`
at all for GRM, but it was still valuable to know about the concepts.
Additionally, the Rustomonicon is just an exciting read.

There is another book called ["Learn Rust With Entirely Too Many Linked
Lists"](https://rust-unofficial.github.io/too-many-lists/).  It hammers home
some concepts like ownership, while giving a thorough introduction into Rust
stdlib components like Iterators, `Rc`, and `Arc`.

Last but not least, I cannot stress how **awesome** the rust reference
documentation is. When starting, you'll most likely work a lot with the
`Option` and `Result` types. Now take a look at the [documentation for
`Option`](https://doc.rust-lang.org/std/option/): It's not just a list of
available methods. No, it also gives an intro about use cases for `Option` and
when you'll encounter it, how to use it with `match`, and groups the methods
into different use cases and describes them

# What I learned about Rust

* [Serde](https://github.com/serde-rs/serde) is everywhere, and it's awesome. I
  already used it for [packager](https://github.com/hakoerber/packager) for
  JSON (de-)serialization in the REST API. For GRM, I used it to parse the TOML
  configuration and for command line parsing with
  [clap](https://github.com/clap-rs/clap).  In my experience, you'll catch 90%
  of logical parsing errors already at compile time, and you're forced to
  handle all edge cases during runtime.

* Dependencies grow quite quickly. I'm at ~100 dependencies with 8 direct ones,
  this means that >90% of dependencies are transient. I have to say that it
  kind of reminds me of the disastrous situation with NPM, albeit not quite as
  bad.  I wrote a [little python
  script](https://github.com/hakoerber/git-repo-manager/blob/4eb88260c8a28f3e2f01ef1fd943d69e2c336f89/depcheck/update-cargo-dependencies.py)
  that whether there are new versions available for the direct dependencies,
  but this is still not 100% (for example, it currently does not include
  transitive dependencies, nor do I pin those anyway). In any case, I also have
  to emphasize that almost all crates I encountered are of **very** high
  quality and actually provide some real value.

* While the concepts behind error handling are super cool and quite easy to
  grasp, applying them in a "real" project needs some experience. I'm not good
  at that yet, as I'm mainly just returning error messages directly via
  `Result<T, String>`.  It works for now, but I'm 100% sure that there are much
  better ways. Using the
  [`std::error::Error`](https://doc.rust-lang.org/std/error/trait.Error.html)
  trait would already be a big upgrade, including the possibility to nest or
  wrap errors.

* The crate/module structure just *makes sense*. Every programming language
  does this differently. I have to say that Rust's way is the most sensible to
  me for now. Maybe my opinion changes when I work with multiple crates via
  cargo workspaces, we'll see.

* Productivity was much higher than I expected. I was quite afraid of the
  borrow checker at first, but it turned out to not be a problem. The few times
  it complained, it turned out that the code was actually written weirdly and
  could be improved anyway. Of course, GRM is not making much use of advanced
  Rust features, so maybe I'll have more issues in the future.

* Similar to the previous point, Rust was surprisingly well suited for a "high
  level" (i.e. abstracted from the hardware) project like GRM, even though it's
  mostly popular in the "low level" space (i.e. hardware programming, "close to
  the metal") for now (but I feel like this is already rapidly changing). It
  was quite easy to build high-level abstractions.

* The Rust compiler is extremely helpful. The error messages are very precise,
  and there is often a recommendation how to fix the problem. In 95% of the cases,
  this is exactly the way to fix the problem.

* The tooling around cargo is quite intuitive and comprehensive. With `cargo
  fmt` and `cargo clippy`, formatting and linting is taken care of. All kinds of
  builds and releases are also handled via `cargo`. In short, I'm quite a fan.

---

That's it! In short, Rust is awesome. If you want, check out
[GRM](https://github.com/hakoerber/git-repo-manager) ([Link to the
documentation](https://hakoerber.github.io/git-repo-manager/)).
