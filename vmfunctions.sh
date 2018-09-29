#
# vm-bSave
# by Wil van Antwerpen
# 
# Contains a bunch of standard functions for making backups for vSphere VMs
#
# Parts have been taken from ghettoVCB from William Lam
#
# License: MIT
# See: https://github.com/wilva/vm-bSave for details.

# Used for getting datetime stamps
# Can call from anywhere and will expand to the datetime stamp of that moment.
TIME=`date +'%Y%m%d %H:%M:%S'`

#
# ---------- Variables that are reset on each include of the function library --------------------------------
#

# Shutdown guestOS prior to running backups and power them back on afterwards
# This feature assumes VMware Tools are installed, else they will not power down and loop forever
# 1=on, 0 =off
POWER_VM_DOWN_BEFORE_BACKUP=1

# enable shutdown code 1=on, 0 = off
ENABLE_HARD_POWER_OFF=0

# if the above flag "ENABLE_HARD_POWER_OFF "is set to 1, then will look at this flag which is the # of iterations
# the script will wait before executing a hard power off, this will be a multiple of 60seconds
# (e.g) = 3, which means this will wait up to 180seconds (3min) before it just powers off the VM
ITER_TO_WAIT_SHUTDOWN=3

# Number of iterations the script will wait before giving up on powering down the VM and ignoring it for backup
# this will be a multiple of 60 (e.g) = 5, which means this will wait up to 300secs (5min) before it gives up
POWER_DOWN_TIMEOUT=10

LOG_LEVEL="info"

# always log to STDOUT, use "> /dev/null" to ignore output
LOG_TO_STDOUT=1

# Email log 1=yes, 0=no
EMAIL_LOG=0

# variables to find out what has run, do not set them here
CREATED_ZIP=0

# variables for testing status
ZIP_STATUS_OK=0

# file used to track if we are running
BACKUP_IS_RUNNING=/var/run/backup-is-running


strVMX=""

VMID=0

#
# ---------- Variables that remain state on each include of the function library --------------------------------
#

# Error during zip compression
ERR_ZIP_COUNT=${ERR_ZIP_COUNT=0}

# Error with snapshot operation
ERR_SNAP_COUNT=${ERR_SNAP_COUNT=0}

# Error while cloning data
ERR_CLONE_COUNT=${ERR_CLONE_COUNT=0}

# Error trying to power off VM
ERR_POWEROFF_COUNT=${ERR_POWEROFF_COUNT=0}

# Error powering on a VM
ERR_POWERON_COUNT=${ERR_POWERON_COUNT=0}

# Backup is already running!
ERR_BACKUP_RUNNING=${ERR_BACKUP_RUNNING=0}

#
# ------------------------------------ End of variable declarations ---------------------------------------------
#

#
# ------------------------------------ Determine binary locations -----------------------------------------------
#

if [[ -f /usr/bin/vmware-vim-cmd ]]; then
  VMWARE_CMD=/usr/bin/vmware-vim-cmd
  VMKFSTOOLS_CMD=/usr/sbin/vmkfstools
elif [[ -f /bin/vim-cmd ]]; then
  VMWARE_CMD=/bin/vim-cmd
  VMKFSTOOLS_CMD=/sbin/vmkfstools
else
  logger "info" "ERROR: Unable to locate *vimsh*! You're not running ESX(i) 3.5+, 4.x+ or 5.0!"
  echo "ERROR: Unable to locate *vimsh*! You're not running ESX(i) 3.5+, 4.x+ or 5.0!"
  exit 1
fi

if [[ -f /bin/tar ]]; then
  TAR_CMD=/bin/tar
else
  echo "ERROR: Unable to locate *tar*"
fi

if [[ -f /bin/md5sum ]]; then
  MD5SUM_CMD=/bin/md5sum
else
  echo "ERROR: Unable to locate *md5sum*"
fi

#
# ------------------------------------ End of binary locations -------------------------------------------------
#




