# vm-bSave
vSphere Esxi backup scripts

VM Be safe: Bash scripts to backup your VMs. 

This is very minimal set of bash scripts that can be used for backing up your virtual amchines hosted at a vSphere host.

Around 2007 I wrote my initial VM disk manipulation script that ended up as the bases for these scripts.
Back then it was meant for moving a VM to a new storage ( https://communities.vmware.com/thread/89885 ) 
This was the bases for these simple backup scripts in bash.

It is also what I ended up using for backing up all my vSphere scripts and I have been using it for many years.

The logic for the scripts on how-to backup a running VM is based on what I learned from Alex Mittel's VISBU ( https://communities.vmware.com/thread/73147 ) and a tiny bit has been inspired by William Lam's excellent GhettoVCB ( https://github.com/lamw/ghettoVCB ) 
For whatever reason I had to roll my own.

The only thing new at the time of publishing is the name. :) and the license.

The main logic for making the backups is in the file vmfunctions.sh

The way it works is by writing a short script per VM, a few examples have been included.

The backup script isn't trying to be smart you have to tell it in a few lines on what it has to do.

Let's look at the backup-alexida example.
The VM is named "Alexida" and has only 1 disk.
It is running from local storage at /vmfs/volumes/storage1 and we want to make a backup of it without
interrupting the VM. The VM keeps on running during the backup and the backup made is a so called crash-consistent backup.

The script looks like this:
=====
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

setupBackupLocation "${strVMname}" "${strLUN}" "${strIMPORT}"

createSnapshot "${strVMX}" ${VMID}

cloneVMDK "${strLUN}/${strVMname}/${strVMname}.vmdk" "${strIMPORT}/${strVMname}/${strVMname}.vmdk" "2gbsparse"

commitSnapshot "${strVMX}" ${VMID}

finishBackup "${strVMname}" "${strLUN}"
=====

First we set 3 variables.

The rm -rf line will delete the previous backup completely if it is still there! (We have another script running that already has made a zip archive of the VM so in our scenario that is fine)

Then we load all the functions for making the backup from the vmfunctions.sh file. As you see it is located on the backup location so that it is easy to access from multiple hosts.

The first function called setupBackupLocation does a few things such as create the backup folder at {strIMPORT} and copies the basic configuration such as the .vmx/.nvram/.vmxf files from {strLUN}. It also looks up the current {VMID} for the VM which we can use later one and constructs the full .vmx path based on strVMname and strLUN. This means that your .vmx filename should match the foldername it is running in! (If not, then you can override it here)

The createSnapshot function takes the VMID and vmx file and creates a snapshot of your VM.

cloneVMDK creates a clone of the vmdk file using the 2GB sparse format. 
If you have a VM with more than 1 vmdk file then add more lines.
Example: 
This would copy /vmfs/volumes/storage1/Alexida/Alexida_1.vmdk to /vmfs/volumes/backups/Alexida/Alexida_1.vmdk

cloneVMDK "${strLUN}/${strVMname}/${strVMname}_1.vmdk" "${strIMPORT}/${strVMname}/${strVMname}_1.vmdk" "2gbsparse"
So one line for each vmdk you want to backup.

After the copying of the data has completed, we can commit the snapshot and finish up the backup.
The last step copies the logs.


Another example creates completely consistent backups, but in order to do so it shuts down the VM.
This is a very short interruption as it will quickly make a snapshot and then restart the VM after which the lengthy part of the process starts.

You can see this in the demo file : store-dotis.sh

It has one extra step at the end where it zips the VM too. The resulting vm is uniquely named with the datetime suffixed to the vm name.

eg. dotis-20180923.tar.gz

Please note that you only should do this for smaller VMs as you are running this on your vSphere console and that is not the best place for a lot of heavy CPU processing tasks.
