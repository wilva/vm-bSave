#!/bin/sh
#
# Exports the entire dotis machine and makes it available as a tar.gz
# download. Is a little more advanced as it does this by making a snapshot
# then clone basedisk, then clone disk, after which it will commit

strVMname="dotis"
strLUN="/vmfs/volumes/storage1"
strTMP="/vmfs/volumes/temp"
strBUP="/vmfs/volumes/backups"

# load vmfunctions
. /vmfs/volumes/iSCSIX/root/backup/vmfunctions.sh


setupBackupLocation "${strVMname}" "${strLUN}" "${strTMP}"

powerOff "${strVMname}" ${VMID}
if [[ ${POWER_OFF_EC} -eq 0 ]] ; then
  createSnapshot "${strVMX}" ${VMID}

  powerOn "${strVMname}" ${VMID}

  cloneVMDK "${strLUN}/${strVMname}/${strVMname}.vmdk" "${strTMP}/${strVMname}/${strVMname}.vmdk" "2gbsparse"

  commitSnapshot "${strVMX}" ${VMID}

  finishBackup "${strVMname}" "${strLUN}"

  createZIP ${strVMname} ${strBUP}

else

  echo "PowerOff failed, triggering a powerOn to make sure we don't get a shutdown VM"
  powerOn "${strVMname}" "${VMID}"
fi
