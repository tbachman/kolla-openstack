# Cisco NDFC Overlay Notes

The baseline project automates the build preparation for the Cisco overlay, but two operational steps are still intentionally manual:

- distributing locally built images to compute nodes
- deciding when to run a Neutron-only reconfigure versus a full deploy

## Suggested flow

1. Set `kolla_enable_cisco_ndfc: true` in `group_vars/all.yml`.
2. Replace placeholder secrets in `kolla_ndfc_config`.
3. Run:

```bash
ansible-playbook playbooks/40-cisco-ndfc.yml
```

4. If you want the playbook to run the actual image build, also set:

```yaml
kolla_cisco_build_images: true
```

5. Verify the images on the deployment host:

```bash
sudo docker images --format 'table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}' \
  | egrep 'kolla/neutron-server|kolla/neutron-cisco-topology-agent'
```

6. Load the images onto compute nodes if you are not using a registry:

```bash
sudo docker save kolla/neutron-server:20.3.0 | ssh kk@kkolla02 'sudo docker load'
sudo docker save kolla/neutron-server:20.3.0 | ssh kk@kkolla03 'sudo docker load'
sudo docker save kolla/neutron-cisco-topology-agent:20.3.0 | ssh kk@kkolla02 'sudo docker load'
sudo docker save kolla/neutron-cisco-topology-agent:20.3.0 | ssh kk@kkolla03 'sudo docker load'
```

7. Reconfigure Neutron:

```bash
ansible-playbook playbooks/30-deploy.yml --tags neutron
```

## What the automation patches

- `/etc/kolla/kolla-build.conf`
- `~/template-overrides.j2`
- `.../share/kolla/docker/neutron/neutron-cisco-topology-agent/Dockerfile.j2`
- `.../share/kolla-ansible/ansible/roles/neutron/templates/ml2_conf.ini.j2`
- `.../site-packages/kolla/common/sources.py`

These are upstream file modifications inside the deployer virtualenv. If you recreate the virtualenv, rerun `playbooks/40-cisco-ndfc.yml`.
