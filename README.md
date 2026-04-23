# OpenStack Kolla-Ansible Installer Playbooks

This is a very opinionated, slightly configurable set of ansible playbooks for installing OpenStack using kolla-ansible.
The "out of the box" deployment has:
- `1` controller node
- `2` compute nodes

The controller node also accts as the deployer node for kolla-ansible (which is the same host where these playbooks are installed and run).

This deployment was tested using a single server. The requirements for the server would ideally be:
* 128GB RAM (preferably 256GB)
* 1TB HDD (preferably 2TB)
* 32 cores

The server used for the testing had:
* Ubuntu server 24.04
* linux bridge (e.g. "cisco-br") to connect all VMs
* extra NIC ports to use ass  pass-through interfaces for the VMs (allows direct connection of OpenStack compute hosts to the ND fabric)

Here is a diagram of the 3 node setup, connected to the Linux Bridge:

      +---------------------------------------------------------+
      |                       Linux Bridge                      |
      |                        (cisco-br)                       |
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

                            ***** Nexus Dashboard Fabric ******


## Quick Start
On just the controller, run the following commands to install some requirements and clone this repo:
```yaml
sudo -E apt install git -y
sudo -E apt install vim -y
sudo -E apt install ansible -y
ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519
export https_proxy=http://proxy.esl.cisco.com:80
git clone https://github.com/tbachman/kolla-openstack.git
```

Enter the kolla-openstack playbooks directory
```yaml
cd kolla-openstack/
```

Update inventory/hosts.yml based on your hosts. The "deployment"
is the host you're using to run these playbooks from, while the
"controller" is where the server-side OpenStack services will run,
and the "compute_nodes" is where the hypervisor- and agnet-side
OpenStack services will run (note: once you specify the 
ansible_host and kolla_primary_interface_address for a host,
you don't need to do it if it appears again - like kkolla01
in the example below):
```yaml
    deployment:
      hosts:
        kkolla01:
          ansible_host: 192.168.1.200
          kolla_primary_interface_address: 192.168.1.200/24
    controller:
      hosts:
        kkolla01:
    compute_nodes:
      hosts:
        kkolla02:
          ansible_host: 192.168.1.201
          kolla_primary_interface_address: 192.168.1.201/24
        kkolla03:
          ansible_host: 192.168.1.202
          kolla_primary_interface_address: 192.168.1.202/24
```

We should add a new playbook that just does the following steps:

Initially, you may need to change the following in inventory/group_vars/all.yml:
* kolla_network_interface
* kolla_internal_vip_address
* kolla_primary_interface (update gateway, dns_servers, and dns_search)
* kolla_bond (if using a bond - need to set the subordinate interfaces names)
* kolla_ndfc_config (update IP, credentials, and fabric name for your ND instance)

If you're not using bonds, change this variable (configured in inventory/group_vars/all.yml):
* kolla_netplan_bond_enabled: true


Edit your /etc/hosts to add entries for all the nodes (including this one):
```yaml
sudo vi /etc/hosts
```

An example entry:
```yaml
192.168.1.200 kkolla01
```

Now run a script to set up passwordless ssh to all the hosts:
```yaml
for host in $(egrep kolla_primary_interface_address inventory/hosts.yml | awk '{print $NF}' | awk -F"/" '{print $1}'); do ssh-copy-id -o StrictHostKeyChecking=no -i ~/.ssh/id_ed25519.pub noiro@$host; done
```

Then enable passowrdless sudo on all hosts (run these commands on all hosts)
```yaml
echo 'noiro ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/90-ansible-noiro
sudo chmod 440 /etc/sudoers.d/90-ansible-noiro
sudo visudo -cf /etc/sudoers.d/90-ansible-noiro
```


Now run the playbooks
```yaml
ansible-playbook playbooks/00-prepare-hosts.yml
ansible-playbook playbooks/10-deployer-setup.yml
ansible-playbook playbooks/20-configure-kolla.yml
ansible-playbook playbooks/30-deploy.yml
```

