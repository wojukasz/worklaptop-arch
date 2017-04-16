#!/bin/bash
## stage 1 ##
# enable multilib
ex - /etc/pacman.conf << end-of-script
93
s/#//
+
s/#//
wq
end-of-script

# Update package lists
pacman -Sy --noconfirm jq

# *TODO* Disk detection
NUM_DISKS=$(lsblk -J | jq  '.[] | length')
for CUR_DISK in $(seq 0 $((NUM_DISKS - 1)));
do
    echo "${CUR_DISK}"
done

# Setup EFI and boot
# parted -s /dev/sda "mklabel gpt"
# parted -s /dev/sda "mkpart esp fat32 1M 1G"
# parted -s /dev/sda "mkpart boot ext4 1G 2G"
# parted -s /dev/sda "mkpart lvm ext2 2G -1"
# parted -s /dev/sda "name 1 esp"
# parted -s /dev/sda "name 2 boot"
# parted -s /dev/sda "name 3 lvm"
# parted -s /dev/sda "toggle 1 boot"
# parted -s /dev/sda "toggle 3 lvm"

# mkfs.vfat -F32 /dev/sda1
# mkfs.ext4 -F /dev/sda2

# ## end stage 1 ##


# # Install device-mapper cryptsetup

# echo "Run these to setup the encrypted partition:"
# echo -e "\tcryptsetup luksFormat /dev/sda3"
# echo -e "\tcryptsetup open --type luks /dev/sda3 lvm"
# echo -e "\tbash stage2.sh"

