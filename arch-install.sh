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

set -euo pipefail
IFS=$'\n\t'

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
chroot_command() # {{{
{
    COMMAND="arch-chroot /mnt $1"
    echo "Running: $COMMAND"
    eval $COMMAND
} # }}}
install_deps() # {{{
{
    pacman -Sy --noconfirm jq lvm2 btrfs-progs
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
    if ! SEL_DISK=$(eval $COMMAND)
    then
        clear
        echo "OK aborting installation as no disk selected."
        exit
    fi
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
    dialog --clear
} # }}}
get_required_hostname() # {{{
{
    local COMMAND="dialog --stdout --inputbox \"Please enter the hostname you want to use for the system.\" 8 50"
    REQUIRED_HOSTNAME="$(eval $COMMAND)"
    dialog --clear
} # }}}
get_facter_facts() # {{{
{
    local COMMAND="dialog --stdout --inputbox \"Please enter any custom facter facts you want to use for the system separated by commas e.g. (owner=alan,envtype=prod).\" 8 50"
    FACTS="$(eval $COMMAND)"
    clear
} # }}}
wipe_disk() # {{{
{
    echo "Wiping disk"
    wipefs -a "$DISK_PATH"
}
# }}}
partition_disk() # {{{
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
    mkfs.btrfs -L root /dev/mapper/volgroup-lvolroot
    mkfs.btrfs -L home /dev/mapper/volgroup-lvolhome
} # }}}
mount_partitions() # {{{
{
    echo "Mounting partitions"
    mount /dev/mapper/volgroup-lvolroot /mnt
    swapon /dev/mapper/volgroup-lvolswap

    mkdir /mnt/home
    mount /dev/mapper/volgroup-lvolhome /mnt/home

    get_partition 1
    mkdir /mnt/boot
    mount "/dev/$PART_NAME" /mnt/boot

    get_partition 0
    mkdir /mnt/boot/esp
    mount "/dev/$PART_NAME" /mnt/boot/esp
} # }}}
install_base_system() # {{{
{
    echo "Installing system"
    pacstrap /mnt base base-devel curl efibootmgr btrfs-progs git puppet wget ruby-shadow
    genfstab -L /mnt > /mnt/etc/fstab
} # }}}
setup_locales() # {{{
{
    echo "Setting locale"
    chroot_command "sed -i 's/#en_GB/en_GB/g' /etc/locale.gen"
    chroot_command "sed -i 's/#en_US/en_US/g' /etc/locale.gen"
    chroot_command "locale-gen"
    echo 'LANG=en_GB.UTF-8' > /mnt/etc/locale.conf
} # }}}
setup_hostname() { # {{{
    echo "Setting hostname to $REQUIRED_HOSTNAME"
    #chroot_command "bash echo 'test' > /etc/hostname"
    echo "$REQUIRED_HOSTNAME" > /mnt/etc/hostname
    chroot_command "hostname \"$REQUIRED_HOSTNAME\""
} # }}}
create_initcpio() # {{{
{
    echo "Creating initcpio"
    chroot_command "sed -i 's/base udev autodetect modconf block filesystems keyboard fsck/base udev encrypt autodetect modconf block lvm2 resume filesystems keyboard fsck/g' /etc/mkinitcpio.conf"
    chroot_command "mkinitcpio -p linux"
} # }}}
setup_efi() # {{{
{
    echo "Setup EFI"
    mkdir -p /mnt/boot/esp/EFI/arch
    cp /mnt/boot/vmlinuz-linux /mnt/boot/esp/EFI/arch
    cp /mnt/boot/initramfs-linux.img /mnt/boot/esp/EFI/arch

    cat <<'EOF' >> /mnt/etc/systemd/system/efistub-update.path
    [Unit]
    Description=Copy EFISTUB Kernel to EFI System Partition

    [Path]
    PathChanged=/boot/initramfs-linux-fallback.img

    [Install]
    WantedBy=multi-user.target
    WantedBy=system-update.target
EOF

    cat <<'EOF' >> /mnt/etc/systemd/system/efistub-update.service
    [Unit]
    Description=Copy EFISTUB Kernel to EFI System Partition

    [Service]
    Type=oneshot
    ExecStart=/usr/bin/cp -f /boot/vmlinuz-linux /boot/esp/EFI/arch/vmlinuz-linux
    ExecStart=/usr/bin/cp -f /boot/initramfs-linux.img /boot/esp/EFI/arch/initramfs-linux.img
    ExecStart=/usr/bin/cp -f /boot/initramfs-linux-fallback.img /boot/esp/EFI/arch/initramfs-linux-fallback.img
EOF

    chroot_command "systemctl enable efistub-update.path"
} # }}}
setup_systemd_boot() # {{{
{
    echo "Setting up systemd-boot"
    get_partition 2
    local LUKSUUID=$(blkid /dev/$PART_NAME | awk '{ print $2; }' | sed 's/"//g')

    chroot_command "bootctl --path=/boot/esp install"

    echo "label Arch Linux" >> /mnt/boot/esp/loader/entries/arch.conf
    echo "linux /EFI/arch/vmlinuz-linux" >> /mnt/boot/esp/loader/entries/arch.conf
    echo "initrd /EFI/arch/initramfs-linux.img" >> /mnt/boot/esp/loader/entries/arch.conf
    echo "options cryptdevice=${LUKSUUID}:lvm root=/dev/mapper/volgroup-lvolroot resume=/dev/mapper/volgroup-lvolswap rw initrd=/EFI/arch/initramfs-linux.img" >> /mnt/boot/esp/loader/entries/arch.conf
} # }}}
install_r10k() # {{{
{
    chroot_command "gem install r10k"
} # }}}
get_puppet_code() # {{{
{
    chroot_command "git clone --depth=1 https://github.com/alanjjenkins/puppet.git /puppet"
} #}}}
get_puppet_modules() # {{{
{
    cat <<'END' | arch-chroot /mnt su -l root
    cd /puppet
    /root/.gem/ruby/2.4.0/bin/r10k puppetfile install
END
} # }}}
create_custom_facts() # {{{
{
    mkdir -p /mnt/etc/facter/facts.d
    echo "$FACTS" | tr ',' '\n' > /mnt/etc/facter/facts.d/facts.txt
} # }}}
perform_puppet_run() # {{{
{
    cat <<'END' | arch-chroot /mnt su -l root
    cd /puppet/
    ./apply.sh
END
} # }}}

install_deps
select_install_disk
get_encryption_password
get_required_hostname
get_facter_facts
wipe_disk
partition_disk
format_partitions
setup_luks
mount_partitions
install_base_system
setup_locales
setup_hostname
create_initcpio
setup_efi
setup_systemd_boot
install_r10k
get_puppet_code
create_custom_facts
get_puppet_modules
perform_puppet_run
