#!/bin/bash
# script running in target debian arm64 OS

set -e

source /opt/build/common.sh

[ -d /config ] || mkdir -p /config

board_upgrade

# Add radxa rk3566 repo
keyring="$(mktemp)"
version="$(curl -L https://github.com/radxa-pkg/radxa-archive-keyring/releases/latest/download/VERSION)"
curl -L --output "$keyring" "https://github.com/radxa-pkg/radxa-archive-keyring/releases/latest/download/radxa-archive-keyring_${version}_all.deb"
dpkg -i "$keyring"
rm -f "$keyring"
tee /etc/apt/sources.list.d/70-radxa-rk3566.list <<< "deb [signed-by=/usr/share/keyrings/radxa-archive-keyring.gpg] https://radxa-repo.github.io/rk3566-bookworm/ rk3566-bookworm main"
tee /etc/apt/sources.list.d/80-radxa.list <<< "deb [signed-by=/usr/share/keyrings/radxa-archive-keyring.gpg] https://radxa-repo.github.io/bookworm/ bookworm main"

install_dependencies

apt install -y linux-headers-vendor-rk35xx

install_locales
install_wfb_ng
install_wifi_drivers
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
update-rc.d -f tftpd-hpa remove

# # enable services
systemctl enable systemd-networkd
systemctl enable ssh
