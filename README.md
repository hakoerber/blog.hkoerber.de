## Building

Build requirements (Fedora 25):

```
# dnf install rubygem-bundler ruby-devel libxml2-devel redhat-rpm-config
```

```
$ git clone https://github.com/whatevsz/blog.haktec.de.git blog
$ cd blog
$ bundle install
$ bundle exec jekyll serve .
```

Now open [http://localhost:4000](http://localhost:4000) in your browser.

## Used Software

This site uses [jekyll](https://jekyllrb.com/) with the [minimal mistakes](https://github.com/mmistakes/minimal-mistakes)
theme.
