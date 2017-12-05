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
    prlctl unregister "$VM"
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

TIMESTAMP=$(date +"%s")
HARDDRIVE="$1"
VM="${HARDDRIVE%.vhd}"
TEMP_PVM=$(/usr/bin/mktemp -d /tmp/prepared_pvm.XXXX)
OUTPUT_PVM="${TEMP_PVM}/${VM}.pvm"
PARALLELS_HDD="${OUTPUT_PVM}/${HARDDRIVE%.vhd}.hdd"
PACKER_DIR="$(cd "$(dirname "$0")"; pwd)/../packer"

msg_status "Creating new Parallels virtual machine"
prlctl create "$VM" --distribution macosx --no-hdd --dst="${TEMP_PVM}"

msg_status "Converting $HARDDRIVE"
prl_convert "$HARDDRIVE" --allow-no-os --no-reconfig --reg --dst="${OUTPUT_PVM}"

msg_status "Adding SATA Controller and attaching hdd"
prlctl set "$VM" --device-add hdd --image "$PARALLELS_HDD" --iface sata --position 0

msg_status "Setting up Parallels virtual machine"
prlctl set "$VM" --efi-boot "on"
prlctl set "$VM" --cpus "2"
prlctl set "$VM" --memsize "4096"

msg_status "Optimizing virtual disk"
prl_disk_tool convert --hdd "$PARALLELS_HDD" --merge
prl_disk_tool compact --hdd "$PARALLELS_HDD" --exclude-pagefile

cleanup
