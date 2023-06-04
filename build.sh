#!/bin/bash

# SPDX-License-Identifier: GPL-3.0-only
# Copyright 2021 Dang Huynh <danct12@disroot.org>

set -e

SUPPORTED_ARCHES=(aarch64 armv7)
NOCONFIRM=0
OSK_SDL=0
username="alarm"
password="123456"
NO_BOOTLOADER=0
use_mesa_git=0
output_folder="build"
mkdir -p "$output_folder"
cachedir="$output_folder/pkgcache"
temp=$(mktemp -p $output_folder -d)
date=$(date +%Y%m%d)

error() { echo -e "\e[41m\e[5mERROR:\e[49m\e[25m $1" && exit 1; }
check_dependency() { [ $(which $1) ] || error "$1 not found. Please make sure it is installed and on your PATH."; }
usage() { error "$0 [-a ARCHITECTURE] [-d device] [-u ui] [-h hostname] [--username username] [--password password] [--osk-sdl] [--noconfirm] [--cachedir directory] [--no-cachedir]"; }
cleanup() {
    trap '' EXIT
    trap '' INT
    if [ -d "$temp" ]; then
        unmount_chroot
        rm -r "$temp"
    fi
}

trap cleanup EXIT
trap cleanup INT

pre_check() {
    check_dependency wget
    check_dependency bsdtar
    check_dependency fallocate
    check_dependency fdisk
    check_dependency losetup
    check_dependency mkfs.vfat
    check_dependency mkfs.ext4
    check_dependency mkfs.btrfs
    check_dependency genfstab
    check_dependency lsof
    chmod 755 "$temp"
}

parse_args() {
    while [ $# -gt 0 ]; do
        case $1 in
            -a|--arch) arch=$2; shift ;;
            -d|--device) device=$2; shift ;;
            -u|--ui) ui=$2; shift ;;
            --username) username=$2; shift ;;
	    --password) password=$2; shift ;;
            -h|--hostname) hostname=$2; shift ;;
            --noconfirm) NOCONFIRM=1;;
            --osk-sdl) OSK_SDL=1;;
            --cachedir) cachedir=$2; shift ;;
            --no-cachedir) cachedir= ;;
            *) usage ;;
        esac
        shift
    done
}

parse_presets() {
    [ ! -e "devices/$device" ] && error "Device \"$device\" is unknown!"
    [ ! -e "ui/$ui" ] && error "User Interface \"$ui\" is unknown!"

    [ ! -e "devices/$device/config" ] && error "\"$device\" doesn't have a config file!" \
        || source "devices/$device/config"

    for i in $(cat "devices/$device/packages"); do
        packages_device+=( $i )
    done

    for i in $(cat "ui/$ui/packages"); do
        [ $use_mesa_git -gt 0 ] && [ $i = "mesa" ] && i="mesa-git"
        packages_ui+=( $i )
    done

    if [ -e "devices/$device/packages-$ui-extra" ]; then
        for i in $(cat "devices/$device/packages-$ui-extra"); do
            packages_ui+=( $i )
        done
    fi

    if [ -e "ui/$ui/postinstall" ]; then
        while IFS= read -r postinstall_line; do
            postinstall+=("$postinstall_line\n")
        done < ui/$ui/postinstall
    fi
}

check_arch() {
    echo ${SUPPORTED_ARCHES[@]} | grep -q $arch || { echo "$arch is not supported. Supported architecture are: ${SUPPORTED_ARCHES[@]}" && exit 1; }
}

