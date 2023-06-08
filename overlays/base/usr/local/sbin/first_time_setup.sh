#!/bin/bash

# Copyright 2021-2022 - Dreemurrs Embedded Labs / DanctNIX Community

# This is a first time boot script, it is supposed to self destruct after the script has finished.

if [ -e /sys/devices/platform/bootsplash.0/enabled ]; then
    echo 0 > /sys/devices/platform/bootsplash.0/enabled
fi

echo "THE FIRST BOOT SCRIPT IS NOW RUNNING, PLEASE WAIT."
echo "ONCE IT'S DONE, YOU'LL BE BOOTED TO THE OPERATING SYSTEM."

date +%Y%m%d -s "REPLACEDATE" # this is changed by the make_rootfs script

# Initialize the pacman keyring
pacman-key --init
pacman-key --populate

if [ -e "/usr/lib/initcpio/hooks/resizerootfs" ]; then
    rm /usr/lib/initcpio/hooks/resizerootfs
    rm /usr/lib/initcpio/install/resizerootfs

    sed -i 's/resizerootfs//g' /etc/mkinitcpio.conf
    mkinitcpio -P
fi

#configuring snapper    
umount /.snapshots
rm -r /.snapshots
snapper --no-dbus -c root create-config /
btrfs subvolume delete /.snapshots
mkdir /.snapshots
mount -a
chmod 750 /.snapshots
#Changing The timeline auto-snap
sed -i 's|QGROUP=""|QGROUP="1/0"|' /etc/snapper/configs/root
sed -i 's|NUMBER_LIMIT="50"|NUMBER_LIMIT="10-15"|' /etc/snapper/configs/root
sed -i 's|NUMBER_LIMIT_IMPORTANT="50"|NUMBER_LIMIT_IMPORTANT="5-10"|' /etc/snapper/configs/root
sed -i 's|TIMELINE_LIMIT_HOURLY="10"|TIMELINE_LIMIT_HOURLY="0"|' /etc/snapper/configs/root
sed -i 's|TIMELINE_LIMIT_DAILY="10"|TIMELINE_LIMIT_DAILY="3"|' /etc/snapper/configs/root
sed -i 's|TIMELINE_LIMIT_WEEKLY="0"|TIMELINE_LIMIT_WEEKLY="2"|' /etc/snapper/configs/root
sed -i 's|TIMELINE_LIMIT_MONTHLY="10"|TIMELINE_LIMIT_MONTHLY="2"|' /etc/snapper/configs/root
sed -i 's|TIMELINE_LIMIT_YEARLY="10"|TIMELINE_LIMIT_YEARLY="0"|' /etc/snapper/configs/root
systemctl enable snapper-timeline.timer
systemctl enable snapper-cleanup.timer

#Resizing Btrfs filesystem
btrfs filesystem resize max /

# Cleanup
rm /usr/local/sbin/first_time_setup.sh
rm /usr/lib/systemd/system/first_time_setup.service
rm /usr/lib/systemd/system/basic.target.wants/first_time_setup.service

if [ -e /sys/devices/platform/bootsplash.0/enabled ]; then
    echo 1 > /sys/devices/platform/bootsplash.0/enabled
fi
