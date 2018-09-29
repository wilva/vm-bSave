#!/bin/sh
#
# Imports the entire alexida machine as a ready to run VM from our local storage.
# The import is from a LIVE VM, folder name = vmx name = first disk name
# Old imports WILL be removed and overwritten! 

strVMname="Alexida"
strLUN="/vmfs/volumes/storage1"
strIMPORT="/vmfs/volumes/backups"

rm -rf ${strIMPORT}/${strVMname}

# load vmfunctions
. /vmfs/volumes/backups/vmfunctions.sh

rm -rf ${strIMPORT}/${strVMname}

setupBackupLocation "${strVMname}" "${strLUN}" "${strIMPORT}"

createSnapshot "${strVMX}" ${VMID}

cloneVMDK "${strLUN}/${strVMname}/${strVMname}.vmdk" "${strIMPORT}/${strVMname}/${strVMname}.vmdk" "2gbsparse"

commitSnapshot "${strVMX}" ${VMID}

finishBackup "${strVMname}" "${strLUN}"