download_rootfs() {
    [ $NOCONFIRM -gt 0 ] && [ -f "$output_folder/ArchLinuxARM-$arch-latest.tar.gz" ] && return

    [ -f "$output_folder/ArchLinuxARM-$arch-latest.tar.gz"  ] && {
        read -rp "Stock rootfs already exist, delete it? (y/n) " yn
        case $yn in
            [Yy]*) rm "$output_folder/ArchLinuxARM-$arch-latest.tar.gz" ;;
            [Nn]*) return ;;
            *) echo "Aborting." && exit 1 ;;
        esac; }

    wget -O "$output_folder/ArchLinuxARM-$arch-latest.tar.gz" http://os.archlinuxarm.org/os/ArchLinuxARM-$arch-latest.tar.gz

    pushd .
    cd $output_folder && { curl -s -L http://os.archlinuxarm.org/os/ArchLinuxARM-$arch-latest.tar.gz.md5 | md5sum -c \
        || { rm ArchLinuxARM-$arch-latest.tar.gz && error "Rootfs checksum failed!"; } }
    popd
}

extract_rootfs() {
    [ -f "$output_folder/ArchLinuxARM-$arch-latest.tar.gz" ] || error "Rootfs not found"
    bsdtar -xpf "$output_folder/ArchLinuxARM-$arch-latest.tar.gz" -C "$temp"
}

mount_chroot() {
    mount -o bind /dev "$temp/dev"
    mount -t proc proc "$temp/proc"
    mount -t sysfs sys "$temp/sys"
    mount -t tmpfs tmpfs "$temp/tmp"
}

unmount_chroot() {
    for i in $(lsof +D "$temp" | tail -n+2 | tr -s ' ' | cut -d ' ' -f 2 | sort -nu); do
        kill -9 $i
    done

    for i in $(cat /proc/mounts | awk '{print $2}' | grep "^$(readlink -f $temp)"); do
        [ $i ] && umount -l $i
    done
}

mount_cache() {
    if [ -n "$cachedir" ]; then
        mkdir -p "$cachedir"
        mount --bind "$cachedir" "$temp/var/cache/pacman/pkg" || error "Failed to mount pkg cache!";
    fi
}

unmount_cache() {
    if [[ $(findmnt "$temp/var/cache/pacman/pkg") ]]; then
        umount -l "$temp/var/cache/pacman/pkg" || error "Failed to unmount pkg cache!";
    fi
}

do_chroot() {
    chroot "$temp" "$@"
}

init_rootfs() {
    if [ $OSK_SDL -gt 0 ]; then
        rootfs_tarball="rootfs-$device-$ui-$date-osksdl.tar.gz"
        packages_ui+=( osk-sdl )
    else
        rootfs_tarball="rootfs-$device-$ui-$date.tar.gz"
    fi

    [ $NOCONFIRM -gt 0 ] && [ -f "$output_folder/$rootfs_tarball" ] && rm "$output_folder/$rootfs_tarball"

    [ -f "$output_folder/$rootfs_tarball"  ] && {
        read -rp "Rootfs seems to have generated before, delete it? (y/n) " yn
        case $yn in
            [Yy]*) rm "$output_folder/$rootfs_tarball" ;;
            [Nn]*) return ;;
            *) echo "Aborting." && exit 1 ;;
        esac; }

    download_rootfs
    extract_rootfs
    mount_chroot
    mount_cache

    rm "$temp/etc/resolv.conf"
    cat /etc/resolv.conf > "$temp/etc/resolv.conf"

    cp "overlays/base/etc/pacman.conf" "$temp/etc/pacman.conf"

    if [[ $ui = "barebone" ]]; then
        sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/g' "$temp/etc/locale.gen"
    fi

    echo "${hostname:-danctnix-btrfs}" > "$temp/etc/hostname"

    # Download our gpg key and install it first, this however will be overwritten with our package later.
    wget https://raw.githubusercontent.com/dreemurrs-embedded/Pine64-Arch/master/PKGBUILDS/danctnix/danctnix-keyring/danctnix.gpg \
        -O "$temp/usr/share/pacman/keyrings/danctnix.gpg"
    wget https://raw.githubusercontent.com/dreemurrs-embedded/Pine64-Arch/master/PKGBUILDS/danctnix/danctnix-keyring/danctnix-trusted \
        -O "$temp/usr/share/pacman/keyrings/danctnix-trusted"

    cat > "$temp/second-phase" <<EOF
