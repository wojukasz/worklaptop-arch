#!/bin/bash
## stage 2 ##
pacman -S --noconfirm lvm2 f2fs-tools
pvcreate /dev/mapper/lvm
vgcreate volgroup /dev/mapper/lvm
lvcreate -L 20G volgroup -n lvolswap
lvcreate -l 50%FREE volgroup -n lvolroot
lvcreate -l 100%FREE volgroup -n lvolhome

mkswap -L swap /dev/mapper/volgroup-lvolswap
mkfs.f2fs -L root /dev/mapper/volgroup-lvolroot
mkfs.f2fs -L home /dev/mapper/volgroup-lvolhome

# mount partitions
mount /dev/mapper/volgroup-lvolroot /mnt
mkdir /mnt/{home,boot,esp}
mount /dev/mapper/volgroup-lvolhome /mnt/home
mount /dev/sda1 /mnt/esp
mount /dev/sda2 /mnt/boot

# install operating system
pacstrap /mnt base base-devel

genfstab -L /mnt > /mnt/etc/fstab

cp stage3.sh /mnt/

echo "Run:"
echo -e "\tbash stage3.sh"

arch-chroot /mnt


