title: Ceph single node deployment
date: 2016-09-08 22:44:43
tags:
---

## Getting the Cluster up and running

### Installing the hypervisor

```
2 x 128 GB SSH
2 x 3 TB HDD

SSD: RAID1

512MiB /boot

LVM:

VG hyper01:
10 GiB /
10 GiB /var
1 GiB swap

VG virt:
5 x 10GiB (Ceph VMs, see below)

VG journal:
2 x 5GiB (Ceph journals)
---
~80GiB

=> 120GiB - 80GiB = 40GiB expansion potential

40GiB / (10GiB + 5GiB) =~ 2 => space for 2 more OSDs in the future
```

```
Ceph VMs:

2 x OSD
3 x MON

each:
4GiB /
5GiB /var
512MiB swap
512MiB /boot
---
10GiB
```

CentOS 7

```
# AUTHENTICATION AND USERS
auth --enableshadow --passalgo=sha512
rootpw --iscrypted {{password}}

# FIREWALL
firewall --disabled

# LOCALIZATION AND TIME
keyboard --vckeymap=de-nodeadkeys
lang en_US.UTF-8
timezone --nontp --utc Europe/Berlin --nontp

# MISC
selinux --enforcing

# WHERE TO INSTALL FROM
install
cdrom

skipx
text
poweroff

# NETWORK
network --hostname=hyper01.mgmt.haktec.de
network --activate --onboot=yes --device=00:25:90:47:6e:14 --noipv4 --noipv6
network --activate --onboot=yes --device=00:25:90:47:6e:15 --noipv4 --activate
network --activate --onboot=yes --device=bond0 --noipv4 --noipv6 --bondslaves=eno1,eno2 --bondopts=mode=active-backup,miimon=100
network --activate --onboot=yes --device=bond0.30 --noipv4 --noipv6 --vlanid=30
network --activate --onboot=yes --device=br-home --bridgeslaves=bond0.30 --bootproto=dhcp

services --disabled=firewalld,NetworkManager

# PARTITIONS
ignoredisk --only-use=/dev/disk/by-id/ata-SanDisk_SDSSDP128G_150610400358,/dev/disk/by-id/ata-SanDisk_SDSSDP128G_152964400540

zerombr

bootloader --location=mbr --boot-drive=/dev/disk/by-id/ata-SanDisk_SDSSDP128G_150610400358
clearpart --all --initlabel

part raid.01 --fstype=mdmember --ondisk=/dev/disk/by-id/ata-SanDisk_SDSSDP128G_150610400358 --size=512
part raid.02 --fstype=mdmember --ondisk=/dev/disk/by-id/ata-SanDisk_SDSSDP128G_152964400540 --size=512

part raid.11 --fstype=mdmember --ondisk=/dev/disk/by-id/ata-SanDisk_SDSSDP128G_150610400358 --grow
part raid.12 --fstype=mdmember --ondisk=/dev/disk/by-id/ata-SanDisk_SDSSDP128G_152964400540 --grow

raid /boot     --level=1 --device=boot --fstype=xfs  raid.01 raid.02
raid pv.01 --level=1 --device=pv01 --fstype=lvmpv raid.11 raid.12

volgroup vg.hyper01 pv.01

logvol /    --vgname=vg.hyper01 --name=root --size=5120 --fstype=xfs
logvol /var --vgname=vg.hyper01 --name=var  --size=4096 --fstype=xfs
logvol swap --vgname=vg.hyper01 --name=swap --size=1024 --fstype=xfs

user --name hannes

%packages
@Core
bridge-utils
tmux
-firewalld
-NetworkManager
%end

%post --erroronfail
mkdir --parents --mode 700 /home/hannes/.ssh

cat > /home/hannes/.ssh/authorized_keys << EOF
ssh-rsa {{pubkey}} hannes
EOF

chmod 600 /home/hannes/.ssh/authorized_keys
chown -R hannes:hannes /home/hannes
%end
```

Network configuration

```
/etc/sysconfig/networks-scripts/ifcfg-bond0
---
DEVICE=bond0
TYPE=Bond
ONBOOT=yes
BOOTPROTO=none
USERCTL=no
BONDING_OPTS="mode=1 miimon=100"
```

```
/etc/sysconfig/networks-scripts/ifcfg-eno1
---
DEVICE=eno1
ONBOOT=yes
BOOTPROTO=none
USERCTL=no
MASTER=bond0
SLAVE=yes
```

```
/etc/sysconfig/networks-scripts/ifcfg-eno2
---
DEVICE=eno2
ONBOOT=yes
BOOTPROTO=none
USERCTL=no
MASTER=bond0
SLAVE=yes
```

```
/etc/sysconfig/networks-scripts/ifcfg-bond0.30
---
DEVICE=bond0.30
ONBOOT=yes
BOOTPROTO=none
TYPE=None
VLAN=yes
USERCTL=no
BRIDGE=br-home
```

