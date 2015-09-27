---
date: 2018-07-02
summary: |
  The rabbithole that is /proc/self/mountstats
tags:
- linux
- kernel
- prometheus
- golang
- go
title: Prometheus NFS client monitoring for UDP
toc: false
---

Everything started with a simple idea: Get per-client NFS statistics into [Prometheus](https://prometheus.io/).

I found out that the [Node Exporter](https://github.com/prometheus/node_exporter) is already able to export NFS client metrics via the `mountstats` collector. It gathers metrics from `/proc/self/mountstats` and exports them nicely for prometheus to scrape. Nice! Let's try this out:

```bash
./node_exporter --collector.mountstats
failed to parse mountstats: invalid NFS transport stats 1.1 statement: [740 1 881477 875055 5946 2888414103 286261 16 258752 2080886]
```

Hmm, that does not look good. After a lot of digging throught the code, I found out that the collector seems not to support NFS mounts via UDP! This is due to a different format of the `mountstats` file depending on the protocol. [Here](https://utcc.utoronto.ca/%7Ecks/space/blog/linux/NFSMountstatsXprt) is an awesome writeup about the `mountstats` file format, which is seemingly now documented anywhere else. A big thanks to Chris Siebenmann!

The problem lies in the `xprt` line in `/proc/self/mountstats`, which contains transport statistics and looks like this for TCP:

```
xprt: tcp 695 1 1 0 16 96099368 96091328 6383 341933213458 1504192
```

All fields are explained in the link above. The crux is the following part[^quote1]:

> For the udp RPC transport there is no connection count, connect idle time, or idle time (fields #3, #4, and #5); all other fields are the same.

[^quote1]: [Link](https://utcc.utoronto.ca/%7Ecks/space/blog/linux/NFSMountstatsXprt) --- retrieved 2018-12-10

This means that for UDP, the line contains three fewer fields than for TCP. The mountstats exporter always expects the same number of fields and therefore breaks for UDP.

Another tricky thing is the `statvers` variable in `/proc/self/mountpoints` that specifies which version the statistics refer to. `statvers=1.1` added three more fields to the end, 11, 12 and 13 in the link above. I was not sure how this was handled for UDP, but after digging through kernel code and git logs, I found [this commit](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=15a4520621824a3c2eb2de2d1f3984bc1663d3c8), which shows that the three fields were added for both UDP and TCP.

I coded up the changes (learning some golang in the process) and opened a pull request with the procfs project in Prometheus at https://github.com/prometheus/procfs/pull/100, so the component now exports the statistics correctly for TCP and UDP. The fields that are missing in UDP are simply set to zero to ensure the same number of fields for both protocols. I also added a field specifiying the protocol, either "tcp" or "udp".

<!--
TODO
After getting that merged, I opened another pull request with the node exporter to actually export these statistics. Also, the NFS metrics now have a new label indicating the protocol, using the new field mentioned above!


Because these are breaking changes, they will be released with the next version of node exporter. As soon as they do, NFS client metrics will also be available for UDP mounts!
-->
