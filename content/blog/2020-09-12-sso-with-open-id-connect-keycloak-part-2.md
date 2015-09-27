---
title: "Single Sign-On with Keycloak on Kubernetes — Part 2"
date: "2021-04-18T17:15:28+02:00"
summary: >
  How to add Single Sign-On to applications without OIDC support
  using OpenResty and some Lua scripting.
tags:
- keycloak
- openid
- oauth
- nginx
- go
- lua
- docker
- kubernetes
toc: true
---

# Introduction

In the [last blog post]({{< relref
"2020-08-30-sso-with-open-id-connect-keycloak.md" >}}), I described how to
configure Keycloak on Kubernetes to enable Single Sign-On for multiple
services. All these services had built in support for authentication and
authorization using OpenID Connect. But what if a service doesn't?

In this part, I'll describe how to use an authentication reverse proxy in front
of applications to secure them properly. A few advantages of OIDC will
of course get lost: For example, fine-grained access control on the application
level is not possible.

# The reverse proxy

I was looking around for a good authenticating reverse proxy and came across
[Pomerium](https://www.pomerium.io/). But to me, this project seemed a bit too
complex for my use case. I guess it's more apt for businesses with lots of
users.

Then I stumbled upon [lua-resty-openidc](https://github.com/zmartzone/lua-resty-openidc).
It's a Lua based plugin to [OpenResty](https://openresty.org), which is a web server
built on Nginx with a lot nice features available.

The functionality is quite straighforward: You place lua-resty-openidc in front
of your application. When a request comes in, the reverse proxy checks if the user
is already authenticated via OpenID connect. If yes, it forwards the request
to the backend application. If no, it redirects the user to the identity provider
(Keycloak in my case) for authentication. Keycloak then redirects back after
successful authentication. The backend application never sees anything of the
authentication flow.

# Building a Container

To deploy the reverse proxy in Kubernetes, I first had to package lua-resty-openidc
as a Docker container. This is actually quite straightforward:

```dockerfile
FROM openresty/openresty:1.19.3.1-centos

# https://luarocks.org/modules/bungle/lua-resty-session
# https://github.com/bungle/lua-resty-session
RUN ["/usr/local/openresty/luajit/bin/luarocks", "--global", "install", "--no-manifest", "lua-resty-session", "3.7"]

# https://luarocks.org/modules/pintsized/lua-resty-http
# https://github.com/ledgetech/lua-resty-http
RUN ["/usr/local/openresty/luajit/bin/luarocks", "--global", "install", "--no-manifest", "lua-resty-http", "0.15"]

# https://luarocks.org/modules/cdbattags/lua-resty-jwt
# https://github.com/cdbattags/lua-resty-jwt
RUN ["/usr/local/openresty/luajit/bin/luarocks", "--global", "install", "--no-manifest", "lua-resty-jwt", "0.2.2"]

# https://luarocks.org/modules/hanszandbelt/lua-resty-openidc
# https://github.com/zmartzone/lua-resty-openidc
RUN ["/usr/local/openresty/luajit/bin/luarocks", "--global", "install", "--no-manifest", "lua-resty-openidc", "1.7.3"]

RUN : \
    && curl -s -L -o /usr/local/bin/dumb-init https://github.com/Yelp/dumb-init/releases/download/v1.2.2/dumb-init_1.2.2_amd64 \
    && chmod +x /usr/local/bin/dumb-init

COPY ./start-nginx.sh /start-nginx
COPY ./nginx.conf /usr/local/openresty/nginx/conf/nginx.conf

CMD ["/usr/local/bin/dumb-init", "--", "/start-nginx"]

EXPOSE 80
```

The module versions are only a snapshot. Make sure to use the latest ones and
to update them regularly (or automatically)!

The nginx configuration is very default-y:

```nginx {linenos=table,hl_lines=["31-32",51]}
# [...]

events {
    worker_connections  1024;
}

http {
    include       mime.types;
    default_type  application/octet-stream;

    access_log logs/access.log combined;
    error_log  logs/error.log  info;

    # See Move default writable paths to a dedicated directory (#119)
    # https://github.com/openresty/docker-openresty/issues/119
    client_body_temp_path /var/run/openresty/nginx-client-body;
    proxy_temp_path       /var/run/openresty/nginx-proxy;
    fastcgi_temp_path     /var/run/openresty/nginx-fastcgi;
    uwsgi_temp_path       /var/run/openresty/nginx-uwsgi;
    scgi_temp_path        /var/run/openresty/nginx-scgi;

    sendfile        on;
    #tcp_nopush     on;

    #keepalive_timeout  0;
    keepalive_timeout  65;

    #gzip  on;

    # Required because of huge session cookies
    large_client_header_buffers 8 64k;
    client_header_buffer_size 64k;

    lua_shared_dict discovery 10m;

    lua_ssl_trusted_certificate /etc/pki/tls/certs/ca-bundle.crt;
    lua_ssl_verify_depth 2;

    # Include dynamically generated resolver config
    include /etc/nginx/resolver.conf;

    server {
        # Include dynamically generated listener config
        include /etc/nginx/listen.conf;
        server_name _;

        location /health {
            return 204;
        }

        include /etc/nginx/conf.d/oidc.conf;
    }
}
```

One interesting point is the `large_client_header_buffers` and `client_header_buffer_size`
setting. More on that later.

As you can see, the configuration imports `/etc/nginx/conf.d/oidc.conf`, which is
not part of the container. This file needs to be mounted into the container at runtime
to configure the access rights.

The start script is straightforward as well:

```bash
#!/usr/bin/env bash

# We need to extract the DNS server from /etc/resolv.conf and put it into the
# `resolver` directive in nginx

nameservers="$(grep ^nameserver /etc/resolv.conf | cut -d ' ' -f 2 | paste -s -d ' ')"

echo "resolver ${nameservers};" > /etc/nginx/resolver.conf

echo "listen ${LISTEN_PORT:-80};" > /etc/nginx/listen.conf

exec /usr/bin/openresty -g "daemon off;"
```

Building the container and making it available to Kubernetes is left as an exercise
to the reader ;)

# Putting it into Kubernetes

Now we can use the container in Kubernetes. The idea is simple: Add it to a pod,
expose only the port of the reverse proxy, and make the service use that port.

Here, I'm using [Firefly III](https://www.firefly-iii.org/) as an example, an
absolutely **awesome** personal finance manager I use to manage all my income
and expenses. It does not support OpenID connect by default. But it supports
"remote user" authentication[^firefly_remote_user]

[^firefly_remote_user]: https://docs.firefly-iii.org/firefly-iii/advanced-installation/authentication/#enable-the-remote-user-option

```yaml

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: firefly-iii
  labels:
    app: firefly-iii
spec:
  replicas: 1
  revisionHistoryLimit: 0
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: firefly-iii
  template:
    metadata:
      labels:
        app: firefly-iii
    spec:
      containers:
        - name: firefly-iii-db
          image: "docker.io/postgres:10.3"
          imagePullPolicy: IfNotPresent
          volumeMounts:
            - mountPath: '/var/lib/postgresql/data'
              name: database
          env: # snip
        - name: firefly-iii
          image: "docker.io/jc5x/firefly-iii:version-5.4.6"
          imagePullPolicy: IfNotPresent
          volumeMounts:
            - mountPath: '/var/www/firefly-iii/storage'
              name: storage
          env: # [...]
            - name: AUTHENTICATION_GUARD
              value: remote_user_guard
            - name: AUTHENTICATION_GUARD_HEADER
              # So in PHP, header gets prefixed with HTTP_ and dashes
              # are replaced by underscores. In nginx, we set
              # X-AUTH-USERNAME and X-AUTH-EMAIL
              value: HTTP_X_AUTH_USERNAME
            - name: AUTHENTICATION_GUARD_EMAIL
              value: HTTP_X_AUTH_EMAIL
            - name: CUSTOM_LOGOUT_URI
              value: /logout
        - name: oidc-proxy
          image: registry.hkoerber.de/openresty-oidc:045fc92c5826c766bd087ce51ce3959bc46b93df
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 80
              protocol: TCP
              name: http-oidc-proxy
          volumeMounts:
            - name: nginx-oidc-config
              mountPath: /etc/nginx/conf.d/oidc.conf
              subPath: conf
          livenessProbe:
            httpGet:
              port: http-oidc-proxy
              scheme: HTTP
              path: /health
          readinessProbe:
            httpGet:
              port: http-oidc-proxy
              scheme: HTTP
              path: /health
      volumes:
        - name: database
          persistentVolumeClaim:
            claimName: firefly-iii-db
        - name: storage
          persistentVolumeClaim:
            claimName: firefly-iii-storage
        - name: nginx-oidc-config
          configMap:
            name: firefly-iii-nginx-oidc-config-v3

```

First, we need a configmap the contains the nginx configuration for `/etc/nginx/conf.d/oidc.conf` mentioned above:

```yaml
kind: ConfigMap
apiVersion: v1
metadata:
  labels:
    app: firefly-iii
  name: firefly-iii-nginx-oidc-config-v3
data:
  conf: |-
    set $session_storage cookie;
    set $session_cookie_persistent on;
    set $session_cookie_secure on;
    set $session_cookie_httponly on;
    set $session_cookie_samesite Strict;

    server_tokens off;

    location = /logout_done {
      return 200 'Logout done. <a href="/">Login again</a>';
      add_header Content-Type text/html;
    }

    location / {
        access_by_lua_block {
            local opts = {
              redirect_uri = "https://finance.hkoerber.de/oauth2/callback",
              discovery = "https://{keycloak}/auth/realms/{realm}/.well-known/openid-configuration",

              client_id = "firefly-iii",
              client_secret = "{secret}",

              token_endpoint_auth_method = "client_secret_post",

              scope = "openid email profile firefly-iii",

              session_contents = {id_token=true, access_token=true},

              ssl_verify = "yes",
              accept_unsupported_alg = false,
              accept_none_alg = false,

              renew_access_token_on_expiry = true,

              logout_path = "/logout",
              post_logout_redirect_uri = "https://finance.hkoerber.de/logout_done",

              revoke_tokens_on_logout = true,
            }

            local oidc = require("resty.openidc")

            -- call authenticate for OpenID Connect user authentication
            local res, err = oidc.authenticate(opts)

            if err then
              ngx.log(ngx.CRIT, tostring(err))
              ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
            end

            -- get acess token
            local parsed_token, token_err = oidc.jwt_verify(res.access_token, opts)
            if token_err then
              ngx.log(ngx.CRIT, tostring(token_err))
              ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
            end

            -- get roles from access token
            local roles = (parsed_token["realm_access"] or {})["roles"] or {}

            local function has_role(role_name)
                for _, value in ipairs(roles) do
                    if value == role_name then
                        return true
                    end
                end
                return false
            end

            local allow = false

            -- all the setup is done. now we can check roles

            local email = parsed_token["email"]

            if has_role("firefly-iii:user") and email ~= nil then
                allow = true
            end

            if allow == true then
                ngx.req.set_header("X-AUTH-USERNAME", email)
                ngx.req.set_header("X-AUTH-EMAIL", email)
                return
            end
            ngx.exit(ngx.HTTP_FORBIDDEN)
        }

        proxy_pass http://127.0.0.1:8080;
    }
```

You can see, all the authentication magic is done in the lua block. Actually,
you're completely free to put any logic you want there. Here, I require the
user to have the `firefly-iii:user` role in keycloak. In case of authentication
success, the `X-AUTH-*` headers are set correspondingly. Firefly is configured
to trust those headers.

## The Cookie Problem

Now with 80% of the work done, I could expect to spend 80% of the time on the
remaining 20%. I was not disappointed, because a very hard to debug problem
showed up: Sometimes, the authentication would fail first with a 500 HTTP code,
and then with a 502 on reload.

I checked the logs of nginx, and it complained that it could not decode the
authentication cookie properly. It then started the authentication workflow
again, leading to an infinite loop. This turned out to be quite hard to debug,
mainly because there were so many components:

* Kubernetes ingress
* Nginx
* Keycloak
* The application itself (Firefly-III)

The first step was to reduce the number of components, or eliminate them from
the list of potential sources of errors. The application itself could be the
problem, because I saw the exact same error with other applications as well.

The next step was to strip down the setup to a minimal "proof-of-error". During
that, I noticed that the error vanished as soon as I omitted `access_token
= true` in the nginx lua configuration. I dug into the documentation of `lua-resty-openidc` and
stumpled upon [this FAQ
entry](https://github.com/zmartzone/lua-resty-openidc/wiki#why-does-my-browser-get-in-to-a-redirect-loop):

> **Why does my browser get in to a redirect loop?**
>
> It may be that you are using the (default) cookie-only session storage of lua-resty-session library that lua-resty-openidc depends on and the size of the cookie becomes too large, typically >4096 bytes. See: https://github.com/zmartzone/lua-resty-openidc/issues/32.
>
> Solution: either make the size of the session cookie smaller by having the Provider include less information in the session/claims, or revert to server side session storage such as memcache, see: https://github.com/bungle/lua-resty-session#pluggable-storage-adapters.

That's it: The session cookie gets too large! But at which point are they
dropped? I first suspected nginx to be the problem. So I set the following
configuration in the openresty nginx config, which you already saw above:

```nginx
large_client_header_buffers 8 64k;
client_header_buffer_size   64k;
```

This did not help though. As I saw later, it was one piece of the solution
puzzle. So this setting is required, but it's not enough (yet).

So, to the next suspect: Kubernetes, or more specifically, the nginx ingress. To
pinpoint the exact point, I set up SSH tunnels to different components from my
local machine and checked authentication:

* SSH tunnel to the ingress endpoint: Authentication fails (well, of course)
* SSH tunnel directly to the pod: Authentication works!
* SSH tunnel directly to the service: Authentication works, too!

So the problem was also with the header settings of the Kubernetes ingress. I
first checked the configuration. Effectively, the kubernetes nginx ingress is
just a regular nginx with a dynamically generated configuration. So I used
`kubectl` to take a look at that config:

```bash
kubectl -n ingress-nginx exec \
    $(kubectl get -n ingress-nginx pod \
        --field-selector=status.phase=Running \
        --selector=app.kubernetes.io/name=ingress-nginx,app.kubernetes.io/component=controller \\
        -o jsonpath='{.items[*].metadata.name}') \
    -- cat /etc/nginx/nginx.conf
```

I saw a few concerning defaults:

```nginx
proxy_buffer_size 4k;
proxy_buffers     4 4k;
```

Note that the settings above (`large_client_header_buffers` and
`client_header_buffer_size`) do not apply here, because nginx only acts as
a proxy. Anyway, the values of the settings above are too small for the huge
cookies that we need. So let's increase them!

Fortunately, the nginx ingress exposes these values as
annotations[^ingress_nginx_proxy_buffer_size], which can be set on
a per-ingress basis. So I updated the ingress manifest for the firefly
application:

[^ingress_nginx_proxy_buffer_size]: https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/annotations/#proxy-buffer-size

```yaml {linenos=table,hl_lines=["12-14"]}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: firefly-iii
  labels:
    app: firefly-iii
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    kubernetes.io/ingress.class: "nginx"
    cert-manager.io/cluster-issuer: "letsencrypt-production"

    # required for big session cookies in oidc authentication
    nginx.ingress.kubernetes.io/proxy-buffers-number: "8"
    nginx.ingress.kubernetes.io/proxy-buffer-size: "64k"

```

A `kubectl apply` later, authentication worked flawlessly!

# Wrap up

I used the above solution to secure access to multiple other applications, as
well. For example a Prometheus & Alertmanager setup that I use for some
internal monitoring. Prometheus does not have any authentication story anyway,
so this setup allowed me to easily secure access. But as already mentioned,
there are a few drawbacks:

* It's either-or. A user either gets access, or they don't.
* If you use reverse proxy authentication (using headers), you again need
  support from the application. At this point, I guess it's easier to add
  support for OIDC than for such an antiquated authentication scheme.

Due to that, I much prefer to use applications with proper OIDC integration.
But it's still good as a stopgap measure!

