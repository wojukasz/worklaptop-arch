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
pacman -Sy

# Setup EFI and boot 
parted /dev/sda
mklabel gpt
mkpart esp fat32 1M 1G
mkpart boot ext4 1G 2G
mkpart lvm ext2 2G -1
name 1 esp
name 2 boot
name 3 lvm
toggle 1 boot
toggle 3 lvm
quit

mkfs.vfat -F32 /dev/sda1
mkfs.ext4 /dev/sda2

## end stage 1 ##


# Install device-mapper cryptsetup

echo "Run these to setup the encrypted partition:"
echo -e "\tcryptsetup luksFormat /dev/sda3"
echo -e "\tcryptsetup open --type luks /dev/sda3 lvm"

