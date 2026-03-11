#! /bin/bash

# (c) Thomas Lange, 2002-2024, lange@cs.uni-koeln.de
# slightly adjusted to also save the name of the first interface

# NOTE: Files named *.sh will be sourced, but their output is ignored.

inside_nfsroot || return 0 # Do only execute when doing install

echo 0 > /proc/sys/kernel/printk

kernelmodules+=" md-mod"
for mod in $kernelmodules; do
    [ X$verbose = X1 ] && echo Loading kernel module $mod
    modprobe -a $mod 1>/dev/null 2>&1
done
unset mod

INTERFACE=$(ip -4 -brief -oneline link show | egrep -m 1 -v ^lo | awk '{ print $1 }')
echo INTERFACE=\"$INTERFACE\" >> $LOGDIR/additional.var

echo $printk > /proc/sys/kernel/printk

odisklist=$disklist
set_disk_info  # recalculate list of available disks
if [ "$disklist" != "$odisklist" ]; then
    echo New disklist: $disklist
    echo disklist=\"$disklist\" >> $LOGDIR/additional.var
fi
unset odisklist

save_dmesg     # save new boot messages (from loading modules)