```
/etc/sysconfig/networks-scripts/ifcfg-br-home
---
DEVICE=br-home
ONBOOT=yes
TYPE=Bridge
BOOTPROTO=dhcp
```

Check the RAID Setup:
```
# cat /proc/mdstat
Personalities : [raid1]
md126 : active raid1 sdb2[0] sda2[1]
      122489856 blocks super 1.2 [2/2] [UU]
      bitmap: 0/1 pages [0KB], 65536KB chunk

md127 : active raid1 sdb1[0] sda1[1]
      524224 blocks super 1.0 [2/2] [UU]
      bitmap: 0/1 pages [0KB], 65536KB chunk

unused devices: <none>
```

Update the system:

```
# yum update
```

Enable passwordless sudo:

```
# groupadd --system sudo
# echo '%sudo ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers
# gpasswd -a hannes sudo
```

Disable SSH Password Authentication:
```
# sed -i -e 's/^PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config
# systemctl restart sshd
```

### Setting up libvirt

```
# yum install libvirt qemu-kvm
```

Everyone in group `libvirt` is allowed to access libvirt:

```
# gpasswd -a hannes libvirt
```

Start libvirt:

```
# systemctl start libvirtd
# systemctl enable libvirtd
```

Connect to the hypervisor:

```
$ virsh --connect=qemu:///system
```

#### libvirt storage setup

```
~/pool-lvm-hyper01.xml
---
<pool type='logical'>
  <name>lvm-hyper01</name>
  <source>
    <name>vg.hyper01</name>
  </source>
  <target>
    <path>/dev/vg.hyper01</path>
  </target>
</pool>
```

Define and start the pool:

```
virsh # pool-define pool-lvm-hyper01.xml
virsh # pool-start lvm-hyper01
virsh # pool-autostart lvm-hyper01

virsh # pool-list --all --details
 Name         State    Autostart  Persistent    Capacity  Allocation   Available
---------------------------------------------------------------------------------
 lvm-hyper01  running  yes        yes         116.81 GiB   10.00 GiB  106.81 GiB
```

#### libvirt network setup

2 networks: storage and cluster

Remove the `default` network:

```
virsh # net-destroy default
virsh # net-undefine default
```

Define the relevant bridges:

```
/etc/sysconfig/networks-scripts/ifcfg-br-cluster
---
DEVICE=br-cluster
ONBOOT=yes
TYPE=Bridge
BOOTPROTO=none
```

```
/etc/sysconfig/networks-scripts/ifcfg-br-storage
---
DEVICE=br-storage
ONBOOT=yes
TYPE=Bridge
BOOTPROTO=static
IPADDR=10.3.1.1
NETMASK=255.255.255.0
```

```
# systemctl restart network
```

Network definitions:
```
~/network-cluster.xml
---
<network ipv6='yes'>
  <name>cluster</name>
  <forward mode='bridge'/>
  <bridge name='br-cluster'/>
</network>
```

```
~/network-storage.xml
---
<network ipv6='yes'>
  <name>storage</name>
  <forward mode='bridge'/>
  <bridge name='br-storage'/>
</network>
```

Start the networks:

```
virsh # net-define network-cluster.xml
virsh # net-define network-storage.xml

virsh # net-start cluster
virsh # net-start storage

virsh # net-autostart cluster
virsh # net-autostart storage

virsh # net-list --all
 Name                 State      Autostart     Persistent
----------------------------------------------------------
 cluster              active     yes           yes
 storage              active     yes           yes
```

### Creating the Ceph VMs

#### Create the first monitor VM

Create the storage volume:

```
virsh # vol-create-as --pool lvm-hyper01 --name virt-mon01 --capacity 10GiB --format raw
```

```
# lvdisplay vg.hyper01/virt-mon01
  --- Logical volume ---
  LV Path                /dev/vg.hyper01/virt-mon01
  LV Name                virt-mon01
  VG Name                vg.hyper01
  LV UUID                6LLfnI-Jrve-q5IV-dBER-w0jv-wt8Y-TBAKf5
  LV Write Access        read/write
  LV Creation host, time hyper01.mgmt.haktec.de, 2016-09-09 23:52:16 +0200
  LV Status              available
  # open                 0
  LV Size                10.00 GiB
  Current LE             2560
  Segments               1
  Allocation             inherit
  Read ahead sectors     auto
  - currently set to     256
  Block device           253:3
```

Domain definition:

