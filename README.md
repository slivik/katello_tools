# katello_tools
Auxiliary scripts for Katello 2.x or Red Hat Satellite 6 admins

#### [gen_errata.py](https://github.com/slivik/katello_tools/blob/master/gen_errata.py)
- Exports list of erratas for systems in specifed organization into CSV file.

#### [prov_vm.rake](https://github.com/slivik/katello_tools/blob/master/hooks/prov_vm.rake)

- Rails task written for Foreman (v1.8) hooks. Can be executed by a shell script placed in ```foreman/hooks/host/managed/before_provision``` and ```/after_build```.
- Removes provisioning interface from VM deployed by Foreman and assign provisionig feature to primary interface.
- Add provisioning interface during Rebuild action.
- Execution:
```bash
/usr/sbin/foreman-rake "prov_vm:prov_iface[\"${object}\",\"`date +"%Y%m%d%H%M%S"`\",\"add\"]" --trace >> /tmp/hook_rake.log 2>&1 &
```

#### [provisioning_templates](https://github.com/slivik/katello_tools/tree/master/provisioning_templates)
- Temlpates for provision RHEL 6, RHEL 7, Centos 7 and SLES 11 SP3.
- Works with SafeMode enabled.
