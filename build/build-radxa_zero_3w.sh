#!/bin/bash
# script running in target debian arm64 OS
set -e

source /opt/build/common.sh

# Remove unnecessary package for xface base image [ need remove more unnecessary package ]
if dpkg -l | grep -q xface4;
then
    apt purge -y xfce4* lightdm* liblightdm-gobject-1-0 libupower-glib3 libxklavier16 upower chromium-x11 xserver-xorg-core xserver-xorg-legacy rockchip-chromium-x11-utils firefox-esr x11-apps
    # fix radxa-sddm-theme uninstall issue
    mkdir -p /usr/share/sddm/themes/breeze
    touch /usr/share/sddm/themes/breeze/Main.qml
    # fix radxa-system-config-rockchip uninstall issue
    [ -f /etc/modprobe.d/panfrost.conf.bak ] && rm /etc/modprobe.d/panfrost.conf.bak
    apt autoremove -y --purge
fi
dpkg -l | grep -q "linux-image-5.10.160-26-rk356x" && apt purge -y linux-image-5.10.160-26-rk356x linux-headers-5.10.160-26-rk356x

# Update bullseye-backports source URL
sed -i 's|https://deb.debian.org/debian|http://archive.debian.org/debian|g' /etc/apt/sources.list.d/50-bullseye-backports.list

board_upgrade
install_dependencies
install_locales
install_wifi_drivers

apt -y install firmware-atheros # required by install_intree_kmods
install_intree_kmods

install_wfb_ng
install_pixelpilot
install_msposd
install_wfb_osd
install_rubyfpv
install_sbc_gs_cc
install_alink
install_ttyd
install_useful_packages
install_misc_tools
configure_system

# disable services
sed -i '/disable_service systemd-networkd/a disable_service dnsmasq' /config/before.txt
update-rc.d -f tftpd-hpa remove

# enable services
sed -i "s/disable_service systemd-networkd/# disable_service systemd-networkd/" /config/before.txt
sed -i "s/disable_service ssh/# disable_service ssh/" /config/before.txt
sed -i "s/disable_service nmbd/# disable_service nmbd/" /config/before.txt
sed -i "s/disable_service smbd/# disable_service smbd/" /config/before.txt

# sync mount /config
sed -i 's/\(UUID=\\S*\s*\/config\s*vfat\s*defaults,x-systemd.automount\)/\1,sync/' /etc/fstab

# disable auto extend root partition and rootfs
apt purge -y cloud-initramfs-growroot
sed -i "s/resize_root/# resize_root/" /config/before.txt
