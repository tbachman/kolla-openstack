# OpenStack Kolla Playbooks

An Ansible project for deploying OpenStack Epoxy (`stable/2025.1`) with `kolla-ansible` on:

- `1` controller node
- `2` compute nodes
- the controller also acting as the deployment host

The scaffold is based on the deployment notes you supplied, but reorganized into repeatable playbooks and templates.

## Layout

- `ansible.cfg`: local project Ansible defaults
- `inventory/hosts.yml`: sample inventory for `kkolla01-03`
- `inventory/group_vars/all.yml`: deployment variables
- `templates/`: generated Kolla config and optional netplan/build artifacts
- `playbooks/00-prepare-hosts.yml`: host prerequisites for all nodes
- `playbooks/10-deployer-setup.yml`: Python venv and `kolla-ansible` install on the deployer
- `playbooks/20-configure-kolla.yml`: render `/etc/kolla/globals.yml` and `/etc/kolla/multinode`
- `playbooks/30-deploy.yml`: run `install-deps`, `bootstrap-servers`, `prechecks`, `deploy`, and `post-deploy`
- `playbooks/40-cisco-ndfc.yml`: optional Cisco `networking-cisco` overlay and image build preparation
- `playbooks/site.yml`: baseline end-to-end entry point

## Assumptions

- OS is Ubuntu 24.04 on all nodes.
- SSH access already works from the deployment host to every target node.
- Hostnames and IPs are known in advance.
- The baseline path uses distro Docker packages for idempotence instead of `get.docker.com`.
- The deployment host must be able to install `kolla-ansible` either from PyPI, an internal Python mirror, or a local wheelhouse.
- The deployment host venv installs a Kolla-supported `ansible-core` and all Kolla commands are run with that venv first on `PATH`.
- Kolla runtime commands also set `ANSIBLE_COLLECTIONS_PATH` so collections installed under the deployer user's home are visible when Kolla invokes Ansible.
- Cisco NDFC support is treated as an optional overlay because it requires patching/building Neutron images.

## Quick Start

1. Review and edit `inventory/hosts.yml`.
   Set `kolla_primary_interface_address` per host if you enable netplan management.
2. Review and edit `inventory/group_vars/all.yml`.
   If the controller needs a proxy for outbound access, set `kolla_http_proxy`, `kolla_https_proxy`, and extend `kolla_no_proxy` for your internal addresses.
   If you also use an internal Python mirror or wheelhouse, set `kolla_pip_extra_args` or `kolla_pip_wheelhouse` as needed.
   Set `kolla_host_entries` so each node's real hostname is present, with short aliases as needed.
3. Run the baseline flow:

```bash
ansible-playbook playbooks/site.yml
```

If you run `kolla-ansible` manually with `sudo`, preserve the venv and collection path:

```bash
sudo env \
  PATH=/home/<user>/kolla-venv/bin:$PATH \
  VIRTUAL_ENV=/home/<user>/kolla-venv \
  ANSIBLE_COLLECTIONS_PATH=/home/<user>/.ansible/collections:/usr/share/ansible/collections \
  /home/<user>/kolla-venv/bin/kolla-ansible <subcommand> -i /etc/kolla/multinode
```

4. If you need the Cisco NDFC overlay, enable `kolla_enable_cisco_ndfc: true` in `inventory/group_vars/all.yml` and run:

```bash
ansible-playbook playbooks/40-cisco-ndfc.yml
```

5. Re-run the Neutron deploy stage after the custom images are available:

```bash
ansible-playbook playbooks/30-deploy.yml --tags neutron
```

## What The Playbooks Do

### Baseline deployment

- disables cloud-init network management
- optionally manages a netplan file for static addressing and bonding
- reads the primary NIC address from each host's inventory vars
- only enables the bond stanza for hosts in the `compute` group by default
- keeps the controller on the OVN control plane and, in this topology, also models it as the OVS/OVN network node that owns the external bridge
- installs required packages on all nodes
- manages `/etc/hosts` entries with a real hostname and optional aliases per node
- enables Docker and Chrony
- installs `openvswitch-switch` but, by default, stops the host service and cleans stale runtime files so Kolla's OVS containers can own `/run/openvswitch`
- installs `openvswitch-switch` but, by default, stops the host service
- leaves OVS runtime cleanup disabled by default because deleting `/run/openvswitch` on an already deployed host breaks live Kolla OVS containers
- creates the deployer virtualenv
- installs `kolla-ansible` `20.x` from PyPI, a mirror, or a local wheelhouse
- renders Kolla inventory and globals
- generates `passwords.yml` if missing
- runs the normal Kolla lifecycle
- installs `python3-openstackclient` on the deployer and makes `/etc/kolla/admin-openrc.sh` readable after `post-deploy`

## Python Package Source

By default the deployer host installs `kolla-ansible` from public PyPI.

If your environment requires an outbound proxy, set:

```yaml
kolla_http_proxy: "http://proxy.example.com:3128"
kolla_https_proxy: "http://proxy.example.com:3128"
kolla_no_proxy:
  - localhost
  - 127.0.0.1
  - 10.193.253.0/24
  - kkolla01
  - kkolla02
  - kkolla03
```

Those values are applied to `apt`, `pip`, `kolla-ansible`, and `kolla-build` commands run by these playbooks.
When set, the host prep playbook also writes a Docker systemd proxy drop-in so image pulls use the same proxy.

If your deployment host is isolated, set one of these in `inventory/group_vars/all.yml`:

