---
projects:
- name: git-repo-manager
  description:
    - |
      A command-line tool to manage local git repositories
  icon:
    path: /assets/logos/git.svg
    alt: Git
  tags:
  - type: language
    value: rust
  - type: tech
    value: libgit2
  - type: tech
    value: toml
  links:
    github: https://github.com/hakoerber/git-repo-manager
- name: prometheus-restic-backblaze
  description:
    - |
      A prometheus exporter that reports restic backup ages for Backblaze
  image:
    path: /assets/logos/backblaze.svg
    type: picture-padded
    alt: Backblaze
  tags:
  - type: language
    value: python
  - type: tech
    value: prometheus
  - type: tech
    value: restic
  links:
    github: https://github.com/hakoerber/prometheus-restic-backblaze
    projectpage: x
- name: virt-bootstrap
  description:
    - |
      A script that bootstraps a new libvirt VM using cobbler
  tags:
  - type: language
    value: python
  - type: tech
    value: libvirt
  - type: tech
    value: cobbler
  links:
    github: https://github.com/hakoerber/virt-bootstrap
- name: aws-glacier-backup
  description:
    - |
      A bash script that uploads gzip'ed, gpg encrypted backups to AWS glacier
  icon:
    path: /assets/logos/aws-s3.svg
    alt: AWS S3
  tags:
  - type: language
    value: bash
  - type: tech
    value: AWS S3
  - type: tech
    value: GPG
  links:
    github: https://github.com/hakoerber/aws-glacier-backup
- name: guitar-practice
  description:
    - |
      A simple python script that gives me a series of guitar chords to practice
      chord transitions, with customizable rate of change
  image:
    path: /assets/images/guitar-closeup.jpg
    alt: A Guitar
  tags:
  - type: language
    value: python
  links:
    github: https://github.com/hakoerber/guitar-practice
- name: checkconn
  description:
    - |
      Utiliy that continuously monitors the internet connection and reports downtimes
  tags:
  - type: language
    value: bash
  links:
    github: https://github.com/hakoerber/checkconn
- name: packager
  description:
    - |
      A learning project that can be used to manage packing lists for trips, considering
      duration, weather and other factors.
    - |
      I mainly wrote this to play around with Flask and Elm
  tags:
  - type: language
    value: python
  - type: language
    value: elm
  - type: language
    value: javascript
  - type: tech
    value: flask
  - type: tech
    value: SQLite
  links:
    github: https://github.com/hakoerber/packager
- name: salt-nginx-letsencrypt
  description:
    - |
      A SaltStack nginx formula that also enables automated letsencrypt certificate management
  icon:
    path: /assets/logos/letsencrypt.svg
    alt: Let's Encrypt
  tags:
  - type: language
    value: python
  - type: tech
    value: SaltStack
  - type: tech
    value: LetsEncrypt
  - type: tech
    value: nginx
  links:
    github: https://github.com/hakoerber/salt-nginx-letsencrypt
- name: ansible-roles
  description:
    - |
      A collection of ansible roles, e.g. for libvirt, networking, OpenVPN
  icon:
    path: /assets/logos/ansible.svg
    alt: Ansible
  tags:
  - type: language
    value: yaml
  - type: tech
    value: ansible
  links:
    github: https://github.com/hakoerber/ansible-roles
- name: salt-states
  description:
    - |
      A big collection of saltstack states that I used for my homelab.
    - |
      It contains configuration for a bunch of different services, e.g. elasticsearch,
      dovecot, grafana, influxdb, jenkins, kibana, nginx, owncloud, postgresql, ssh and
      a lot of others.
  tags:
  - type: language
    value: YAML
  - type: language
    value: jinja2
  - type: tech
    value: saltstack
  links:
    github: https://github.com/hakoerber/salt-states
- name: wifiqr
  description:
    - |
      A script that generates QR codes for easy WiFi access
  image:
    path: /assets/images/qrcode-example.png
    alt: An example QR code
  tags:
  - type: language
    value: bash
  links:
    github: https://github.com/hakoerber/wifiqr
- name: syncrepo
  description:
    - |
      A python script to create and maintain a local YUM/DNF package repository
      for CentOS. Can be used to keep a mirror up to date with `cron(8)`.
  tags:
  - type: language
    value: python
  - type: tech
    value: DNF
  links:
    github: https://github.com/hakoerber/syncrepo

