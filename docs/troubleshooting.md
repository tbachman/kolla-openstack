# Troubleshooting

## Load admin credentials

```bash
source /etc/kolla/admin-openrc.sh
source ~/kolla-venv/bin/activate
```

## Inspect Neutron server state

```bash
docker exec -itu root neutron_server bash
cat /etc/neutron/plugins/ml2/ml2_conf.ini
cat /var/log/kolla/neutron/neutron-server.log
```

To search for a specific host or switch identifier:

```bash
grep -F "kkbd2006" /var/log/kolla/neutron/neutron-server.log
```

## Cisco Neutron database checks

```bash
docker exec -itu root neutron_server \
  neutron-cisco-db-tool --config-file /etc/neutron/neutron.conf list-nxos-links
```

## Quick health checks

```bash
openstack service list
openstack network agent list
docker ps --format 'table {{.Names}}\t{{.Status}}'
ovs-vsctl show
```

## Horizon

- URL: `http://<kolla_internal_vip_address>`
- User: `admin`
- Domain: `Default`

Retrieve the admin password from:

```bash
grep keystone_admin_password /etc/kolla/passwords.yml
```
