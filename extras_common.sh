#!/bin/sh
## this file must be sourced to operate in the correct directory
mkdir -p etc/conf.d

## REBOOT MANAGER
## - The clearlock scripts dequeues the node from the reboot queue stored in consul
cp -a ../dist/scripts/clearlock etc/init.d/clearlock
chmod +x etc/init.d/clearlock
rm sbin/reboot ## remove to avoid following symlink during copy
cp -a ../dist/scripts/reboot.sh sbin/reboot
cp -a ../dist/scripts/reboot_locker sbin/
cp -a ../dist/scripts/reboot_try_queue sbin/
chmod +x sbin/reboot sbin/reboot_locker sbin/reboot_try_queue

## basic files for cluster management
touch etc/cluster etc/leaders etc/workers

## ssh wrapper to load environment vars which dropbear does not support
cp -a ../dist/scripts/ssheval usr/bin/ssheval
chmod +x usr/bin/ssheval
# DROPBEAR OPTIONS
mkdir -m 700 -p root/.ssh home/pine/.ssh
# increase default window size
echo "DROPBEAR_OPTS=\"-W 1MB\"" > /etc/conf.d/dropbear

## iomon script: some VMs experience I/O failure, use iostat to monitor potential stalls and reboot on occasion
cp -a ../dist/scripts/iomon usr/bin/iomon
chmod +x usr/bin/iomon

## some utility shell functions
cp ../functions.sh etc/profile.d/func.sh
## make sure core dumps are disabled
cat ../dist/cfg/profile /etc/profile > etc/profile

## enable boot logging
sed -r 's/#?(rc_logger=).*/\1"YES"/' -i etc/rc.conf

## backup config
DUP_VER=$(last_version gilbertchen/duplicacy)
eval 'echo "'"$(<../templates/dup)"'"' >etc/conf.d/dup

cp -a ../dist/scripts/consul_nameserver etc/init.d/consul_nameserver
chmod +x etc/init.d/consul_nameserver
