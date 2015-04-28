#!/bin/sh

# Install the specified version of Puppet and tools
#
# PUPPET_VERSION, FACTER_VERSION and HIERA_VERSION are set to either
# 'latest' or specific versions via the Packer template
#
# install function mostly borrowed dmg function from hashicorp/puppet-bootstrap,
# except we just take an already-downloaded dmg

install_dmg() {
    local dmg_path="$1"

    echo "Installing: ${dmg_path}"

    # Mount the DMG
    echo "-- Mounting DMG..."
    tmpmount=$(/usr/bin/mktemp -d /tmp/puppet-dmg.XXXX)
    hdiutil attach "${dmg_path}" -mountpoint "${tmpmount}"

    echo "-- Installing pkg..."
    pkg_path=$(find "${tmpmount}" -name '*.pkg' -mindepth 1 -maxdepth 1)
    installer -pkg "${pkg_path}" -tgt /

    # Unmount
    echo "-- Unmounting and ejecting DMG..."
    hdiutil eject "${tmpmount}"
}

get_dmg() {
    local name="$1"
    local version="$2"
    curl -s -O "https://downloads.puppetlabs.com/mac/${name}-${version}.dmg"
    echo "${name}-${version}.dmg"
}


# Retrieve the installer DMGs
PUPPET_DMG=$(get_dmg puppet "${PUPPET_VERSION}")
FACTER_DMG=$(get_dmg facter "${FACTER_VERSION}")
HIERA_DMG=$(get_dmg hiera "${HIERA_VERSION}")

# Install them
install_dmg "${PUPPET_DMG}"
install_dmg "${FACTER_DMG}"
install_dmg "${HIERA_DMG}"

# Hide all users from the loginwindow with uid below 500, which will include the puppet user
defaults write /Library/Preferences/com.apple.loginwindow Hide500Users -bool YES

# Clean up
rm -rf "${PUPPET_DMG}" "${FACTER_DMG}" "${HIERA_DMG}"
