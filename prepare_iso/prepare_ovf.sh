#!/bin/sh -e

usage() {
	cat <<EOF
Usage:
$(basename "$0") "/path/to/diskimage.vdi"

Description:
Creates and exports a machine image (OVF) from virtual disk image

EOF
}

cleanup() {
  if [ -n "$VM" ] && VBoxManage list vms | grep -q "$VM"; then
    # Detach the diskimage before deleting the virtual image
    VBoxManage storageattach "$VM" --storagectl "SATA Controller" --port 0 --device 0 --type hdd --medium none
    VBoxManage unregistervm "$VM" --delete || echo > /dev/null
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
VM="macOS_${TIMESTAMP}"
HARDDRIVE="$1"
OUTPUT="${HARDDRIVE%.vdi}.ovf"

msg_status "Creating new virtual machine"
VBoxManage createvm --name "$VM" --ostype "MacOS_64" --register

msg_status "Adding SATA Controller"
VBoxManage storagectl "$VM" --name "SATA Controller" --add sata --controller IntelAHCI

msg_status "Attaching vdi"
VBoxManage storageattach "$VM" --storagectl "SATA Controller" --port 0 --device 0 --type hdd --medium "$HARDDRIVE"

msg_status "Setting up virtual machine"
VBoxManage modifyvm "$VM" --audiocontroller "hda"
VBoxManage modifyvm "$VM" --chipset "ich9"
VBoxManage modifyvm "$VM" --firmware "efi"
VBoxManage modifyvm "$VM" --cpus "2"
VBoxManage modifyvm "$VM" --hpet "on"
VBoxManage modifyvm "$VM" --keyboard "usb"
VBoxManage modifyvm "$VM" --memory "4096"
VBoxManage modifyvm "$VM" --mouse "usbtablet"
VBoxManage modifyvm "$VM" --vram "128"

msg_status "Exporting the virtual machine"
VBoxManage export "$VM" --output "$OUTPUT"

msg_status "Done. Virtual machine export located at $OUTPUT."