logger() {
  LOG_TYPE=$1
  MSG=$2

  if [[ "${LOG_LEVEL}" == "debug" ]] && [[ "${LOG_TYPE}" == "debug" ]] || [[ "${LOG_TYPE}" == "info" ]] || [[ "${LOG_TYPE}" == "dryrun" ]]; then
    TIME=$(date +%F" "%H:%M:%S)
    if [[ "${LOG_TO_STDOUT}" -eq 1 ]] ; then
      echo -e "${TIME} -- ${LOG_TYPE}: ${MSG}"
    fi

    if [[ -n "${LOG_OUTPUT}" ]] ; then
      echo -e "${TIME} -- ${LOG_TYPE}: ${MSG}" >> "${LOG_OUTPUT}"
    fi

    if [[ "${EMAIL_LOG}" -eq 1 ]] ; then
      echo -ne "${TIME} -- ${LOG_TYPE}: ${MSG}\r\n" >> "${EMAIL_LOG_OUTPUT}"
    fi
  fi
}


notifyBackupStarts()
{
  local HOSTBACKUP_PID

  logger "info" "backups started"
  if [[ -f "${BACKUP_IS_RUNNING}" ]]; then
    echo "${TIME} Error, oh dear, backup is already running or did not finish properly last time."
    echo "${TIME} Removing tracker."
    rm -f "${BACKUP_IS_RUNNING}"
    ERR_BACKUP_RUNNING=1
  fi
  touch "${BACKUP_IS_RUNNING}"
  HOSTBACKUP_PID=$$
  echo $HOSTBACKUP_PID > "${BACKUP_IS_RUNNING}"
}

notifyBackupEnds()
{
  if [[ -f "${BACKUP_IS_RUNNING}" ]]; then
  rm -f "${BACKUP_IS_RUNNING}"
  else
   echo -e "${TIME} Error, backup tracking file was already removed by another process."
  fi
  logger "info" "backups ends"
}

setupBackupLocation()
{
  local VM_NAME="$1"
  local VM_LUN="$2"
  local TMP_LUN="$3"

  mkdir "${TMP_LUN}/${VM_NAME}"
  cd "${TMP_LUN}/${VM_NAME}"

  cp -p "${VM_LUN}/${VM_NAME}/"*.vmx   .
  cp -p "${VM_LUN}/${VM_NAME}/"*.vmxf  .
  cp -p "${VM_LUN}/${VM_NAME}/"*.nvram .

  findVMIDForVMname "${VM_NAME}"
  # set global vmx file name
  strVMX="${VM_LUN}/${VM_NAME}/${VM_NAME}.vmx"
}

finishBackup()
{
  local VM_NAME="$1"
  local VM_LUN="$2"

  cp -p "${VM_LUN}/${VM_NAME}/"vmware*.log .

  cd ..

#  createZIP ${strVMname} ${strBUP}
  #rm -rf ${strVMname}
}

powerOff() {
  local VM_NAME="$1"
  local VM_ID="$2"
  local START_ITERATION=0

  POWER_OFF_EC=0

  logger "info" "Powering off initiated for ${VM_NAME}, backup will not begin until VM is off..."

  ${VMWARE_CMD} vmsvc/power.shutdown ${VM_ID} > /dev/null 2>&1

  sleep 45
  while ${VMWARE_CMD} vmsvc/power.getstate ${VM_ID} | grep -i "Powered on" > /dev/null 2>&1; do
    #enable hard power off code
    if [[ ${ENABLE_HARD_POWER_OFF} -eq 1 ]] ; then
      if [[ ${START_ITERATION} -ge ${ITER_TO_WAIT_SHUTDOWN} ]] ; then
        logger "info" "Hard power off occured for ${VM_NAME}, waited for $((ITER_TO_WAIT_SHUTDOWN*60)) seconds"
        ${VMWARE_CMD} vmsvc/power.off ${VM_ID} > /dev/null 2>&1
        #this is needed for ESXi, even the hard power off did not take affect right away
        sleep 60
        break
      fi
    fi

    logger "info" "VM is still on - Iteration: ${START_ITERATION} - sleeping for 60secs (Duration: $((START_ITERATION*60)) seconds)"
    sleep 60

    #logic to not backup this VM if unable to shutdown
    #after certain timeout period
    if [[ ${START_ITERATION} -ge ${POWER_DOWN_TIMEOUT} ]] ; then
      logger "info" "Unable to power off ${VM_NAME}, waited for $((POWER_DOWN_TIMEOUT*60)) seconds! Ignoring ${VM_NAME} for backup!"
      POWER_OFF_EC=1
      ERR_POWERON_COUNT=$((ERR_POWERON_COUNT+1))
      break
    fi
    START_ITERATION=$((START_ITERATION + 1))
  done
  if [[ ${POWER_OFF_EC} -eq 0 ]] ; then
    logger "info" "VM is powered Off"
  fi
}

