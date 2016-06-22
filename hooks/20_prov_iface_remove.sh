#!/bin/bash -x
. $(dirname $0)/hook_functions.sh
object=${HOOK_OBJECT}
echo "`date +"%Y%m%d%H%M%S"`: Hook script \"$0\" try to run rake task for ${object} in background." >> $LOGFILE
/usr/sbin/foreman-rake "prov_vm:prov_iface[\"${object}\",\"`date +"%Y%m%d%H%M%S"`\",\"remove\"]" --trace >> $LOGFILE 2>&1 &
exit 0