```yaml
kolla_pip_extra_args: "--index-url https://<your-pypi-mirror>/simple --trusted-host <your-pypi-mirror>"
```

or:

```yaml
kolla_pip_wheelhouse: /opt/wheelhouse
```

With `kolla_pip_wheelhouse`, the playbook installs using `--no-index --find-links /opt/wheelhouse`, so the required packages must already exist in that directory on the deployment host.

### Cisco overlay

- installs `kolla` into the same virtualenv so `kolla-build` is available
- renders `kolla-build.conf`
- writes the template override used to install `/plugins/*` into `neutron-server`
- adds a custom `neutron-cisco-topology-agent` Dockerfile template
- patches the upstream `ml2_conf.ini.j2`
- patches `kolla/common/sources.py` to recognize the topology agent source

This project does not automatically distribute built images to compute nodes. The original notes used `docker save | ssh docker load`; that is left as an explicit operational step because image distribution strategy depends on your registry model.

## Notes

- `playbooks/30-deploy.yml` runs Kolla commands from the deployment host only.
- `playbooks/40-cisco-ndfc.yml` prepares the build environment and can optionally run `kolla-build`.
- `kolla_manage_host_openvswitch_service: false` is the default because this scaffold assumes Kolla-managed OVS/OVN containers rather than a permanently running host OVS service.
- `kolla_cleanup_openvswitch_runtime` should only be enabled for one-time recovery before a host-limited Kolla deploy; it is intentionally `false` by default.
- Sensitive values in `inventory/group_vars/all.yml` are placeholders and should be replaced before use.


This is a very opinionated, slightly configurable set of playbooks to install OpenStack using kolla-ansible.

Hypervisor:
* Ubuntu server
* create linux bridge to connect all VMs
* have enough NIC ports on the hypervisor to support pass-through interfaces to the VMs used as compute nodes for OpenStack
*
You need to create 3 VMs:
* Controller VM. This only needs a

      +---------------------------------------------------------+
      |                       Linux Bridge                      |
      |                          (br0)                          |
      +---------------------------------------------------------+
              |                  |                  |
              |                  |                  |
      +-------|-------+  +-------|-------+  +-------|-------+
      |    [veth0]    |  |    [veth1]    |  |    [veth2]    |
      |               |  |               |  |               |
      |      VM       |  |      VM       |  |      VM       |
      |   Controller  |  |   Compute 1   |  |   Compute 2   |
      +---------------+  +---|-------|---+  +---|-------|---+
                             |       |          |       |
                          [eth1]   [eth2]    [eth1]   [eth2]
                             |       |          |       |
                             |       |          |       |


Initially, you'll need to change the following in inventory/group_vars/all.yml:
* kolla_no_proxy:
* kolla_internal_vip_address
* kolla_host_entries

You'll also need to change the hosts and IPs in inventory/hosts.yml

Here are the commands that I had to run on the controller:

# on just the controller
sudo -E apt install net-tools
sudo -E apt install git
sudo -E apt install vim
sudo -E apt install iputils-ping
sudo -E apt install ansible -y
export https_proxy=http://proxy.esl.cisco.com:80
git clone https://github.com/tbachman/kolla-openstack.git
cd kolla-openstack/
sudo vi /etc/hosts
ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519
ssh-copy-id -i ~/.ssh/id_ed25519.pub noiro@kkolla04
ssh-copy-id -i ~/.ssh/id_ed25519.pub noiro@kkolla05
ssh-copy-id -i ~/.ssh/id_ed25519.pub noiro@kkolla06

# on all hosts
echo 'noiro ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/90-ansible-noiro
sudo chmod 440 /etc/sudoers.d/90-ansible-noiro
sudo visudo -cf /etc/sudoers.d/90-ansible-noiro

Make sure you have bonding enabled if you're using bonds (configured in inventory/group_vars/all.yml):
kolla_netplan_bond_enabled: true

You may need to configure the networking parameters (including the bond) here:
kolla_network_interface: enp1s0
kolla_bond
  name: bond0
  mtu: 9000
  interfaces:
    - enp7s0
    - enp8s0

# now run the playbooks
ansible-playbook playbooks/00-prepare-hosts.yml
ansible-playbook playbooks/10-deployer-setup.yml
ansible-playbook playbooks/20-configure-kolla.yml
ansible-playbook playbooks/30-deploy.yml

At this point, you should have a deployed OpenStack cloud without the integration with ND.

Now set in inventory/group_vars/all.yml:
* kolla_enable_cisco_ndfc: true
* kolla_cisco_build_images: true
* kolla_docker_registry_username: <your docker user ID>
* kolla_docker_registry_password: <your docker user password>
* kolla_neutron_type_drivers: nd,geneve,gre,vlan,flat,local
* kolla_neutron_tenant_network_types: nd,geneve,gre,vlan,flat,local
* kolla_neutron_extension_drivers:
  - name: nd_extension_driver

And run the playbook to use the new ansible configuration and build the new images and configuration for the integration with ND:

ansible-playbook playbooks/20-configure-kolla.yml
ansible-playbook playbooks/40-cisco-ndfc.yml


The playbook is missing the step that pushes the images to the compute nodes:
docker save kolla/neutron-cisco-topology-agent:20.3.0 | ssh kkolla05 'docker load'

I also have to fix the extension drivers config - the parameter in inventory/group_vars/all.yml isn't updateing /etc/kolla/globals.yml

Now re-run the OpenStack deploy playbook with the neutron tag to deploy the integration with ND:

ansible-playbook playbooks/30-deploy.yml --tags neutron
