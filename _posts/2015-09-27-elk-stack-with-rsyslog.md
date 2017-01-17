---
title: Using The ELK Stack With Rsyslog
date: 2015-09-27T18:06:15+01:00
tags: homelab logging elk elasticsearch logstash rsyslog json grok
---

{% include toc %}

This post will detail my setup that uses [rsyslog](http://www.rsyslog.com/) to send JSON-formatted log messages to an [ELK stack](https://www.elastic.co/webinars/introduction-elk-stack).

## The result

Let's start with an overview of what we get in the end:

![ScreenShot]({{ site.url }}/assets/images/kibana.png)

## The log structure

The setup uses rsyslog to send two different kinds of logs to the logserver: the good old `syslog`, and logfiles written by applications, for example nginx access logs. Both will be formatted as JSON and sent to the logserver via TCP for further processing. Every message has certain attributes that describes their origin:

  * `host`: identifes the host that sent the message, subfields are `ip` and `name`
  * `type`: can either be `syslog` or `application` and distinguishes a syslog entry from an application logfile
  * `content`: the actual log message

`content` can either be a string (in case of a logfile, this is simply a line in the file) or a dictionary that contains attributes of the message. For syslog, these attributes are:

  * `host`: syslog host field
  * `severity`: syslog severity
  * `facility`: syslog facility
  * `tag`: syslog tag
  * `message`: syslog message
  * `program`: syslog program

On the server side, the `content` attribute can be parsed depending on the application. For example, nginx access logs can be parsed to include response code, verbs, user agents and many more.

All of this makes for easy searching in Kibana. Here are some examples for filters that can be used:

Get all messages from a specific host:

```
host.name:"host.domain"
```

Show all firewall events (Note that this is kind of redudant, the first expression can be left out because it is implied in the second):

```
logtype:"application" AND application:"iptables-block"
```

Gather all serverside errors of nginx servers:

```
application:"nginx-access" AND nginx-access.response:[500 TO 599]
```

## Sending JSON with rsyslog

On every server that sends its logs to our logserver, rsyslog is installed and configured to send all logs in the JSON format described above. Of course, local logging is also done.

Sending data over TCP can be done via the [omfwd](http://www.rsyslog.com/doc/v8-stable/configuration/modules/omfwd.html) output module that is included in rsyslog by default. The configuration looks like this:

```
action(
  type="omfwd"
  Template="syslog-json"
  Target="logserver.example.com"
  Port="515"
  Protocol="tcp"
)
```

Here we use TCP port 515, because 514 is commonly used for plain syslog. The `template` directive defines which template we use to format the logs. The template for syslog messages looks like this and must be defined **before** the accompanying `action`:

```
template(name="syslog-json" type="list") {
  constant(value="{")
  constant(value="\"logtype\":\"")       constant(value="syslog"             format="json")
  constant(value="\",\"content\":{")
    constant(value="\"@timestamp\":\"")  property(name="timegenerated"       format="json" dateFormat="rfc3339")
    constant(value="\",\"host\":\"")     property(name="hostname"            format="json")
    constant(value="\",\"severity\":\"") property(name="syslogseverity-text" format="json")
    constant(value="\",\"facility\":\"") property(name="syslogfacility-text" format="json")
    constant(value="\",\"tag\":\"")      property(name="syslogtag"           format="json")
    constant(value="\",\"message\":\"")  property(name="msg"                 format="json")
    constant(value="\",\"program\":\"")  property(name="programname"         format="json")
  constant(value="\"}")
  constant(value=",\"hostinfo\":{")
    constant(value="\"name\":\"")        property(name="$myhostname" format="json")
  constant(value="\"}")
  constant(value="}")
}
```

Note that the `host.ip` attribute is missing. It will be added later at the server, because syslog does not provide a way to get the IP of the server it is running on (which might be quite difficult to do on servers with multiple interfaces).

The `format="json"` option for the property replacers makes sure that the string is properly quoted if it contains curly braces for example.

Forwarding logfiles is a bit more complex: For each file, a template and input module definition is needed, together with ruleset to bind both to a output module. The input is defined as a [imfile](http://www.rsyslog.com/doc/v8-stable/configuration/modules/imfile.html) module. For an nginx access logfile, it would look like this:

```
input(type="imfile"
    File="/var/log/nginx/access.log"
    Tag="nginx-access"
    StateFile="-var-log-nginx-access.log.state"
    ruleset="forward-nginx-access"
)
```

The `Tag` can be an arbitrary string and would correspond to the `syslogtag` attribute. Because we are not using syslog for file forwarding, it does not matter at all, but is required and is set to something descriptive.

`StateFile` defines the path to a file that rsyslog uses to keep track of its current position in the file. This is needed to preserve state between reboots or rsyslog daemon restarts. Otherwise, every time rsyslog starts it would forward the **entire** file to our logserver. The value defines the filename, which is kept under `/var/lib/rsyslog/`. Here, we simply use the full path to the logfile, with slashes replaced by hyphens. Anything else is fine, as long as it is unique among all input definitions.

Lastly, the `ruleset` determines which ruleset to bind this input to. This will be explained further down.

The template that is used to pack the information into JSON looks like this:

```
template(name="nginx-access-json" type="list") {
  constant(value="{")
  constant(value="\"logtype\":\"")        constant(value="application"  format="json")
  constant(value="\",\"application\":\"") constant(value="nginx-access" format="json")
  constant(value="\",\"content\":{")
    constant(value="\"message\":\"")      property(name="msg"           format="json")
  constant(value="\"}")
  constant(value=",\"hostinfo\":{")
    constant(value="\"name\":\"")         property(name="$myhostname"   format="json")
  constant(value="\"}")
  constant(value="}")
}
```

The `action` that sends the logs to the logging server looks the same for both syslog and file forwarding. But because each file action only applies to a single file, a `ruleset` needs to be defined to bind the `action` and the `template` together:

```
ruleset(name="forward-nginx-access") {
  action(
  type="omfwd"
  Template="nginx-access-json"
  Target="logserver.example.com"
  Port="515"
  Protocol="tcp"
  )
}
```

## Receiving and parsing logs with logstash

Now that logs are sent in a nice format, the logging server has to be configured to receive and store these logs. This is done using [logstash](https://www.elastic.co/products/logstash), which is part of the ELK stack.

The logstash configuration file is separated into three parts: input, filter, and output. The input part is configured to simply listen on TCP port 515 for messages, and logstash can automatically parse the JSON it receives:

```
/etc/logstash/conf.d/10_listen_tcp_json.conf
```

```ruby
input {
  tcp {
    type => "log_json"
    port => 515
    codec => json
  }
}
```

`type` is an arbitrary string that will later be used to distinguish JSON logs from other inputs (logstash could also listen for syslog on port 514, for example)

```
/etc/logstash/conf.d/50_filter.conf
```
```ruby
filter {
  if [type] == "log_json" {
    # complete the host attribute to contain both hostname and IP
    mutate {
      add_field => {
        "host[name]" => "[hostinfo][name]"
        "host[ip]" => "%{host}"
      }
      remove_field => "hostinfo"
    }

    # remove timestamp in syslog
    if [logtype] == "syslog" {
      mutate {
        remove_field => "content[@timestamp]"
      }
    }

    # application-specific parsing
    if [logtype] == "application" {
      if [application] == "nginx-access" {
        grok {
          match => { "content[message]" => "%{NGINXACCESS}" }
          patterns_dir => "./patterns"
          remove_field => "content[message]"
        }
        mutate {
          rename => {
            "clientip" => "[content][clientip]"
            "ident" => "[content][ident]"
            "auth" => "[content][auth]"
            "timestamp" => "[content][timestamp]"
            "request" => "[content][request]"
            "httpversion" => "[content][httpversion]"
            "response" => "[content][response]"
            "bytes" => "[content][bytes]"
            "referrer" => "[content][referrer]"
            "agent" => "[content][agent]"
            "verb" => "[content][verb]"
          }
          rename => {
            "content" => "nginx-access"
          }
        }
      }
    }
  }
}
```

This big rename for nginx access logs is necessary because logstash dumps all parsed variables into the top level of the dictionary, which then have to moved into the `content` field.

Now that the logs are formatted, they can be shipped to a local [elasticsearch](https://www.elastic.co/products/elasticsearch) instance:

```
/etc/logstash/conf.d/80_output_elasticsearch.conf
```
```ruby
output {
  elasticsearch {
    host => localhost
    protocol => transport
    index => "logstash-%{+YYYY.MM.dd}"
  }
}
```

By default, logstash puts all logs into the same elasticsearch index, namely `logstash`. By using a separate index for each day, old logs can be more easily deleted by simply removing old indices.

Grok is used for parsing the logfiles. There are several patterns shipped with logstash by default, which can be found [here](https://github.com/elastic/logstash/tree/v1.4.1/patterns). Because there is no pattern for nginx, the following custom one is used:

```
/opt/logstash/patterns/nginx
```
```
NGUSERNAME [a-zA-Z\.\@\-\+_%]+
NGUSER %{NGUSERNAME}
NGINXACCESS %{IPORHOST:clientip} %{NGUSER:ident} %{NGUSER:auth} \[%{HTTPDATE:timestamp}\] "%{WORD:verb} %{URIPATHPARAM:request} HTTP/%{NUMBER:httpversion}" %{NUMBER:response} (?:%{NUMBER:bytes}|-) (?:"(?:%{URI:referrer}|-)"|%{QS:referrer}) %{QS:agent
```

Kibana should pick up the data automatically, so you get the result seen at the beginning.
