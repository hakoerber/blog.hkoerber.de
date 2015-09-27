---
title: "Rust vs. Go: Error Handling"
date: "2021-09-26T19:22:05+02:00"
description: ""
tags:
- development
- rust
- golang
- go
---

Recently, I've been diving into the [Go](https://golang.org/) programming
language.  I have to say that I'm **very** fond of many of its aspects: The
standard library is plain awesome, especially functionality related to HTTP.
Async via goroutines and channels feels very ... well-thought-out? Static
typing feels like a breath of fresh air. I'd rather the compiler scream at me
during compilation than my Python script breaking during runtime. The
deployment story is very easy due to statically compiled binaries. The
compilation is fast enough, and the runtime speed is amazing (though this might
be unfair when comparing it to Python).

But there is one thing that I'm not too happy about. It's the following, and if
you've ever written Go, you know it all too well most likely:

```go
result, err := somefunc()
if err != nil {
    // panic
}
```

This is the extend of Go's error handling: The convention that functions return
a `(value, error)` tuple, with `error` being `nil` if everything went well. So
many function signatures look like this (using [the stdlib function to open a
file](https://pkg.go.dev/os#Open) as an example:

```go
func Open(name string) (*File, error)
```

Now, there are a few drawbacks to that approach. The first one is the
**verbosity**. In any Go codebase, you'll see  `err != nil` littered
everywhere.  This is, honestly, not too bad. You get used to it. But there is a
bigger problem.  Take a look at following snippet:

```go
configFile, err := os.CreateTemp("/tmp", "config")
errorFile, err := os.CreateTemp("/tmp", "error")
if err != nil {
    return fmt.Errorf("failed to create temp file, %s", err)
}
```

Looks sane at first glance, but what happens when the first call to
`CreateTemp()` fails? Well, nothing, or at least no error handling for sure.
The `err` variable is redeclared in the next line, effectively overwriting any
error that happened.  If the second call succeeds, the program will continue,
even though `configFile` is not safe to use.

So, the verbose ceremony around error handling is not the problem. But you must
never **forget** it. Whenever you get an error variable, you **must** check it.
If you don't, you got a bug!

## How can this be done better?

I've been playing around with [Rust](https://www.rust-lang.org/) on and off for
years now, never really getting around to properly diving into it. It's very
complex and quite unlike all other languages I've worked with so far. By now, I
know enough to at least understand most Rust snippets.

On thing that Rust just gets **right** in my opinion is its approach to error
handling.

### Short Rust Type System Detour!

To lay the groundwork for the dive into error handling, we first have to quickly
talk about a few Rust data types. You have to know that Rust has a very rich
type system. One of the types that you won't have in Python or Go are [Sum
Types](https://en.wikipedia.org/wiki/Tagged_union), called
[Enums](https://doc.rust-lang.org/book/ch06-00-enums.html) in Rust.
Effectively, a sum type is a type that can hold a value that is one, and only
one, of a known list of types.

For example, Rust does not have an "empty" value, e.g. `None` (Python) or `nil`
(Go).  Instead, there is an
[`Option`](https://doc.rust-lang.org/std/option/enum.Option.html) Enum, which
is defined like this:

```rust
enum Option<T> {
    None,
    Some(T),
}
```

`T` is a generic type parameter here, so you can use `Option` with any value.
Effectively, an `Option` can either be "something" (`Some`) or "nothing"
(`None`).  And here comes the big advantage over `nil` or `None`: You cannot
accidentally get a `None` when you expect a value. Whenever you have an
`Option`, the compiler forces you to handle both cases: Either you got
something, or you got nothing. The compiles **forces** you to do this, or your
program will not compile. Assume we have some function that returns an option
that can either be nothing or an integer:

```rust
let r: Option<i32> = returns_option();
```

You will not be able to use `r` like an integer:

```rust
let x = r * 2;
```

The compiler complains:

```
error[E0369]: cannot multiply `Option<i32>` by `{integer}`
  --> src/main.rs:
   |
   |     let x = r * 2;
   |             - ^ - {integer}
   |             |
   |             Option<i32>
```

It's because you don't have an integer, you have an **Option** that **can** be
an integer. To get the value, we have to match all possible cases:

```rust
let actual_value = match r {
    None => {
        panic!("Got no value!");
    },
    Some(i) => i,
};
```

Instead of panicking, you'd most likely have some actual error handling or
course ;) Note that the compiler enforces that you handle any value that your
Enum can have. Let's say you forget to handle the `None` case:

```rust
let actual_value = match r {
    Some(i) => i,
};
```

Rust won't like that:

```
error[E0004]: non-exhaustive patterns: `None` not covered
   --> src/main.rs:
    |
    |     let actual_value = match r {
    |                              ^ pattern `None` not covered
```

The compiler even tells you which case you did not handle.

Note that you won't have to use `match` every time. There are a lot of
convenience methods on `Option`, just take a look at [the
documentation](https://doc.rust-lang.org/std/option/enum.Option.html).

For example, our code above that called `panic!()` on a `None` value could be
simply rewritten like this:

```
let actual_value = r.unwrap()
```

`unwrap()` gives you the `Some` value, or panics if there is a `None` value.
Especially `unwrap_or_else()` is quite helpful.

### Rust Error Handling

So, how can sum types help with error handling? Easy: Rust uses the so-called
[`Result`](https://doc.rust-lang.org/std/result/) type whenever a function can
return an error or an actual value.

`Result` is defined like this:

```rust
enum Result<T, E> {
   Ok(T),
   Err(E),
}
```

This is quite similar to `Option`, right? `Result` can either be the expected
value (`Ok`) or a certain error (`Err`). Conceptually, this is quite close to
Go. The big benefit is that it's enforced **at the type level** that you cannot
forget to handle the error. As we saw above with `Option`, Rust won't even let
you compile your program if you don't handle the `Err` case. And like `Option`,
`Result` has all those convenience functions like `unwrap()`.

`Result` is used *everywhere* in Rust. Remember Go's `Open()` function:

```go
func Open(name string) (*File, error)
```

In Rust, the equivalent function looks [like
this](https://doc.rust-lang.org/std/fs/struct.File.html#method.open)[^1]:

[^1]: This is heavily simplified. Actually, the `Result` type in ``std::io`` is
different from the `Result` type we talked about. Its `Err` variant is not
generic, but always has the `std::io::Error` type. Also, I left out generics.
The actual signature looks like this: `fn open<P: AsRef<Path>>(path: P) ->
Result<File>`

```rust
fn open(path: Path) -> Result<File, std::io::Error>
```

## Error Bubbling

Error Bubbling refers to the practice of throwing an error up the call stack to
the caller function from the perspective of the called function. In other
words, if our function cannot handle the error, we just return it to the
function that called us and hope they know what to do.

In Go, this looks like this:

```go
func ourFunction() (int, error) {
    i, err := someFunc()
    if err != nil {
        return 0, err
    }
    // do something with i
}
```

The equivalent in Rust might look like this:

```rust
fn our_function() -> Result<i32, String> {
    let r = some_function();

    match r {
        Err(e) => return Err(e),
        Ok(i) => {
            // do something with i
        }
    }
}
```

Wow, this is even more boilerplatey than Go! But there is a nice little
operator, the question mark (`?`), that can be used in all functions that
return `Result`.  It's similar to `unwrap()`, but instead of panicking on `Err`
values, it bubbles them up to the calling function. So our code could be
rewritten like this:

```rust
fn our_function() -> Result<i32, String> {
    let i = some_function()?;
    // do something with i
}
```

That is **much** better, don't you think?

## Conclusion

Go gets a lot of things right. But error handling is not one of them, and Rust
shows how it can be done better. Less boilerplate and compiler-time checks for
error handling.

If you want to read more about error handling in Rust, read the chapter
["Recoverable Errors with
`Result`"](https://doc.rust-lang.org/book/ch09-02-recoverable-errors-with-result.html)
from the **awesome** Rust Book.

