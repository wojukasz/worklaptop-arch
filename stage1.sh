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

get_partitions() # {{{
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
} #}}}
get_partition() # {{{
{
    local CHILD_NUM="$1"
    PART_NAME=$(echo "$DISK_CHILDREN" | jq -r ".[$CHILD_NUM].name")
} # }}}
install_deps() # {{{
{
    pacman -Sy --noconfirm jq lvm2 f2fs-tools
} # }}}
select_install_disk() # {{{
{
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
        dialog --clear
    fi
} # }}}
get_encryption_password() # {{{
{
    local COMMAND="dialog --stdout --passwordbox \"Please enter the password to use for disk encryption\" 8 50"
    ENCRPYTION_PASS="$(eval $COMMAND)"
    clear
} # }}}
partiton_disk() # {{{
{
    echo "Partitioning disk: $DISK_PATH"
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
} # }}}
format_partitions() # {{{
{
    echo "Formatting partitions"
    get_partitions "$DISK"
    get_partition 0
    mkfs.vfat -F32 /dev/"$PART_NAME"
    get_partition 1
    mkfs.ext4 -F /dev/"$PART_NAME"
} # }}}
setup_luks() # {{{
{
    echo "Setting up encrypted partitions"
    get_partition 2
    echo -n "$ENCRPYTION_PASS" | cryptsetup luksFormat /dev/"$PART_NAME" -
    echo -n "$ENCRPYTION_PASS" | cryptsetup open --type luks /dev/"$PART_NAME" lvm -
    pvcreate /dev/mapper/lvm
    vgcreate volgroup /dev/mapper/lvm
    lvcreate -L 20G volgroup -n lvolswap
    lvcreate -l 50%FREE volgroup -n lvolroot
    lvcreate -l 100%FREE volgroup -n lvolhome
    mkswap -L swap /dev/mapper/volgroup-lvolswap
    mkfs.f2fs -l root /dev/mapper/volgroup-lvolroot
    mkfs.f2fs -l home /dev/mapper/volgroup-lvolhome
} # }}}
mount_partitions() # {{{
{
    mount /dev/mapper/volgroup-lvolroot /mnt
    mkdir /mnt/{home,boot,esp}
    mount /dev/mapper/volgroup-lvolhome /mnt/home

    get_partition 0
    mount "/dev/$PART_NAME" /mnt/esp
    get_partition 1
    mount "/dev/$PART_NAME" /mnt/boot
} # }}}
install_base_system() # {{{
{
    pacstrap /mnt base base-devel
    genfstab -L /mnt > /mnt/etc/fstab
} # }}}

install_deps
select_install_disk
get_encryption_password
partiton_disk
format_partitions
setup_luks
mount_partitions
install_base_system