powerOn() {
  local VM_NAME="$1"
  local VM_ID="$2"
  local START_ITERATION=0

  POWER_ON_EC=0

  logger "info" "Powering on initiated for ${VM_NAME}"

  ${VMWARE_CMD} vmsvc/power.on ${VM_ID} > /dev/null 2>&1
  sleep 50
  while ${VMWARE_CMD} vmsvc/get.guest ${VM_ID} | grep -i "toolsNotRunning" > /dev/null 2>&1; do
    logger "info" "VM is still not booted - Iteration: ${START_ITERATION} - sleeping for 60secs (Duration: $((START_ITERATION*60)) seconds)"
    sleep 60

    #logic to not backup this VM if unable to shutdown
    #after certain timeout period
    if [[ ${START_ITERATION} -ge ${POWER_DOWN_TIMEOUT} ]] ; then
      logger "info" "Unable to detect started tools on ${VM_NAME}, waited for $((POWER_DOWN_TIMEOUT*60)) seconds!"
      POWER_ON_EC=1
      ERR_POWERON_COUNT=$((ERR_POWERON_COUNT+1))
      break
    fi
    START_ITERATION=$((START_ITERATION + 1))
  done
  if [[ ${POWER_ON_EC} -eq 0 ]] ; then
    logger "info" "VM is powered On"
  fi
}

#
# will retrieve a VMID number for the virtual machine name
#
findVMIDForVMname()
{
  local VM_NAME="$1"

  VMID=`vim-cmd vmsvc/getallvms | grep -i "${VM_NAME}/${VM_NAME}.vmx" | cut -d\  -f1`
  logger "info" "VM ${VM_NAME} has vmid ${VMID}"
}


createSnapshot()
{
  local VM_VMX="$1"
  local VM_ID="$2"

  logger "info" "check snapshot ${VM_VMX} with vmid ${VM_ID}"
  ${VMWARE_CMD} vmsvc/snapshot.get ${VM_ID}

  #vmware-cmd ${strVMX} hassnapshot
  logger "info" "making snapshot ${VM_ID}"
  ${VMWARE_CMD} vmsvc/snapshot.create ${VM_ID} "script-backup" "" 1 1
  logger "info" "check snapshot ${VM_ID}"
  ${VMWARE_CMD} vmsvc/snapshot.get ${VM_ID}
}

commitSnapshot()
{
  local VM_VMX="$1"
  local VM_ID="$2"

  echo -e "clone ready, committing snap ${VM_VMX}"
  ${VMWARE_CMD} vmsvc/snapshot.removeall ${VM_ID}

  echo -e "check snapshot ${VM_VMX}"
  ${VMWARE_CMD} vmsvc/snapshot.get ${VM_ID}
}