contributions:
- name: Prometheus Node Exporter
  changes:
  - Add label to NFS metrics containing the NFS protocol (`tcp/udp`)
  icon:
    path: /assets/logos/prometheus.svg
    alt: Prometheus
  commits:
  - https://github.com/prometheus/node_exporter/commit/14a4f0028e02ba1c21d6833482bd8f7529035b07
  tags:
  - type: language
    value: go
  - type: tech
    value: prometheus
  - type: tech
    value: NFS
  links:
    github: https://github.com/prometheus/node_exporter
- name: Kubespray
  changes:
  - Fix issues with continuous regeneration of etcd TLS cerificates
  - Fix incorrect directory mode for etcd TLS certificates
  icon:
    path: /assets/logos/kubernetes.svg
    alt: Kubernetes
  commits:
  - TODO
  tags:
  - type: language
    value: go
  - type: tech
    value: kubernetes
  - type: tech
    value: ansible
  links:
    github: https://github.com/kubernetes-sigs/kubespray/
- name: SaltStack
  changes:
    - Expand the `firewalld` module for interfaces, sources, services and zones
    - Fix the reactor engine not being loaded when not explicitly configured
  icon:
    path: /assets/logos/saltstack.svg
    alt: SaltStack
  commits:
  - https://github.com/saltstack/salt/commit/83aacc3b32be384eb22c514713cf35238dcb98bf
  - https://github.com/saltstack/salt/commit/5ad305cedfeda516d900f04ded95c168e6cd1ebb
  - https://github.com/saltstack/salt/commit/b8a889497ae557e6e8cc1a0101dc40572c618a5f
  - https://github.com/saltstack/salt/commit/f27ac3c1801a6d515a34c9dedabb95488df0e9a7
  - https://github.com/saltstack/salt/commit/317b7002bbb248bb5a46c173a1a5d13dfc271b6d
  - https://github.com/saltstack/salt/commit/5c1b8fc24611afd8557bcc3b35d5e2523c069408
  - https://github.com/saltstack/salt/commit/59d8a3a5a102540384a0561f0ff828dc5eb8cd69
  - https://github.com/saltstack/salt/commit/e8347282cd129c6b3b2ba1c6d8292d101fd69d1e
  - https://github.com/saltstack/salt/commit/bd49029fe0b312f169443e6086de3b7bbcd1bde7
  - https://github.com/saltstack/salt/commit/749b4bc924b3ecdbecd48d70795bdb1a2391f3d3
  - https://github.com/saltstack/salt/commit/81961136d5e8c2ccb06af1220a7503cc66255998
  tags:
  - type: language
    value: python
  - type: tech
    value: saltstack
  - type: tech
    value: Firewalld
  links:
    github: https://github.com/saltstack/salt
- name: Vagrant
  changes:
    - Renew DHCP lease on hostname change for Debian guests
    - Fix hostname entry in `/etc/hosts` for Debian guests
  icon:
    path: /assets/logos/vagrant.svg
    alt: Vagrant
  commits:
  - https://github.com/hashicorp/vagrant/commit/3082ea502e2d7ad314d78cb0af5d71cc36bc42bc
  - https://github.com/hashicorp/vagrant/commit/3fa3e995a97d8a2d9705a5b483338009315bfeb0
  tags:
  - type: language
    value: ruby
  - type: tech
    value: vagrant
  links:
    github: https://github.com/hashicorp/vagrant
- name: Prometheus procfs
  changes:
    - Add exporting of a new field containing the NFS protocol (required for the node exporter change)
    - Fix parsing of the `xprt` lines in `mountstats` to enable metric exports for UDP mounts
  commits:
  - https://github.com/prometheus/procfs/commit/ae68e2d4c00fed4943b5f6698d504a5fe083da8a
  tags:
  - type: language
    value: go
  - type: tech
    value: prometheus
  - type: tech
    value: NFS
  links:
    github: https://github.com/prometheus/procfs
- name: The Lost Son
  changes:
    - Our contribution to the Global Game Jam 2018!
  image:
    path: /assets/images/lostson.jpg
    alt: The game "Lost Son"
  tags:
  - type: language
    value: javascript
  - type: tech
    value: phaser
  links:
    github: https://github.com/niklas-heer/the-lost-son
---
