FROM fedora:27

RUN yum -y install \
    gcc \
    graphviz \
    make \
    ruby-devel \
    rubygem-bundler \
    redhat-rpm-config \
    zlib-devel \
&& gem install bundler --version 1.16.1

ADD Gemfile.lock /
ADD Gemfile /

RUN bundle install
