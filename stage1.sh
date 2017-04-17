#!/bin/bash
## stage 1 ##
# enable multilib
# ex - /etc/pacman.conf << end-of-script
# 93
# s/#//
# +
# s/#//
# wq
# end-of-script

get_partitions()
{
    local DISKNAME="$1"

    NUM_DISKS=$(lsblk -J | jq  '.[] | length')
    for CUR_DISK in $(seq 0 $((NUM_DISKS - 1)));
    do
        if [ $(lsblk -J | jq -r ".[][$CUR_DISK].name") == "$DISKNAME" ];
        then
            DISK_CHILDREN=$(lsblk -J | jq -r ".[][$CUR_DISK].children")
            break
        fi
    done
}

get_partition()
{
    local CHILD_NUM="$1"
    CHILD_NAME=$(echo "$DISK_CHILDREN" | jq -r ".[$CHILD_NUM].name")
}

# Update package lists
pacman -Sy --noconfirm jq

# *TODO* Disk detection
NUM_DISKS=$(lsblk -J | jq  '.[] | length')
DISKS=""
for CUR_DISK in $(seq 0 $((NUM_DISKS - 1)));
do
    if [ "$(lsblk -J | jq -r ".[][$CUR_DISK].type")" == "disk" ];
    then
        DISK_NAME=$(lsblk -J | jq -r ".[][$CUR_DISK].name")
        DISK_SIZE=$(lsblk -J | jq -r ".[][$CUR_DISK].size")
        DISKS="${DISKS}${DISK_NAME} ${DISK_SIZE} "
    fi
done

COMMAND="$(which dialog) --stdout --menu \"Choose the disk to install to (all data will be destroyed on the selected disk):\" 80 80 70 ${DISKS}"
echo "$COMMAND"
SEL_DISK=$(eval $COMMAND)
COMMAND="$(which dialog) --clear"
eval $COMMAND
COMMAND="$(which dialog) --yesno \"Are you sure you want to wipe ${SEL_DISK} and install Arch Linux?\" 5 80"
echo "$COMMAND"

if ! eval $COMMAND
then
    clear
    echo "OK not installing to ${SEL_DISK}. Exiting..."
    exit 1
else
    unset COMMAND
    unset DISK_NAME
    unset DISKS

    DISK="$SEL_DISK"
    DISK_PATH="/dev/$SEL_DISK"

    unset SEL_DISK
fi


# Setup EFI and boot
parted -s "$DISK_PATH" "mklabel gpt"
parted -s "$DISK_PATH" "mkpart esp fat32 1M 1G"
parted -s "$DISK_PATH" "mkpart boot ext4 1G 2G"
parted -s "$DISK_PATH" "mkpart lvm ext2 2G -1"
parted -s "$DISK_PATH" "name 1 esp"
parted -s "$DISK_PATH" "name 2 boot"
parted -s "$DISK_PATH" "name 3 lvm"
parted -s "$DISK_PATH" "toggle 1 boot"
parted -s "$DISK_PATH" "toggle 3 lvm"

get_partitions "$DISK"

echo "$CHILD_NAME"

get_partition 0
mkfs.vfat -F32 /dev/"$CHILD_NAME"
get_partition 1
mkfs.ext4 -F /dev/"$CHILD_NAME"

# ## end stage 1 ##


# # Install device-mapper cryptsetup

# echo "Run these to setup the encrypted partition:"
# echo -e "\tcryptsetup luksFormat /dev/sda3"
# echo -e "\tcryptsetup open --type luks /dev/sda3 lvm"
# echo -e "\tbash stage2.sh"

