#!/usr/bin/env bash
# https://github.com/timsutton/osx-vm-templates/blob/master/scripts/parallels.sh

set -eo pipefail

TOOLS_PATH="${HOME}/prl-tools-mac.iso"
HDIUTIL='/usr/bin/hdiutil'
INSTALLER='/usr/sbin/installer'

if [ ! -e "${TOOLS_PATH}" ]; then
    echo "Couldn't locate uploaded tools iso at ${TOOLS_PATH}!"
    exit 1
fi

TMPMOUNT="$(/usr/bin/mktemp -d /tmp/parallels-tools.XXXX)"
${HDIUTIL} attach "${TOOLS_PATH}" -mountpoint "${TMPMOUNT}"

INSTALLER_PKG="$TMPMOUNT/Install.app/Contents/Resources/Install.mpkg"
if [ ! -e "${INSTALLER_PKG}" ]; then
    echo "Couldn't locate Parallels Tools installer pkg at ${INSTALLER_PKG}!"
    exit 1
fi

echo "Installing Parallels Tools..."
${INSTALLER} -pkg "${INSTALLER_PKG}" -target /

echo "Unmounting Parallels Tools disk image..."
${HDIUTIL} detach -debug -verbose "${TMPMOUNT}"
rm -rf "${TMPMOUNT}"
rm -f "${TOOLS_PATH}"
