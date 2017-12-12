#!/bin/sh -e

usage() {
	cat <<EOF
Usage:
$(basename "$0") "/path/to/diskimage.vhd"

Description:
Creates and exports a Parallels virtual machine (PVM) from a virtual disk image

EOF
}

cleanup() {
  if [ -n "$VM" ] && prlctl list --all | grep -q "$VM"; then
    prlctl unregister "$VM" > /dev/null
  fi
}

trap cleanup EXIT INT TERM

msg_status() {
	echo "\033[0;32m-- $1\033[0m"
}

msg_error() {
	echo "\033[0;31m-- $1\033[0m"
}

render_template() {
  eval "echo \"$(cat "$1")\""
}

if [ ! -f "$1" ]; then
  usage
	exit 1
fi

HARDDRIVE="$1"
VM="$(basename "${HARDDRIVE%.vhd}")"

OUTPUT="${HARDDRIVE%.vhd}.pvm"
ABS_PATH="$(realpath ${OUTPUT})"

ABS_PARENT="$(dirname ${ABS_PATH})"
CONVERTED_HDD="${ABS_PATH}/${VM}.hdd"
PARALLELS_HDD="${ABS_PATH}/Macintosh.hdd"

msg_status "Creating a new Parallels virtual machine: ${VM}"
prlctl create "$VM" --distribution macosx --no-hdd --dst="${ABS_PARENT}" > /dev/null

msg_status "Converting VHD to Parallels format"
prl_convert "$HARDDRIVE" --dst="${OUTPUT}" --allow-no-os
mv $CONVERTED_HDD $PARALLELS_HDD

msg_status "Compacting $PARALLELS_HDD"
prl_disk_tool compact --hdd "$PARALLELS_HDD"

msg_status "Adding SATA Controller and attaching Parallels HDD"
prlctl set "$VM" --device-add hdd --image "$PARALLELS_HDD" --iface sata --position 0 > /dev/null

msg_status "Setting up Parallels virtual machine"
prlctl set "$VM" --efi-boot "on" > /dev/null
prlctl set "$VM" --cpus "2" > /dev/null
prlctl set "$VM" --memsize "4096" > /dev/null

cleanup

msg_status "Done. Virtual machine export located at $OUTPUT."