cloneVMDK()
{
  local VMDK_SOURCE="$1"
  local VMDK_TARGET="$2"
  local VMDK_OUTPUT=""
  local TAIL_PID=0

  # Cool trick from William to prevent a long list of  % completed lines in your output
  VMDK_OUTPUT=$(mktemp /tmp/hostbackup.XXXXXX)
  tail -f "${VMDK_OUTPUT}" &
  TAIL_PID=$!

  ${VMKFSTOOLS_CMD} -i "${VMDK_SOURCE}" -d 2gbsparse "${VMDK_TARGET}" > "${VMDK_OUTPUT}" 2>&1
  VMDK_EXIT_CODE=$?

  kill "${TAIL_PID}"
  cat "${VMDK_OUTPUT}"
  echo
  cp -p "${VMDK_OUTPUT}" "/tmp/tailtest.log"
  rm "${VMDK_OUTPUT}"

  if [[ "${VMDK_EXIT_CODE}" != 0 ]] ; then
    echo -e "Error in backing up ${VMDK_SOURCE} to ${VMDK_TARGET}"
    ERR_CLONE_COUNT=$((ERR_CLONE_COUNT+1))
  fi

}



createZIP()
{
 local VM_NAME="$1"
 local LUN_BUP="$2"
 local ZIP_FILE=""

 CREATED_ZIP=1 # running zip process

 ZIP_FILE="${VM_NAME}-`date +'%Y%m%d'`.tar.gz"

 logger "info" "current folder `pwd`"
 logger "info" "making zip ${ZIP_FILE}"
 ${TAR_CMD} -cvzf "${ZIP_FILE}" "${VM_NAME}"/*
 if [[ $? -eq 0 ]] && [[ -f "${ZIP_FILE}" ]]; then
   ZIP_STATUS_OK=1
   echo -e "Zip file ${ZIP_FILE} was created OK"
   ${MD5SUM_CMD} "${ZIP_FILE}" > "${ZIP_FILE}.md5"
   /bin/mv "${ZIP_FILE}"* "${LUN_BUP}"
   echo -e "ls ${LUN_BUP}"
   ls -alh "${LUN_BUP}/${ZIP_FILE}"*
   if [[ "${VM_NAME}" != "" ]] && [[ -d "${VM_NAME}" ]]; then
     echo "deleting folder ${VM_NAME}"
     rm -rf "${VM_NAME}"
   fi
 else
  ZIP_STATUS_OK=0
  ERR_ZIP_COUNT=$((ERR_ZIP_COUNT+1))
  echo -e "Error creating zip file ${ZIP_FILE}"
 fi
}

errorSummary()
{
 echo -e "--------------------------- ERROR SUMMARY----------------------   "
 echo -e "Number of errors in backup itself               = ${ERR_CLONE_COUNT}"
 echo -e "Number of power Off Errors                      = ${ERR_POWEROFF_COUNT}"
 echo -e "Number of power On Errors                       = ${ERR_POWERON_COUNT}"
 echo -e "Number of errors during compression             = ${ERR_ZIP_COUNT}"
 if [[ "${ERR_BACKUP_RUNNING}" != 0 ]]; then
  echo -e "No backup taken because the backup process was already running!"
 fi
 echo -e "--------------------------- ERROR SUMMARY ENDS-----------------   "
 echo
 echo -e "  U S E D  &  F R E E   D I S K S P A C E "
 echo
 df -h | grep -i -e "filesystem" -e "NFS" -e "VMFS-"
 echo
 echo -e "---------------------------------------------------------------   "

}

errorStatus()
{
 local ERR_POWER_COUNT
 local ERR_COUNT
 BACKUP_STATUS="undefined"

 echo "errorStatus"

 ERR_POWER_COUNT=$((ERR_POWEROFF_COUNT + ERR_POWERON_COUNT))
 echo "EPC = ${ERR_POWER_COUNT}"
 ERR_COUNT=$((ERR_CLONE_COUNT + ERR_POWER_COUNT + ERR_ZIP_COUNT)) 
 echo "EC = ${ERR_COUNT}"
 if [[ "${ERR_COUNT}" -eq 0 ]] && [[ "${ERR_BACKUP_RUNNING}" -eq 0 ]] ; then 
  echo "PASS"
  BACKUP_STATUS="Pass"
 else
  echo "FAIL"
  BACKUP_STATUS="FAIL"
 fi
}
