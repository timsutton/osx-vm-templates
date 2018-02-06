#!/bin/bash -e

usage() {
    cat <<EOF
Usage:
$(basename "$0") "/path/to/diskimage.vhd"

Description:
Creates and exports a Parallels virtual machine (PVM) from a virtual disk image

EOF
}

GREEN='\033[0;32m'
RED='\033[0;31m'
NONE='\033[0m'

cleanup() {
    if [ -n "$VM" ] && prlctl list --all | grep -q "$VM"; then
        prlctl unregister "$VM" || echo > /dev/null
    fi
}

trap cleanup EXIT INT TERM

msg_status() {
    echo -e "$GREEN-- $1"
    echo -ne "$NONE"
}

msg_error() {
    echo -e "$RED-- $1"
    echo -ne "$NONE"
}

render_template() {
    eval "echo \"$(cat "$1")\""
}

realpath_macos()
{
    # Source:
    # https://stackoverflow.com/questions/1055671/how-can-i-get-the-behavior-of-gnus-readlink-f-on-a-mac

    TARGET_FILE=$1

    cd "$(dirname "$TARGET_FILE")" || exit 1
    TARGET_FILE="$(basename "$TARGET_FILE")"

    # Iterate down a (possible) chain of symlinks
    while [ -L "$TARGET_FILE" ]; do
        TARGET_FILE=$(readlink -f "$TARGET_FILE")
        cd "$(dirname "$TARGET_FILE")" || exit 1
        TARGET_FILE="$(basename "$TARGET_FILE")"
    done

    # Compute the canonicalized name by finding the physical path
    # for the directory we're in and appending the target file.
    PHYS_DIR="$(pwd -P)"
    RESULT=$PHYS_DIR/$TARGET_FILE
    echo "$RESULT"
}

if [ ! -f "$1" ]; then
    usage
    exit 1
fi

HARDDRIVE="$1"
VM="$(basename "${HARDDRIVE%.vhd}")"

OUTPUT="${HARDDRIVE%.vhd}.pvm"
ABS_PATH="$(realpath_macos "$OUTPUT")"

ABS_PARENT="$(dirname "$ABS_PATH")"
CONVERTED_HDD="${ABS_PATH}/${VM}.hdd"
PARALLELS_HDD="${ABS_PATH}/Macintosh.hdd"

msg_status "Creating a new Parallels virtual machine: $VM"
prlctl create "$VM" --distribution macosx --no-hdd --dst="$ABS_PARENT"

msg_status "Converting VHD to Parallels format"
prl_convert "$HARDDRIVE" --dst="$OUTPUT" --allow-no-os
mv "$CONVERTED_HDD" "$PARALLELS_HDD"

msg_status "Adding SATA Controller and attaching Parallels HDD"
prlctl set "$VM" --device-add hdd --image "$PARALLELS_HDD" --iface sata --position 0

msg_status "Setting up Parallels virtual machine"
prlctl set "$VM" --efi-boot "on"
prlctl set "$VM" --cpus "2"
prlctl set "$VM" --memsize "4096"
prlctl set "$VM" --memquota "512:2048"
prlctl set "$VM" --3d-accelerate "highest"
prlctl set "$VM" --high-resolution "off"
prlctl set "$VM" --auto-share-camera "off"
prlctl set "$VM" --auto-share-bluetooth "off"
prlctl set "$VM" --on-window-close "keep-running"
prlctl set "$VM" --shf-host "off"

cleanup

msg_status "Done. Virtual machine export located at $OUTPUT."