At this point, you should have a deployed OpenStack cloud without the integration with ND.

Now update the following in inventory/group_vars/all.yml (note: you will need valid docker registry credentials (username/password) for the following steps to work):
* kolla_enable_neutron_ndfc: true
* kolla_cisco_build_images: true
* kolla_docker_registry_username: <your docker user ID>
* kolla_docker_registry_password: <your docker user password>
* kolla_neutron_type_drivers: nd,geneve,gre,vlan,flat,local (i.e. add "nd" to the list)
* kolla_neutron_tenant_network_types: nd,geneve,gre,vlan,flat,local (i.e. add "nd" to the list)
* kolla_neutron_extension_drivers (un-comment out this next line to enable the extension driver):
  - name: nd_extension_driver

And run the playbook to use the new ansible configuration and build the new images and configuration for the integration with ND:

```yaml
ansible-playbook playbooks/20-configure-kolla.yml
ansible-playbook playbooks/40-cisco-ndfc.yml
```

The Cisco overlay playbook also installs `networking-cisco` into the deployer virtualenv so the OpenStack client can load the Cisco Python client extensions.

Now re-run the OpenStack deploy playbook with the neutron tag to deploy the integration with ND:

```yaml
ansible-playbook playbooks/30-deploy.yml --tags neutron
```
## Repo Layout

- `ansible.cfg`: local project Ansible defaults
- `inventory/hosts.yml`: sample inventory with explicit `controller` and `compute_nodes` role groups
- `inventory/group_vars/all.yml`: deployment variables
- `templates/`: generated Kolla config and optional netplan/build artifacts
- `playbooks/00-prepare-hosts.yml`: host prerequisites for all nodes
- `playbooks/10-deployer-setup.yml`: Python venv and `kolla-ansible` install on the deployer
- `playbooks/20-configure-kolla.yml`: render `/etc/kolla/globals.yml` and `/etc/kolla/multinode`
- `playbooks/30-deploy.yml`: run `install-deps`, `bootstrap-servers`, `prechecks`, `deploy`, and `post-deploy`
- `playbooks/40-cisco-ndfc.yml`: optional Cisco `networking-cisco` overlay and image build preparation

## Assumptions

- OS is Ubuntu 24.04 on all nodes.
- SSH access already works from the deployment host to every target node.
- Hostnames and IPs are known in advance.
- The baseline path uses distro Docker packages for idempotence instead of `get.docker.com`.
- The deployment host must be able to install `kolla-ansible` either from PyPI, an internal Python mirror, or a local wheelhouse.
- The deployment host venv installs a Kolla-supported `ansible-core` and all Kolla commands are run with that venv first on `PATH`.
- Kolla runtime commands also set `ANSIBLE_COLLECTIONS_PATH` so collections installed under the deployer user's home are visible when Kolla invokes Ansible.
- Cisco NDFC support is treated as an optional overlay because it requires patching/building Neutron images.

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

If you run `kolla-ansible` manually with `sudo`, preserve the venv and collection path:

```bash
sudo env \
  PATH=/home/<user>/kolla-venv/bin:$PATH \
  VIRTUAL_ENV=/home/<user>/kolla-venv \
  ANSIBLE_COLLECTIONS_PATH=/home/<user>/.ansible/collections:/usr/share/ansible/collections \
  /home/<user>/kolla-venv/bin/kolla-ansible <subcommand> -i /etc/kolla/multinode
```

## Python Package Source

By default the deployer host installs `kolla-ansible` from public PyPI.

If your environment requires an outbound proxy, set:

```yaml
kolla_http_proxy: "http://proxy.example.com:3128"
kolla_https_proxy: "http://proxy.example.com:3128"
kolla_no_proxy_extra:
  - localhost
  - 127.0.0.1
  - 10.193.253.0/24
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
