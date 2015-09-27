---
date: 2018-04-22
except: MTU issues with Docker
tags:
- linux
- netcat
title: 'Troubles with Drone on Kubernetes'
toc: false
---

Currently, I am trying out [drone](https://drone.io/) to automate building of docker images for my kubernetes cluster.

I have a Docker-in-Docker (DIND) setup in Kubernetes to enable building docker containers in drone. Yes, those are a lot of Docker layers! Kubernetes, then drone, the whatever Docker containers drone is building ... but it works! At least, now it does. Before, I noticed that I did not have network connectivity inside the build containers. DNS was working, but pinging did not. The `.drone.yml` file looks like this:

```yml
pipeline:
  build:
    image: docker:17.12.1
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    commands:
      - apk update
      - apk add make git
      - make
```

I did not want to use DIND containers for every build step, but drone should use a single DIND container for all builds to use. This was done like this in the kubernetes deployment:

```yml
spec:
  containers:
  - image: docker:17.12.1-dind
    name: dind
    ports:
    - containerPort: 2375
      protocol: TCP
    securityContext:
      privileged: true
  - image: drone/agent:0.8
    name: drone-agent
    args:
    - agent
    env:
    - name: DRONE_SECRET
      value: [...]
    - name: DRONE_SERVER
      value: [...]
    - name: DOCKER_HOST
      value: tcp://localhost:2375
```

Exept, that did not work, showing the network connectivity issues mentioned above.

In the end, I tracked it down to an MTU issue, also mentioned [here](https://discourse.drone.io/t/docker-mtu-problem/1207). The fix is a bit ugly, because the DIND container does not expose a straight way to set the MTU. The simplest solution (after looking into [the DIND build environment](https://github.com/docker-library/docker/blob/5b158e3ca87bdc20069754a796c00b270e40cfdb/17.12/dind/)) I found was to set the startup arguments for the DIND container explicitly in the kubernetes deployment:

```diff
  - image: docker:17.12.1-dind
    name: dind
+   command:
+   - dockerd-entrypoint.sh
+   - dockerd
+   - --host=unix:///var/run/docker.sock
+   - --host=tcp://localhost:2375
+   - --mtu=1400
+   - --storage-driver=vfs
    ports:
    - containerPort: 2375
      protocol: TCP
    securityContext:
      privileged: true
```

With these changes, network connectivity for the build containers is restored, and drone can build docker containers without issues.

Hopefully, in one of my next posts I might describe how this blog is then automatically built using drone ;)
