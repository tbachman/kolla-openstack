Install kolla-ansible into /opt/kolla-venv:
sudo ./boostrap.sh

Edit globals.yml (search for CHANGE_ME):
kolla-Internal_vip_address: "192.168.100.10" # fre IP on your network
network_interface: "eth0"                    # management NIC
neutron_external_interface: "eth1"           # provider network NIC (no IP)

sudo ./deploy.sh

OpenStack release: 2024.1 (Caracal) - cahnge KOLLA_BRANCH env var or --branch flag
Hypervisor:        nova_compute_virt_type: kvm - change to qemu if running in a VM
Services enabled:  Nova, Glance, Neutron, Keystone, Horizon, Heat, HAProxy
Cinder:            Disabled by default - set enable_cinder: "yes" and create on LVM VG


sudo ./deploy.sh --step prechecks          # validate only
sudo ./deploy.sh --step deploy --tags nova # redeploy just Nova
sudo ./deploy.sh --multinode               # use multinode inventory

The nova_compute_virt_type will need to be set to qemu if your target host is itself a VM (nested virtualisation).

