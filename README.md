# katello_tools
Auxiliary scripts for Katello 2.x or Red Hat Satellite 6 admins

#### [gen_errata.py](https://github.com/slivik/katello_tools/blob/master/gen_errata.py)
- Exports list of erratas for systems in specifed organization into CSV file.

#### [prov_vm.rake](https://github.com/slivik/katello_tools/blob/master/prov_vm.rake)

- Rails task written for Foreman (v1.8) hooks. Can be executed by a shell script placed in ```foreman/hooks/host/managed/before_provision``` and ```/after_build```.
- Removes provisioning interface from VM deployed by Foreman and assign provisionig feature to primary interface.
- Add provisioning interface during Rebuild action.
- Execution:
```bash
/usr/sbin/foreman-rake "prov_vm:prov_iface[\"${object}\",\"`date +"%Y%m%d%H%M%S"`\",\"add\"]" --trace >> /tmp/hook_rake.log 2>&1 &
```
