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
