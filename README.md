ansible-role-local-vm
=====================

This [Ansible](https://docs.ansible.com/) role uses [FAI](https://fai-project.org/fai-guide/) to install local virtual machines (VM) via `libvirt` (KVM) for testing purposes. The setup is quite opinionated to facilitate quick deployment of (possibly) short-lived VMs. For example I use it to test other Ansible roles in a freshly installed Debian 13 (`trixie`) operating system.

The role installs new Debian VMs in the following way:

- adds a single virtual network adapter and assigns a static IPv4 address 
- adds one or more virtual disks, uses the first to set up EFI and root partitions and installs Debian 13
- sets hostname
- sets FQDN using the IPv4 address from the NIC via `/etc/hosts`
- creates a user `ansible` with a specific password defined by the dev
- adds the dev's SSH public key to the `authorized_keys` of `ansible`
- adds an initial nameserver entry to `/etc/resolv.conf`
- removes `/etc/apt/sources.list`

After installation new VMs are reachable via SSH and ready to be configured by Ansible. The role provides a minimal environment only, assuming that other Ansible plays take over from there to finish the system's configuration.

VM installation does not rely on the network. Instead the role creates installation media and mounts it in the new VM to install Debian from a local mirror (see [FAI Guide](https://fai-project.org/fai-guide/#_a_id_cdboot_a_creating_a_fai_cd_or_and_usb_stick)).

Preparation
-----------

> The following instructions assume that this Ansible role and its dependencies are installed in a Debian-based operating system such as Debian 13 or Ubuntu 24.04.

First of all install `virt-install`:

```sh
sudo apt install virt-manager
sudo adduser $(whoami) libvirt
```

It may be necessary to set up the default network, which uses a bridge `virbr0` to connect to the host network and beyond via NAT:

```sh
virsh net-define /usr/share/libvirt/networks/default.xml
sudo virsh net-autostart default
sudo virsh net-start default
```

> Strictly speaking the default network defined in `/usr/share/libvirt/networks/default.xml` goes beyond what is needed in this setup, such as enabling a DHCP service for guests. DHCP can be removed from the network configuration file without interfering with this role.

Then install FAI. While the [FAI Guide](https://fai-project.org/fai-guide/#_install_the_fai_packages) and the [homepage](https://fai-project.org/download/) provide instructions on this, the necessary steps to use FAI with this role differ slightly from the recommended installation process:

```sh
# as root

echo "deb https://fai-project.org/download trixie koeln" > /etc/apt/sources.list.d/fai.list
wget https://fai-project.org/download/fai-project.gpg -O /etc/apt/trusted.gpg.d/fai-project.gpg
```

```sh
sudo apt update
sudo apt install --no-install-recommends fai-server reprepro squashfs-tools dosfstools mtools
```

Then prepare the FAI configuration space and install the Ansible role:

```sh
cd $HOME
git clone git@github.com:puetzp/ansible-role-local-vm.git
sudo mv ansible-role-local-vm /srv/fai
```

Cloning the repository in this specific location ensures that FAI is able to locate the configuration space in its default path `/srv/fai/config`, while the Ansible role is available in `/srv/fai/ansible`.

When FAI is used for offline or online installations it needs a `nfsroot` which contains a minimal Debian environment (via `debootstrap`) and some extra packages that enable FAI to install Debian on the first virtual disk (see [FAI Guide](https://fai-project.org/fai-guide/#_create_the_nfsroot)).

Review the contents of `/etc/fai/nfsroot.conf` and `/etc/fai/apt/sources.list` and optionally replace the apt mirrors mentioned there. Then create the `nfsroot`:

```sh
sudo fai-setup -v -f
```

In addition to the nfsroot FAI also uses a small local mirror to hold packages defined in [`/srv/fai/config/package_config/DEFAULT`](config/package_config/DEFAULT). Those are packages that you would like to have installed in every new Debian environment. Optionally adjust the list of packages and created the local mirror with this command:

```sh
sudo fai-mirror /srv/fai/mirror
```

The directory should now look like this:

```
/srv/fai
├── ansible
├── config
├── mirror      # created by fai-mirror
├── nfsroot     # created by fai-setup
└── README.md
```

VM Installation
---------------

After preparing the local system by following the above steps, the FAI configuration space and Ansible role located in `/srv/fai/ansible` can now be used to installs new VMs.

Since the Ansible role configures `localhost` no inventory file is required, only some host variables. The following configuration assumes that your playbooks are located in `$HOME/ansible`.

```yml
# $HOME/ansible/host_vars/localhost.yml
---
ansible_connection: local

# Common domain used to configure the fully-qualified domain names of all VMs.
domain: internal

# Encrypted password for user 'ansible'. For example this is the hash of
# the string `foobar`, generated via `openssl passwd -6`.
password: $6$E9akWI2zpi.biv1g$YHGfQ2dzfmFsAbEpX/j7t22K5qqJTevm3XfslT4GiI9GYdsE8lZeFWpgal8D66sLr.r2Y/tppnhFNxFTc4o7V.

# Your SSH public key.
ssh_key: "{{ lookup('file', '~/.ssh/id_ed25519.pub') }}"

# Initial DNS server for early bootstrapping.
dns: 192.168.3.100

# VMs to be installed. Existing VMs are skipped.
virtual_machines:
  dns:
    cpu: 2
    memory: 2048
    disks:
      - 20
    ip: 192.168.122.2
    gateway: 192.168.122.1
  ntp:
    cpu: 2
    memory: 2048
    disks:
      - 20
    ip: 192.168.122.3
    gateway: 192.168.122.1
  netbox:
    cpu: 4
    memory: 8192
    disks:
      - 20
      - 100
    ip: 192.168.122.4
    netmask: 255.255.255.0    # optional, defaults to `255.255.255.0`
    gateway: 192.168.122.1
```

Use the following example playbook to install the VMs:

```yml
# $HOME/ansible/deploy-vms.yml
---
- hosts: localhost
  gather_facts: false
  roles:
    - role: /srv/fai/ansible
```

```sh
ansible-playbook -K deploy-vms.yml
```

> Note that a sudo password needs to be passed to Ansible via the `-K` parameter, because FAI needs to execute the `fai-cd` command as root to build the ISO file on the local system.

In this example the result of the play are three local VMs accessible via SSH:

- `dns.internal`
- `ntp.internal`
- `netbox.internal`

Why Ansible?
------------

Of course this whole deployment and installation process for test VMs could just as well be a bash script. For me personally the point of using Ansible is:

- having a playbook for local test deployments adjacent to any other playbooks that configure local or remote VMs
- being able to expand or clone the role for remote deployments (e.g. VMs on Proxmox) and Ansible becomes the more convenient choice

Drawbacks
---------

New VMs are installed sequentially. Since each installation takes 60-80 seconds to finish (depending on your rig), deploying multiple VMs might take a few minutes. Still, deploying a few new VMs to try some things out should not take much longer than getting a fresh cup of coffee.

One area of reducing overhead is examining the content of the nfsroot in `/etc/fai/NFSROOT` and removing packages that are not needed for this setup to work. The following is a minimal nfsroot that works for me:

```
# package list for creating the NFSROOT

PACKAGES install-norec
# dracut replaces live-boot and initramfs-tools
dracut live-boot- initramfs-tools-
dracut-config-generic
dracut-network
dbus
curl lftp
util-linux-extra
less
ntpsec-ntpdate rdate
dosfstools
lvm2
psmisc
uuid-runtime
dialog
console-common kbd
xz-utils pigz zstd
gpg

PACKAGES install-norec AMD64
grub-pc
grub-efi-amd64-bin
efibootmgr
```


