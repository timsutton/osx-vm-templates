#!/bin/sh -e

usage() {
	cat <<EOF
Usage:
$(basename "$0") "/path/to/diskimage.vdi"

Description:
Converts virtual disk image to Parallels hard disk (HDD) and creates Parallels virtual machine from that image

EOF
}

cleanup() {
  if [ -n "$VM" ] && prlctl list | grep -q "$VM"; then
    prlctl unregister "$VM"
  fi
}

trap cleanup EXIT INT TERM

msg_status() {
	echo "\033[0;32m-- $1\033[0m"
}

if [ ! -f "$1" ]; then
  usage
	exit 1
fi

TIMESTAMP=$(date +"%s")
VM="macOS_${TIMESTAMP}"
HARDDRIVE="$1"

msg_status "Creating new virtual machine"
prlctl create "$VM" --ostype macos --no-hdd --dst="$(dirname "$HARDDRIVE")"

msg_status "Converting VDI to HDD"
prl_convert "$HARDDRIVE" --allow-no-os --no-reconfig --dst="$(dirname "$HARDDRIVE")/$VM.pvm"
prl_disk_tool convert --merge --hdd "$(dirname "$HARDDRIVE")/$VM.pvm/$(basename "${HARDDRIVE%.vdi}.hdd")"

msg_status "Attaching HDD to Parallels VM"
prlctl set "$VM" --device-add hdd --image "$(dirname "$HARDDRIVE")/$VM.pvm/$(basename "${HARDDRIVE%.vdi}.hdd")"

msg_status "Unregistring the virtual machine"
prlctl unregister "$VM"

msg_status "Done. Virtual machine export located at $(dirname "$HARDDRIVE")/$VM.pvm."