```
~/domain-ceph-mon01.xml
---
<domain type='kvm'>
  <name>ceph-mon01</name>
  <memory unit='KiB'>1048576</memory>
  <currentMemory unit='KiB'>1048576</currentMemory>
  <vcpu placement='static'>1</vcpu>
  <os>
    <type arch='x86_64'>hvm</type>
    <boot dev='cdrom'/>
    <boot dev='hd'/>
  </os>
  <features>
    <acpi/>
    <apic/>
  </features>
  <clock offset='utc'>
    <timer name='rtc' tickpolicy='catchup'/>
  </clock>
  <on_poweroff>destroy</on_poweroff>
  <on_reboot>restart</on_reboot>
  <on_crash>destroy</on_crash>
  <devices>
    <disk type='volume' device='disk'>
      <driver name='qemu' type='raw' cache='none' io='native' discard='unmap'/>
      <source pool='lvm-hyper01' volume='virt-mon01'/>
      <target dev='vda' bus='virtio'/>
    </disk>
    <interface type='network'>
      <source network='cluster'/>
      <model type='virtio'/>
      <driver name='vhost'/>
    </interface>
    <interface type='network'>
      <source network='storage'/>
      <model type='virtio'/>
      <driver name='vhost'/>
    </interface>
    <input type='tablet' bus='usb'/>
    <input type='keyboard' bus='usb'/>
    <channel type='spicevmc'>
      <target type='virtio'/>
    </channel>
    <graphics type='spice' autoport='yes' listen='127.0.0.1'>
      <listen type='address' address='127.0.0.1'/>
    </graphics>
    <video>
      <model type='qxl'/>
    </video>
  </devices>
</domain>
```

Define the VM:

```
virsh # define domain-ceph-mon01.xml
```

Attach the ISO for installation:

```
virsh # attach-disk --domain ceph-mon01 --source /var/lib/libvirt/iso/CentOS-7-x86_64-Minimal-1511.iso --target vdz --targetbus virtio --config
```

Start the VM:

```
virsh # start ceph-mon01
```

Install CentOS, kickstart:

```
# AUTHENTICATION AND USERS
auth --enableshadow --passalgo=sha512
rootpw --iscrypted {{password}}

# FIREWALL
firewall --disabled

# LOCALIZATION AND TIME
keyboard --vckeymap=de-nodeadkeys
lang en_US.UTF-8
timezone --nontp --utc Europe/Berlin --nontp

# MISC
selinux --enforcing

# WHERE TO INSTALL FROM
install
cdrom

skipx
text
poweroff

services --disabled=firewalld,NetworkManager

# NETWORK
network --hostname=ceph-mon01.storage.haktec.de
network --activate --onboot=yes --device=52:54:00:ba:5a:db --bootproto=dhcp --noipv6

# PARTITIONS
ignoredisk --only-use=vda

zerombr

bootloader --location=mbr --boot-drive=vda
clearpart --drives=vda --initlabel

part /boot --ondrive=vda --size 512 --fstype=xfs --label=boot
part pv.01 --ondrive=vda --grow

volgroup ceph-mon01 pv.01

logvol /    --vgname=ceph-mon01 --name=root --size=4096 --fstype=xfs
logvol /var --vgname=ceph-mon01 --name=var  --size=1024 --fstype=xfs --grow
logvol swap --vgname=ceph-mon01 --name=swap --size=512

user --name hannes

%packages
@Core
-firewalld
-NetworkManager
%end

%post --erroronfail
mkdir --parents --mode 700 /home/hannes/.ssh

cat > /home/hannes/.ssh/authorized_keys << EOF
ssh-rsa {{pubkey}} hannes
EOF

chmod 600 /home/hannes/.ssh/authorized_keys
chown -R hannes:hannes /home/hannes
%end
```

How to make the kickstart file available from the hypervisor:

```
while :; do nc -l 8080 < ks.cfg ; done
```

```
dnsmasq -d -i br-storage -I lo --bind-interfaces --dhcp-range=10.3.1.100,10.3.1.199,255.255.255.0 -C /dev/null
```

Install the guest and wait for it to shut down.

Detach the ISO:

```
virsh # detach-disk --domain ceph-mon01 --target vdz --config
```

Start it again in order to set it up:

```
virsh # start ceph-mon01
```

Log in, and do the usual deployment stuff.

Network setup:


```
/etc/sysconfig/networks-scripts/ifcfg-eth0
---
DEVICE=eth0
ONBOOT=yes
USERCTL=no
BOOTPROTO=static
IPADDR=10.4.1.10
NETMASK=255.255.255.0
HWADDR=52:54:00:ba:5a:db
```

```
/etc/sysconfig/networks-scripts/ifcfg-eth1
---
DEVICE=eth1
ONBOOT=yes
USERCTL=no
BOOTPROTO=static
IPADDR=10.3.1.10
NETMASK=255.255.255.0
HWADDR=52:54:00:3b:2c:3a
```



From above:

```
# yum update
# groupadd --system sudo
# echo '%sudo ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers
# gpasswd -a hannes sudo
# sed -i -e 's/^PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config
# systemctl restart sshd
```


networking

ssh keylogin + pwless sudo for user cephdeploy
requiretty

firewall

SELinux

### Bootstrapping the Cluster

```
TODO
```