#!/bin/bash
set -e
pacman-key --init
pacman-key --populate archlinuxarm danctnix
pacman -Rsn --noconfirm linux-$arch
pacman -Syu --noconfirm --overwrite=*
 if [[ $ui = "plasma" ]]; then
        pacman -S --noconfirm --overwrite=* --needed pipewire-media-session 
 fi
pacman -S --noconfirm --overwrite=* --needed ${packages_device[@]} ${packages_ui[@]}


systemctl disable sshd
systemctl disable systemd-networkd
systemctl disable systemd-resolved
systemctl enable zramswap
systemctl enable NetworkManager

userdel alarm
rm -rfd /home/alarm
useradd -m $username

if [ $ui == "plasma" ]; then
groupadd -r autologin
usermod -a -G autologin,network,video,audio,rfkill,wheel $username
else
usermod -a -G network,video,audio,rfkill,wheel $username
fi

$(echo -e "${postinstall[@]}")

cp -rv /etc/skel/. /home/$username
chown -R $username:$username /home/$username

if [ -e /etc/sudoers ]; then
    sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
fi

cat << FOE | passwd $username
$password
$password

FOE

locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# remove pacman gnupg keys post generation
rm -rf /etc/pacman.d/gnupg
rm /second-phase
EOF

    chmod +x "$temp/second-phase"
    do_chroot /second-phase || error "Failed to run the second phase rootfs build!"

    cp -r overlays/base/* "$temp/"
    [ -d "overlays/$ui" ] && cp -r overlays/$ui/* "$temp/"
    [ -d "devices/$device/overlays/base" ] && cp -r devices/$device/overlays/base/* "$temp/"
    [ -d "devices/$device/overlays/$ui" ] && cp -r devices/$device/overlays/$ui/* "$temp/"

    if [ -e "$temp/usr/lib/initcpio/hooks/resizerootfs" ] && [ $OSK_SDL -gt 0 ]; then
        rm -f $temp/usr/lib/initcpio/hooks/resizerootfs
        rm -f $temp/usr/lib/initcpio/install/resizerootfs
    fi

    [ -e "$temp/usr/lib/initcpio/hooks/resizerootfs" ] && sed -i 's/fsck/resizerootfs fsck/g' "$temp/etc/mkinitcpio.conf"
    [ -e "$temp/usr/lib/initcpio/hooks/osk-sdl" ] && sed -i 's/fsck/osk-sdl fsck/g' "$temp/etc/mkinitcpio.conf"
    [ -e "$temp/usr/lib/initcpio/install/bootsplash-danctnix" ] && sed -i 's/fsck/fsck bootsplash-danctnix/g' "$temp/etc/mkinitcpio.conf"
    sed -i 's/base udev/base udev btrfs/g' "$temp/etc/mkinitcpio.conf"
    sed -i 's/fsck / /g' "$temp/etc/mkinitcpio.conf"
    sed -i 's/MODULES=()/MODULES=(btrfs)/g' "$temp/etc/mkinitcpio.conf"
    sed -i "s/REPLACEDATE/$date/g" "$temp/usr/local/sbin/first_time_setup.sh"

    [[ "$ui" != "barebone" ]] && do_chroot passwd -d root

    [ -d "$temp/usr/share/glib-2.0/schemas" ] && do_chroot /usr/bin/glib-compile-schemas /usr/share/glib-2.0/schemas
    do_chroot mkinitcpio -P

    unmount_cache
    yes | do_chroot pacman -Scc

    unmount_chroot

    echo "Creating tarball: $rootfs_tarball ..."
    pushd .
    cd $temp && bsdtar -czpf ../$rootfs_tarball .
    popd
    rm -rf $temp
}

make_image() {
    [ ! -e "$output_folder/$rootfs_tarball" ] && \
        error "Rootfs not found! (how did you get here?)"

    [ $NOCONFIRM -gt 0 ] && [ -f "$output_folder/archlinux-btrfs-$device-$ui-$date.img" ] && \
        rm "$output_folder/archlinux-btrfs-$device-$ui-$date.img"

    [ -f "$output_folder/archlinux-btrfs-$device-$ui-$date.img"  ] && {
        read -rp "Disk image already exist, delete it? (y/n) " yn
        case $yn in
            [Yy]*) rm "$output_folder/archlinux-btrfs-$device-$ui-$date.img" ;;
            [Nn]*) return ;;
            *) echo "Aborting." && exit 1 ;;
        esac; }

    disk_size="$(eval "echo \${size_ui_$ui}")"

    disk_output="$output_folder/archlinux-btrfs-$device-$ui-$date.img"

    echo "Generating a blank disk image ($disk_size)"
    fallocate -l $disk_size $disk_output

    boot_part_start=${boot_part_start:-1}
    boot_part_size=${boot_part_size:-128}

    echo "Boot partition start: ${boot_part_start}MB"
    echo "Boot partition size: ${boot_part_size}MB"

    parted -s $disk_output mktable gpt
    parted -s $disk_output mkpart boot fat32 ${boot_part_start}MB $[boot_part_start+boot_part_size]MB
    parted -s $disk_output set 1 esp on
    parted -s $disk_output mkpart primary btrfs $[boot_part_start+boot_part_size]MB '100%'

    echo "Attaching loop device"
    loop_device=$(losetup -f)
    losetup -P $loop_device "$output_folder/archlinux-btrfs-$device-$ui-$date.img"

    echo "Creating filesystems"
    mkfs.vfat ${loop_device}p1
    mkfs.btrfs ${loop_device}p2
    
    mkdir -p $temp
    echo "Mounting disk image"
    mount ${loop_device}p2 $temp
    
    #Making subvolumes
    btrfs subvolume create $temp/@
	btrfs subvolume create $temp/@/.snapshots
	mkdir $temp/@/.snapshots/1
	btrfs subvolume create $temp/@/.snapshots/1/snapshot
	mkdir $temp/@/boot
	btrfs subvolume create $temp/@/root
	btrfs subvolume create $temp/@/srv
	btrfs subvolume create $temp/@/tmp
	mkdir $temp/@/usr
	btrfs subvolume create $temp/@/usr/local
	mkdir $temp/@/var
	btrfs subvolume create $temp/@/var/cache
	btrfs subvolume create $temp/@/var/log
	btrfs subvolume create $temp/@/var/spool
	btrfs subvolume create $temp/@/var/tmp
	NOW=$(date +"%Y-%m-%d %H:%M:%S")
    echo "<?xml version=\"1.0\"?>" > info.xml
    echo "<snapshot>" >> info.xml
    echo "	<type>single</type>" >> info.xml
    echo "	<num>1</num>" >> info.xml
    echo "	<date>$NOW</date>" >> info.xml
    echo "	<description>First Root Filesystem</description>" >> info.xml
    echo "</snapshot>" >> info.xml
	cp info.xml $temp/@/.snapshots/1/info.xml
	sed -i "s|2022-01-01 00:00:00|${NOW}|" $temp/@/.snapshots/1/info.xml
  	btrfs subvolume set-default $(btrfs subvolume list $temp | grep "@/.snapshots/1/snapshot" | grep -oP '(?<=ID )[0-9]+') $temp
	btrfs quota enable $temp
	chattr +C $temp/@/var/cache
	chattr +C $temp/@/var/log
	chattr +C $temp/@/var/spool
	chattr +C $temp/@/var/tmp

    # unmount root to remount with default subvolume
    umount $temp
    rm -rf $temp
    mkdir -p $temp
    mount ${loop_device}p2 -o compress=zstd $temp
    # make directories home, .snapshots, var, tmp
	mkdir $temp/.snapshots
	mkdir $temp/root
	mkdir $temp/srv
	mkdir $temp/tmp
	mkdir -p $temp/usr/local
	mkdir -p $temp/var/cache
	mkdir $temp/var/log
	mkdir $temp/var/spool
	mkdir $temp/var/tmp
	mkdir $temp/boot
	mkdir $temp/home
    # mount subvolumes and partition
    mount ${loop_device}p2 -o noatime,compress=zstd,ssd,commit=120,subvol=@/.snapshots $temp/.snapshots
    mount ${loop_device}p2 -o noatime,compress=zstd,ssd,commit=120,subvol=@/root $temp/root
    mount ${loop_device}p2 -o noatime,compress=zstd,ssd,commit=120,subvol=@/srv $temp/srv
    mount ${loop_device}p2 -o noatime,compress=zstd,ssd,commit=120,subvol=@/tmp $temp/tmp
    mount ${loop_device}p2 -o noatime,compress=zstd,ssd,commit=120,subvol=@/usr/local $temp/usr/local
    mount ${loop_device}p2 -o noatime,ssd,commit=120,subvol=@/var/cache $temp/var/cache
    mount ${loop_device}p2 -o noatime,ssd,commit=120,subvol=@/var/log,nodatacow $temp/var/log
    mount ${loop_device}p2 -o noatime,ssd,commit=120,subvol=@/var/spool,nodatacow $temp/var/spool
    mount ${loop_device}p2 -o noatime,ssd,commit=120,subvol=@/var/tmp,nodatacow $temp/var/tmp
    mount ${loop_device}p1 $temp/boot
    
    echo "Extracting rootfs to image"
    bsdtar -xpf "$output_folder/$rootfs_tarball" -C "$temp" || true

    [ $NO_BOOTLOADER -lt 1 ] && {
        echo "Installing bootloader"
        case $platform in
            "rockchip")
                dd if=$temp/boot/idbloader.img of=$loop_device seek=64 conv=notrunc,fsync
                dd if=$temp/boot/u-boot.itb of=$loop_device seek=16384 conv=notrunc,fsync
                ;;
            *)
                dd if=$temp/boot/$bootloader of=$loop_device bs=128k seek=1
                ;;
        esac; }

    echo "Generating fstab"
    blkid
    genfstab -U $temp | grep UUID | grep -v "swap" | tee -a $temp/etc/fstab
    sed -i 's|,subvolid=259,subvol=/@/.snapshots/1/snapshot| |' $temp/etc/fstab
    if [ ! -f "$temp/boot/boot.txt" ]; then
	 cp devices/pinephone-pro/boot.txt $temp/boot/boot.txt
    else
    	sed -i 's/rw rootwait/rw rootfstype=btrfs rootwait/g' "$temp/boot/boot.txt"
    fi
    mkimage -A arm -O linux -T script -C none -n "U-Boot boot script" -d $temp/boot/boot.txt $temp/boot/boot.scr
    
    echo "Unmounting disk image"
    umount -R $temp
    rm -rf $temp
    losetup -d $loop_device
}

make_squashfs() {
    check_dependency mksquashfs

    [ $NOCONFIRM -gt 0 ] && [ -f "$output_folder/archlinux-btrfs-$device-$ui-$date.sqfs" ] && \
        rm "$output_folder/archlinux-btrfs-$device-$ui-$date.sqfs"

    [ -f "$output_folder/archlinux-btrfs-$device-$ui-$date.sqfs"  ] && {
        read -rp "Squashfs image already exist, delete it? (y/n) " yn
        case $yn in
            [Yy]*) rm "$output_folder/archlinux-btrfs-$device-$ui-$date.sqfs" ;;
            [Nn]*) return ;;
            *) echo "Aborting." && exit 1 ;;
        esac; }

    mkdir -p "$temp"
    bsdtar -xpf "$output_folder/$rootfs_tarball" -C "$temp"
    mksquashfs "$temp" "$output_folder/archlinux-btrfs-$device-$ui-$date.sqfs"
    rm -rf "$temp"
}

pre_check
parse_args $@
[[ "$arch" && "$device" && "$ui" ]] || usage
check_arch
parse_presets
init_rootfs
[ $OSK_SDL -gt 0 ] && make_squashfs || make_image
