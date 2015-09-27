---
date: 2017-08-22
excerpt: This is why I love linux!
tags:
- linux
- netcat
title: Cloning a hard disk over the network
toc: false
---

This is going to be short: My old trusty laptop began showing signs of old age. The screen started flickering, a problem I already knew. Last time, I bought a new screen from Alibaba for ~100€, but wasn't going to spend that much on a three year old laptop.

So, new laptop it is. The Lenovo V110-15IAP looked nice, so I ordered it online. It arrived today, but I wasn't going to spend hours to set up a new OS, copy all files over, check if everything is ok --- and I also didn't have an external drive to hold all files during transfer ... there must be an easier way.

Well, there is, and it's called `netcat` and some pipes. Netcat is a nice, simple tool that reads and writes data over the network, using TCP by default (more info [here](http://nc110.sourceforge.net/)).

I connected old and new laptop via ethernet, booted the old laptop into recovery mode, booted the new laptop with a Arch live USB drive I had laying around, and got to work.

First, the two computers need a network connection. On the old laptop:

```shell
[~]$ sudo ip addr add 10.1.1.1/24 dev enp1s0f0
[~]$ sudo ip l set dev enp1s0f0 up
```

and on the new laptop:

```shell
[~]$ sudo ip addr add 10.1.1.2/24 dev enp1s0
[~]$ sudo ip l set dev enp1s0
```

Notice the different interface names. Check connectivity:

```shell
[~]$ ping -c 3 10.1.1.1
PING 10.1.1.1 (10.1.1.1) 56(84) bytes of data.
64 bytes from 10.1.1.1: icmp_seq=1 ttl=64 time=2.33 ms
64 bytes from 10.1.1.1: icmp_seq=2 ttl=64 time=2.34 ms
64 bytes from 10.1.1.1: icmp_seq=3 ttl=64 time=2.33 ms

--- 10.1.1.1 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2003ms
rtt min/avg/max/mdev = 2.335/2.340/2.346/0.004 ms
```

Looks good!

On the "receiving" (new) laptop, I made `netcat` listen on the network, together with `pv` to get an idea of the transmission rate:

```shell
[~]$ nc -l -p 4000 | pv -pterab -s 117g | sudo dd of=/dev/sda
```

The switches for `pv` give us some nice metrics, see [`pv(1)`](https://linux.die.net/man/1/pv) for more info. The `117g` is the size of the disk, this is necessary to get an ETA and a progress meter.

Now, start the transfer on the old laptop:

```shell
[~]$ sudo dd if=/dev/sda | nc 10.1.1.2 4000
```

The transfer took around 20 minutes at about 100 MB/s, which means the Ethernet is actually the bottleneck).

After that, I verified the first few bytes of the disk to make sure they are actually the same:

```shell
[~]$ sudo dd if=/dev/sda bs=1M count=1 status=none | md5sum
d4bf772aa861fef76ff777aa52ec6800  -
```

This output was the same on both machines, which means we are good!

After a reboot, the new machine booted straight into my trusted fedora, and everything worked out of the box (except I had to re-enter the WiFi password, which I guess has something to do with changing MAC addresses). And not even five minutes later, I started writing this post.

I also eperimented a bit with compression (lz4 and lzop), but even though the network was the bottleneck, the transfer didn't complete any faster. Not sure why, but I got what I wanted, so I didn't bother to investigate further.

You could do the same over any network, but with the `netcat` transfer being unencrypted, you'd need some kind of encryption, for example by piping through `ssh`.

Anyway, thank you for reading!
