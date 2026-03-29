ansible-role-local-vm
=====================

This [Ansible](https://docs.ansible.com/) role uses [FAI](https://fai-project.org/fai-guide/) to build raw disk images and create local virtual machines (VM) via `libvirt` (KVM) for testing purposes. The setup is quite opinionated to facilitate quick deployment of (possibly) short-lived VMs. For example I use it to test other Ansible roles in a freshly installed Debian 13 (`trixie`) operating system.

The role creates raw disk images in the following way:

- sets up separate partitions for EFI and LVM and installs Debian 13
- creates network configuration for a single interface and assigns a static IPv4 address
- sets hostname
- sets FQDN using the IPv4 address from the NIC via `/etc/hosts`
- creates a user `ansible` with a specific password defined by the dev
- adds the dev's SSH public key to the `authorized_keys` of `ansible`
- adds an initial nameserver entry to `/etc/resolv.conf`
- copies `/etc/fai/apt/sources.list` to the disk image at `/etc/apt/sources.list`

Then Ansible creates new VMs from those disk images. After booting VMs are reachable via SSH and ready to be configured by other Ansible plays.

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

Then install FAI. While the [FAI Guide](https://fai-project.org/fai-guide/#_install_the_fai_packages) and the [homepage](https://fai-project.org/download/) provide instructions on this, the necessary steps to use FAI with this role differ slightly from the recommended installation process, because fewer packages are needed to create disk images:

```sh
# as root

echo "deb https://fai-project.org/download trixie koeln" > /etc/apt/sources.list.d/fai.list
wget https://fai-project.org/download/fai-project.gpg -O /etc/apt/trusted.gpg.d/fai-project.gpg
```

```sh
sudo apt update
sudo apt install --no-install-recommends fai-server fai-setup-storage
```

Then prepare the FAI configuration space and install the Ansible role by cloning the repository:

```sh
cd $HOME
git clone git@github.com:puetzp/ansible-role-local-vm.git
```

The `fai-diskimage` command requires a basefile to build disk images having a specific operating system. Execute the following command once to create a basefile for Debian 13:

```sh
cd $HOME/ansible-role-local-vm/config/basefiles
sudo ./mk-basefile TRIXIE64
```

Also ensure that `/etc/fai/apt/sources.list` contains valid sources for Debian 13:

```
deb http://deb.debian.org/debian trixie main
deb http://deb.debian.org/debian-security trixie-security main
```

VM Installation
---------------

After preparing the local system by following the above steps, the FAI configuration space and Ansible role located in `/srv/fai/ansible` can now be used to install new VMs.

Since the Ansible role runs on `localhost` no inventory file is required, only some host variables. The following configuration assumes that your playbooks are located in `$HOME/ansible`.

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
    interface: enp1s0
    ip: 192.168.122.2
    gateway: 192.168.122.1
  ntp:
    cpu: 2
    memory: 2048
    interface: enp1s0
    ip: 192.168.122.3
    gateway: 192.168.122.1
  netbox:
    cpu: 4
    memory: 8192
    interface: enp1s0
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
    - role: ../ansible-role-local-vm
```

```sh
ansible-playbook -K deploy-vms.yml
```

> Note that a sudo password needs to be passed to Ansible via the `-K` parameter, because FAI needs to execute the `fai-diskimage` command as root to build the disk image on the local system.

In this example the result of the play are three local VMs accessible via SSH:

- `dns.internal`
- `ntp.internal`
- `netbox.internal`

Why Ansible?
------------

Of course this whole deployment and installation process for test VMs could just as well be a bash script. For me personally the point of using Ansible is:

- having a playbook for local test deployments adjacent to any other playbooks that configure local or remote VMs
- being able to expand or clone the role for remote deployments (e.g. VMs on Proxmox) and Ansible becomes the more convenient choice

