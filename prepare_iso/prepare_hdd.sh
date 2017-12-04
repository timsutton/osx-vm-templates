#!/bin/sh -e

usage() {
	cat <<EOF
Usage:
$(basename "$0") "/path/to/diskimage.vhd"

Description:
Creates and exports a Parallels machine image (PVM) from virtual disk image

EOF
}

# cleanup() {
#   if [ -n "$VM" ] && prlctl list --all | grep -q "$VM"; then
#     prlctl stop "$VM"
#     prlctl delete "$VM"
#   fi
# }

# trap cleanup EXIT INT TERM

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
VM="macOS_${TIMESTAMP}"
HARDDRIVE="$1"
OUTPUT_PVM="${HOME}/Parallels/${VM}.pvm"

msg_status "Creating new Parallels virtual machine"
prlctl create "$VM" --distribution macosx --no-hdd

msg_status "Converting $HARDDRIVE to $OUTPUT_PVM"
prl_convert "$HARDDRIVE" --allow-no-os --no-reconfig --reg --dst="${OUTPUT_PVM}"

msg_status "Adding SATA Controller and attaching hdd"
prlctl set "$VM" --device-add hdd --image "${OUTPUT_PVM}/${HARDDRIVE%.vhd}.hdd" --iface sata --position 0

msg_status "Setting up Parallels virtual machine"
prlctl set "$VM" --efi-boot "on"
prlctl set "$VM" --cpus "2"
prlctl set "$VM" --memsize "4096"
