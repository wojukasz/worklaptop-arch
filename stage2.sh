#!/bin/bash
## stage 2 ##
pacman -S --noconfirm lvm2
pvcreate /dev/mapper/lvm
vgcreate volgroup /dev/mapper/lvm
lvcreate -L 20G volgroup -n lvolswap
lvcreate -l 50%FREE volgroup -n lvolroot
lvcreate -l 100%FREE volgroup -n lvolhome

mkswap -L swap /dev/mapper/volgroup-lvolswap
mkfs.ext4 -L root /dev/mapper/volgroup-lvolroot
mkfs.ext4 -L home /dev/mapper/volgroup-lvolhome

# mount partitions
mount /dev/mapper/volgroup-lvolroot /mnt
mkdir /mnt/{home,boot,esp}
mount /dev/mapper/volgroup-lvolhome /mnt/home
mount /dev/sda1 /mnt/esp
mount /dev/sda2 /mnt/boot

# install operating system
pacstrap /mnt base base-devel

genfstab -L /mnt > /mnt/etc/fstab

arch-chroot /mnt

# setup locale
sed -i 's/#en_GB/en_GB/g' /etc/locale.gen
sed -i 's/#en_US/en_US/g' /etc/locale.gen
locale-gen
localectl set-locale LANG=en_GB.UTF-8

# setup hostname
echo 'bashton-ajenkins' > /etc/hostname

# networking
pacman -S --noconfirm wpa_supplicant
## wired
export INTERFACE=`ip link | grep '2:' | cut -d' ' -f 2 | sed 's/://'` 
cat << EOF > /etc/systemd/network/${INTERFACE}.network
[Match]
Name=${INTERFACE}

[Network]
DHCP=ipv4

[DHCP]
RouteMetric=10
EOF

## wifi
export INTERFACE=`ip link | grep '3:' | cut -d' ' -f 2 | sed 's/://'` 
cat << EOF > /etc/systemd/network/${INTERFACE}.network
[Match]
Name=${INTERFACE}

[Network]
DHCP=ipv4

[DHCP]
RouteMetric=20
EOF

systemctl enable systemd-networkd
systemctl enable systemd-resolved
## ln -sf /run/systemd/resolve/resolve.conf /etc/resolv.conf ##! Troublesome, may need to run manually
# firewall
iptables -P INPUT DROP
iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m conntrack --ctstate INVALID -j DROP
iptables -A INPUT -p icmp --icmp-type 8 -m conntrack --ctstate NEW -j ACCEPT
iptables -A INPUT -p udp -m conntrack --ctstate NEW -j UDP
iptables -A INPUT -p tcp --syn -m conntrack --ctstate NEW -j TCP
iptables -A INPUT -p udp -j REJECT --reject-with icmp-port-unreachable
iptables -A INPUT -p tcp -j REJECT --reject-with tcp-reset
iptables -A INPUT -j REJECT --reject-with icmp-proto-unreachable
iptables-save > /etc/iptables/iptables.rules
systemctl enable iptables

# initramfs
sed -i 's/base udev autodetect modconf block filesystems keyboard fsck/base udev autodetect modconf block sd-encrypt filesystems keyboard fsck/g' 
mkinitcpio -p linux

# setup efi
pacman -S --noconfirm efibootmgr
mkdir -p /esp/EFI/arch/
cp /boot/vmlinuz-linux /esp/EFI/arch/
cp /boot/initramfs-linux.img /esp/EFI/arch/
efibootmgr -d /dev/sda -p 1 -c -L "Arch Linux" -l /EFI/arch/vmlinuz-linux -u
"root=/dev/mapper/volgroup-lvolroot resume=/dev/mapper/volgroup-lvolswap rw
initrd=/EFI/arch/initramfs-linux.img luks.name=lvm"

# gpu drivers
pacman -S --noconfirm mesa-libgl lib32-mesa-libgl
## actual machine
# pacman -S --noconfirm xf86-video-intel

## vm
pacman -S --noconfirm xf86-video-vmware xf86-input-vmmouse open-vm-tools

# gui apps
pacman -S --noconfirm gvim lightdm lightdm-gtk-greeter i3-wm i3status dmenu termite
chromium firefox virtualbox compton feh evince libreoffice inkscape gimp 

systemctl enable lightdm

# cli apps
pacman -S --noconfirm openssh vagrant gnu-netcat pkgfile bind-tools nmap nethogs sudo htop
tmux iotop git tig the_silver_searcher puppet dos2unix unix2dos ncdu ranger
pkgfile -u

# create user
useradd alan
mkdir /home/alan
chown -R alan:alan /home/alan
chmod 750 /home/alan

ex - /etc/sudoers << end-of-script
88
s///
wq
end-of-script

visudo -c

groupadd sudo
gpasswd -a alan sudo

# set passwords

# manual commands:
echo "run:"
echo -e "\tpasswd root"
echo -e "\tpasswd alan"
echo -e "\twpa_passphrase SSID PASSWORD >
/etc/wpa_supplicant/wpa_supplicant-${INTERFACE}.conf"
echo -e "\tsystemctl enable wpa_supplicant@${INTERFACE}.conf"
echo "After reboot:"
echo -e "\tln -sf /run/systemd/resolve/resolve.conf /etc/resolv.conf"