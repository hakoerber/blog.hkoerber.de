---
title: "Single Sign-On with Keycloak on Kubernetes"
date: "2020-08-30T09:29:26+02:00"
summary: >
  How I set up Single Sign-On for a few services (GitLab, Nextcloud, Miniflux)
  on Kubernetes with Keycloak
tags:
- keycloak
- openid
- oauth
- go
- docker
- kubernetes
toc: true
---

# Introduction

So I have a few services running in my private "cloud". If I told you that it's just a single VPS at [Hetzner](https://www.hetzner.de/cloud) I would not longer be able to call it "cloud", so please forget what I just said. ;)

Anyway, I currently have a few different "user-facing" services running:

* [Nextcloud](https://nextcloud.com/)
* [Gitea](https://gitea.io/), a git hosting service similar to GitHub
* [Miniflux](https://miniflux.app/), an RSS reader
* [Firefly III](https://www.firefly-iii.org/), a finance manager
* This blog

What annoyed me is the requirement to have a separate login for each service. So save a few minutes I decided to spend a few days to research and set up Single Sign-On for all these services.

Single Sign-On (or SSO for short) means that multiple services are protected behind the same login. Note that this does **not** mean to just have the same password for every service. Instead, logging in to one service means you are effectively logged in to all other services as well, without the need to authenticate again. You most likely know this from Google: When you log in to your GMail account, you are automatically also logged in to Calendar, Youtube, Google Docs etc.

SSO requires a central authentication provider that your services can authenticate against. Often (also in case of Google), this is handled by the [OpenID Connect](https://openid.net/connect/) protocol, which sits on top of OAuth 2.0. I will not go into more detail about this, but instead link to to a an awesome writeup by Micah Silverman from [Okta](https://www.okta.com/) who wrote a detailed explanation of OpenID connect: [Link](https://developer.okta.com/blog/2017/07/25/oidc-primer-part-1). Make sure to read all parts!

At this point, the steps were clear:

* Find an identity provider
* Set it up
* Integrate the services
* Rejoice

# Keycloak

While looking for an identity provider, I was looking for the following:

* Free & Open Source
* Support for OpenID Connect & OAuth 2.0
* Support for two-factor authentication

In the end, I saw that the landscape here is not too crowded and found two solution that fit the bill:

* [Keycloak](https://www.keycloak.org/), which is the upstream base to RedHat's ["Single Sign-On"](https://access.redhat.com/products/red-hat-single-sign-on)
* [Gluu](https://www.gluu.org/)

In the end, I decided on Keycloak. The main reason was that Gluu used MongoDB as its backend database, while Keycloak supports any RDBMS. The reasoning is thin, but I just prefer PostgreSQL to MongoDB.

Keycloak also supports user federation and can be used with any LDAP server. They recommend to use LDAP instead of the built-in RDBMS for scalability, but this is not a problem I am currently facing, so I'll stick to a simple setup. In the future this might be a good starting point to dive into [FreeIPA](https://www.freeipa.org/) ...

## Kubernetes deployment

Keycloak provides ready-made Docker images for the keycloak server, and I set
it
up with PostgreSQL as its backing database. On kubernetes, the setup is really
straight-forward:

```yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: keycloak
  labels:
    app: keycloak
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: keycloak
  template:
    metadata:
      labels:
        app: keycloak
    spec:
      containers:
      - name: keycloak
        # note that v11.0.1 currently has a bug that breaks updating of
        # user data, see:
        # https://issues.redhat.com/projects/KEYCLOAK/issues/KEYCLOAK-15373
        image: quay.io/keycloak/keycloak:11.0.0
        imagePullPolicy: IfNotPresent
        ports:
          - containerPort: 8080
            protocol: TCP
            name: http
        env:
        - name: KEYCLOAK_USER
          value: admin
        - name: KEYCLOAK_PASSWORD
          value: mysecurepassword
        - name: DB_VENDOR
          value: postgres
        - name: DB_ADDR
          value: localhost
        - name: DB_PORT
          value: "5432"
        - name: DB_DATABASE
          value: keycloak
        - name: DB_USER
          value: keycloak
        - name: DB_PASSWORD
          value: myothersecurepassword
        - name: KEYCLOAK_FRONTEND_URL
          value: https://keycloak.hkoerber.de/auth/
        - name: PROXY_ADDRESS_FORWARDING
          value: "true"

      - name: keycloak-db
        image: 'postgres:12.2'
        imagePullPolicy: IfNotPresent
        ports:
          - containerPort: 5432
        volumeMounts:
          - mountPath: '/var/lib/postgresql/data'
            name: database
        env:
          - name: POSTGRES_USER
            value: keycloak
          - name: POSTGRES_DB
            value: keycloak
          - name: POSTGRES_PASSWORD
            value: myothersecurepassword
      volumes:
        - name: database
          persistentVolumeClaim:
            claimName: keycloak-db
```

Handling of `VolumeClaims` and setup of services/ingress is left as an exercise to the Kubernetes admin.

## Setup

One `kubectl apply` later (done automatically via [Drone](https://drone.io/) of
course!), I logged into keycloak as the admin and was greeted with the admin
interface:

![Keyclaok admin interface](/assets/images/keycloak/intro.png)

Keycloak has an **excellent**
[documentation](https://www.keycloak.org/documentation.html) that explains all
concepts behind Keycloak and guides you through all menus and settings.
I highly
recommend to read through it (yes, it's a lot).

I will not go into too much detail about the keycloak setup here. Because it's
mostly configured via Web UI, this would just lead to a heap of screenshots.
While I really like graphical configuration for its discoverability, I much
prefer textual config, which can be tracked in git, shared, reviewed, automated
and so on. When my setup is a bit more stable, I plan to migrate the Keycloak
configuration to [Terraform](https://www.terraform.io/) with the [Terraform
provider for Keycloak](https://github.com/mrparkers/terraform-provider-keycloak)

As a brief summary, I did the following in Keycloak:

* Created a new realm for my "cloud"
* Created all users (me)
* Added groups and roles
    * I used roles in the format of `<service>:<scope>` for all services. For example, there would be a `nextcloud:admin` role
    * I used groups to assign users to roles. So the `/nextcloud/admin` group would get the `nextcloud:admin` role. Quite over-engineered for a single user, but you never know :D
* Added client scopes for the relevant roles and clients
* Added a "confidential" client for every service

That's it for the Keycloak setup! Now it's time to convince some services to authenticate against it ...

# Client configuration

The first clients I migrated were the ones that already have OpenID Connect support built-in, which were Gitea and Miniflux. Because I had to take a few hurdles along the way, I'll describe their setup briefly.

## Gitea

Gitea unfortunately does not offer any means to set the OIDC provider using the configuration file or environment variables. Instead, you have to go the the "Site Administration" menu and create a new provider under "Authentication Sources":

![Gitea setup for OpenID client](/assets/images/keycloak/gitea-oauth-setup.png)

You can see here that I chose `keycloak` for the name of the authentication provider. Gitea will always use `/user/oauth2/<name>/callback` as the callback URL path, so in Keycloak I specified `https://code.hkoerber.de/user/oauth2/keycloak/callback` as the only valid redirect URL.

This is already enough the enable OpenID login in Gitea:

![Gitea Login with OpenID](/assets/images/keycloak/gitea-login.png)

I wanted to manage Gitea users *only* via OpenID. This needed a few settings in Gitea's `app.ini`:

```ini

[service]
; Disable registration
DISABLE_REGISTRATION = false
; ... except via OpenID
ALLOW_ONLY_EXTERNAL_REGISTRATION = true

[openid]
; Do not allow signin to local users via OpenID
ENABLE_OPENID_SIGNIN = false
; Allow creation of new users via OpenID
ENABLE_OPENID_SIGNUP = true
```

That's it for Gitea. The next service is Miniflux, the RSS reader.

## Miniflux

In contrast to Gitea, Miniflux allows setting the OpenID authentication provider via environment variables. This makes it easy to set up in Kubernetes. I set the following environment variables for the Miniflux container in the Kubernetes deployment:

```yaml
env:
- name: OAUTH2_PROVIDER
  value: oidc
- name: OAUTH2_CLIENT_ID
  value: miniflux
- name: OAUTH2_CLIENT_SECRET
  value: [redacted]
- name: OAUTH2_OIDC_DISCOVERY_ENDPOINT
  value: https://keycloak.hkoerber.de/auth/realms/mycloud
- name: OAUTH2_REDIRECT_URL
  value: https://rss.hkoerber.de/oauth2/oidc/callback
- name: OAUTH2_USER_CREATION
  value: "1"
```

According to the Miniflux documentation, "Only google is supported" as an OAuth provider.[^miniflux-man-page]. Fortunately, GitHub user @pmarschik added support for generic OpenID Connect providers in [this pull request](https://github.com/miniflux/miniflux/pull/583).

I struggled a bit with the callback URL: At first, I set the path in `OAUTH2_REDIRECT_URL` to something generic like `/oauth2/keycloak/callback`. This led to a redirect loop after authentication. The browser was redirected to `/oauth2/keycloak/callback`, which started a new authentication flow, which in the end again redirected to `/oauth2/keycloak/callback` and so on. Miniflux did not properly detect that the redirect URL was the redirect URL, and started a new authentication flow every single time. So, what was the correct value to set for `OAUTH2_REDIRECT_URL` to make Miniflux detect the redirect? I had to dive into the source code ...

[^miniflux-man-page]: https://miniflux.app/miniflux.1.html

In the logs, I only got the following message:

```
[ERROR] [OAuth2] oauth2 provider not found
```

This error can only be caused at a single place in the code, at `oauth2/manager.go`[^miniflux-code-manager]

[^miniflux-code-manager]: https://github.com/miniflux/miniflux/blob/3e1e0b604fb42eba4617d77a164cca37d4cae1aa/oauth2/manager.go#L24

```go
// Provider returns the given provider.
func (m *Manager) Provider(name string) (Provider, error) {
	if provider, found := m.providers[name]; found {
		return provider, nil
	}

	return nil, errors.New("oauth2 provider not found")
}
```

This method looks for a new provider in the `m.providers` map of a `Manager` object with a certain name. The `Manager` object and its providers are initialized just a few lines further down[^miniflux-code-manager-2]:

[^miniflux-code-manager-2]: https://github.com/miniflux/miniflux/blob/3e1e0b604fb42eba4617d77a164cca37d4cae1aa/oauth2/manager.go#L32

```go
// NewManager returns a new Manager.
func NewManager(ctx context.Context, clientID, clientSecret, redirectURL, oidcDiscoveryEndpoint string) *Manager {
	m := &Manager{providers: make(map[string]Provider)}
	m.AddProvider("google", newGoogleProvider(clientID, clientSecret, redirectURL))

	if oidcDiscoveryEndpoint != "" {
		if genericOidcProvider, err := newOidcProvider(ctx, clientID, clientSecret, redirectURL, oidcDiscoveryEndpoint); err != nil {
			logger.Error("[OAuth2] failed to initialize OIDC provider: %v", err)
		} else {
			m.AddProvider("oidc", genericOidcProvider)
		}
	}

	return m
}
```

The important line is this one:

```go
m.AddProvider("oidc", genericOidcProvider)
```

We see that the key in the `providers` map is `oidc`. So why is it not found? Where does the `name` parmater to `Provider()` actually come from?

It turns out that the name is actually extracted from the URL path. The callback request is handled in a method called `oauth2Redirect()` in `ui/oauth2_callback.go`[^miniflux-code-redirect]

[^miniflux-code-redirect]: https://github.com/miniflux/miniflux/blob/master/ui/oauth2_redirect.go#L27

Here is the call to `Provider()`:

```go
authProvider, err := getOAuth2Manager(r.Context()).Provider(provider)
```

And `provider` is set a bit further above:

```go
provider := request.RouteStringParam(r, "provider")
```

If we look at the method signature, we see that `r` is a pointer to the `http.Request`:

```go
func (h *handler) oauth2Redirect(w http.ResponseWriter, r *http.Request) {
```

The `oauth2Redirect()` method is called by the Go HTTP Router according to the following handler, found in `ui/ui.go`[^miniflux-code-router]:

[^miniflux-code-router]: https://github.com/miniflux/miniflux/blob/master/ui/ui.go#L133

```go
uiRouter.HandleFunc("/oauth2/{provider}/redirect", handler.oauth2Redirect).Name("oauth2Redirect").Methods(http.MethodGet)
```

And there we are. We have an invariant in our OIDC configuration: The second part of the path of `OAUTH2_REDIRECT_URL` has to match the value of `OAUTH2_PROVIDER` (`oidc` in this case). This was of course violated when using `/oauth2/keycloak/callback` as the callback URL's path.

With the correct values set (see above), all is well and authentication works like a charm.

## Wrap up

That's it! Now all the applications are authenticating against the central Keycloak instance. Only one password to remember (I mean, put into the password manager of course). Stuff like two-factor authencation can be managed in Keycloak (it supports TOTP via Google Authenticatior for example).

There will be a follow-up post, because I'm not yet done: What about applications that do not support OpenID Connect themselves?

Stay tuned.
