#!/bin/sh -e
#
# Preparation script for an OS X automated installation for use with VeeWee/Packer/Vagrant
#
# What the script does, in more detail:
#
# 1. Mounts the InstallESD.dmg to locate the os's installer pkg (OSInstall.mpkg)
# 2. A 'veewee-config.pkg' installer package is built, which creates the
#    'vagrant' user, configures sshd and sudoers, and disables setup assistants.
# 3. A temporary sparse disk image is created.
# 4. The OSInstall and the veewee-config.pkg are installed into the disk image.
# 5. The image's raw device is converted into a virtual disk image.
#
# Thanks:
# Idea thanks to Per Olofsson's AutoDMG
# (https://github.com/MagerValp/AutoDMG/wiki/How-Does-AutoDMG-Work%3F)
#
# And Joseph Chilcote's vfuse
# (https://github.com/chilcote/vfuse)
#
# User creation via package install method also credited to Greg, and made easy with Per
# Olofsson's CreateUserPkg (http://magervalp.github.io/CreateUserPkg)
#
#

usage() {
	cat <<EOF
Usage:
$(basename "$0") [-upiD] "/path/to/Install OS X [Name].app" /path/to/output/directory

Description:
Creates and install OS X into a virtual disk image. The virtual disk image will be
named 'macOS_[osversion].vdi.'

Optional switches:
  -u <user>
    Sets the username of the root user, defaults to 'vagrant'.

  -p <password>
    Sets the password of the root user, defaults to 'vagrant'.

  -i <path to image>
    Sets the path of the avatar image for the root user, defaulting to the vagrant icon.

  -o <name of the disk image>
    Sets the name of the generated virtual disk image, defaulting to macOS_[osversion].vdi.

  -D <flag>
    Sets the specified flag. Valid flags are:
      DISABLE_REMOTE_MANAGEMENT
      DISABLE_SCREEN_SHARING
      DISABLE_SIP

EOF
}

cleanup() {
	if [ ! -z "$MNT_ESD" ]; then
		hdiutil detach -quiet -force "$MNT_ESD" || rm -rf "$MNT_ESD" || echo > /dev/null
	fi

	if [ ! -z "$MNT_SPARSEIMAGE" ]; then
		hdiutil detach -quiet -force "$MNT_SPARSEIMAGE" || rm -rf "$MNT_SPARSEIMAGE" || echo > /dev/null
	fi
  
	if [[ ! -z "$TEST" && -e "$SPARSEIMAGE" ]]; then
		rm -rf "$SPARSEIMAGE"
	fi
}

trap cleanup EXIT INT TERM

msg_status() {
	echo "\033[0;32m-- $1\033[0m"
}
msg_error() {
	echo "\033[0;31m-- $1\033[0m"
}
exit_with_error() {
	msg_error "$1"
	exit 1
}

SCRIPT_DIR="$(cd "$(dirname "$0")"; pwd)"
SUPPORT_DIR="$SCRIPT_DIR/support"

# Import shared code to generate first boot pkgs
FIRST_BOOT_PKG_SCRIPT="$SCRIPT_DIR/create_firstboot_pkg.sh"
[ -f "$FIRST_BOOT_PKG_SCRIPT" ] && . "$FIRST_BOOT_PKG_SCRIPT"

# Parse the optional command line switches
USER="vagrant"
PASSWORD="vagrant"
IMAGE_PATH="$SUPPORT_DIR/vagrant.jpg"
DISK_SIZE_GB=32

# Flags
DISABLE_REMOTE_MANAGEMENT=0
DISABLE_SCREEN_SHARING=0
DISABLE_SIP=0
DISABLE_APFS=1

if [ $# -eq 0 ]; then
	usage
	exit 1
fi

while getopts u:p:i:o:D: OPT; do
  case "$OPT" in
    u)
      USER="$OPTARG"
      ;;
    p)
      PASSWORD="$OPTARG"
      ;;
    i)
      IMAGE_PATH="$OPTARG"
      ;;
    o)
      OUTPUT_DMG="$OPTARG"
      ;;
    D)
      if [ x${!OPTARG} = x0 ]; then
        eval $OPTARG=1
      elif [ x${!OPTARG} != x1 ]; then
        msg_error "Unknown flag: ${OPTARG}"
        usage
        exit 1
      fi
      ;;
    \?)
      usage
      exit 1
      ;;
  esac
done

# Remove the switches we parsed above.
shift $(expr $OPTIND - 1)

if [ $(id -u) -ne 0 ]; then
	exit_with_error "This script must be run as root, as it saves a disk image with ownerships enabled."
fi

if [ -z "$(which VBoxManage)" ]; then
	exit_with_error "VBoxManage, the command-line interface to VirtualBox, not found"
fi

INSTALLER_PATH="$1"
if [ ! -e "$INSTALLER_PATH" ]; then
	exit_with_error "Input installer image $INSTALLER_PATH could not be found! Exiting.."
fi

OUT_DIR="$2"
if [ -z "$OUT_DIR" ]; then
	exit_with_error "Currently an explicit output directory is required as the second argument."
elif [ ! -d "$OUT_DIR" ]; then
	msg_status "Destination dir $OUT_DIR doesn't exist, creating.."
	mkdir -p "$OUT_DIR"
fi

ESD="$INSTALLER_PATH/Contents/SharedSupport/InstallESD.dmg"
if [ ! -e "$ESD" ]; then
	exit_with_error "Can't locate an InstallESD.dmg in this source location $ESD!"
fi

SYSVER_PLIST_PATH="$INSTALLER_PATH/Contents/SharedSupport/InstallInfo.plist"
if [ ! -e "$SYSVER_PLIST_PATH" ]; then
	exit_with_error "Can't locate InstallInfo.plist in $INSTALLER_PATH/Contents/SharedSupport/!"
fi

DMG_OS_VERS=$(/usr/libexec/PlistBuddy -c 'Print :System\ Image\ Info:version' "$SYSVER_PLIST_PATH")
DMG_OS_VERS_MAJOR=$(echo $DMG_OS_VERS | awk -F "." '{print $1}')
DMG_OS_VERS_MINOR=$(echo $DMG_OS_VERS | awk -F "." '{print $2}')
DMG_OS_VERS_PATCH=$(echo $DMG_OS_VERS | awk -F "." '{print $3}')
msg_status "macOS version detected: $DMG_OS_VERS_MAJOR.$DMG_OS_VERS_MINOR.$DMG_OS_VERS_PATCH"

HOST_OS_VERS=$(sw_vers -productVersion)
HOST_OS_VERS_MAJOR=$(echo $HOST_OS_VERS | awk -F "." '{print $1}')
HOST_OS_VERS_MINOR=$(echo $HOST_OS_VERS | awk -F "." '{print $2}')
HOST_OS_VERS_PATCH=$(echo $HOST_OS_VERS | awk -F "." '{print $3}')
msg_status "host macOS version detected: $HOST_OS_VERS_MAJOR.$HOST_OS_VERS_MINOR.$HOST_OS_VERS_PATCH"

if [ "$DMG_OS_VERS_MAJOR" != "$DMG_OS_VERS_MAJOR" ] || [ "$DMG_OS_VERS_MINOR" != "$HOST_OS_VERS_MINOR" ]; then
	exit_with_error "Unfortunately prepare_vdi can only generate images of same version as the host"
fi

if [ -z "$OUTPUT_DMG" ]; then
  OUTPUT_DMG="$OUT_DIR/macOS_${DMG_OS_VERS}.vdi"
elif [ -e "$OUTPUT_DMG" ]; then
  exit_with_error "Output file $OUTPUT_DMG already exists! We're not going to overwrite it, exiting.."
fi

if [ $DMG_OS_VERS_MINOR -ge 13 ]; then
  if [ $DISABLE_APFS = 1 ]; then
	  FSTYPE="HFS+J"
  else
    FSTYPE="APFS"
  fi
	OSPACKAGE="$INSTALLER_PATH/Contents/SharedSupport/InstallInfo.plist"
else
	FSTYPE="HFS+J"
	MNT_ESD=$(/usr/bin/mktemp -d /tmp/veewee-osx-esd.XXXX)
	
	msg_status "Attaching input OS X installer image"
	hdiutil attach "$ESD" -mountpoint "$MNT_ESD" -nobrowse -owners on
	if [ $? -ne 0 ]; then
		[ ! -e "$ESD" ] && exit_with_error "Could not find $ESD in $(pwd)"
		exit_with_error "Could not mount $ESD on $MNT_ESD"
	fi

	OSPACKAGE="$MNT_ESD/Packages/OSInstall.mpkg"
fi

# Build our post-installation pkg that will create a user and enable ssh
msg_status "Making firstboot installer pkg.."
create_firstboot_pkg
if [ -z "$BUILT_PKG" ] || [ ! -e "$BUILT_PKG" ]; then
  exit_with_error "Failed building the firstboot installer pkg, exiting.."
fi

MNT_SPARSEIMAGE=$(/usr/bin/mktemp -d /tmp/prepare_vdi_mnt_sparseimage.XXXX)
SPARSEIMAGE="$(/usr/bin/mktemp /tmp/prepare_vdi.XXXX).sparseimage"

msg_status "Creating DMG of "${DISK_SIZE_GB}g" with $FSTYPE located at $SPARSEIMAGE.."
if ! hdiutil create -size "${DISK_SIZE_GB}g" -type SPARSE -fs "$FSTYPE" -volname "Macintosh HD" -uid 0 -gid 80 -mode 1775 "$SPARSEIMAGE"; then
  exit_with_error "Failed creating the disk image"
fi

msg_status "Mounting empty read-write DMG located at $SPARSEIMAGE.."
hdiutil attach "$SPARSEIMAGE" -mountpoint "$MNT_SPARSEIMAGE" -nobrowse -owners on

msg_status "Installing macOS"
installer -verboseR -dumplog -pkg "$OSPACKAGE" -target "$MNT_SPARSEIMAGE"
if [ $? -ne 0 ]; then
	exit_with_error "Failed installing macOS"
fi

msg_status "Installing firstboot installer pkg"
installer -pkg "$BUILT_PKG" -target "$MNT_SPARSEIMAGE"
if [ $? -ne 0 ]; then
	exit_with_error "Failed installing the firstboot installer pkg"
fi

# Unmount and remount to make sure that is synchronized.
msg_status "Remounting $SPARSEIMAGE"
hdiutil detach -quiet -force "$MNT_SPARSEIMAGE" || echo > /dev/null
MOUNTOUTPUT=$(hdiutil attach "$SPARSEIMAGE" -mountpoint "$MNT_SPARSEIMAGE" -nobrowse -owners on)
DISK_DEV=$(grep GUID_partition_scheme <<< "$MOUNTOUTPUT" | cut -f1 | tr -d '[:space:]')
DISK_SIZE_BYTES=$(($DISK_SIZE_GB * 1024 * 1024 * 1024))

if [ ! -e "$DISK_DEV" ]; then
	exit_with_error "Failed to find the device file of the image"
fi

msg_status "Exporting from $DISK_DEV to $OUTPUT_DMG"
VBoxManage convertfromraw stdin "$OUTPUT_DMG" "$DISK_SIZE_BYTES" < "$DISK_DEV"

msg_status "Checksumming output image.."
MD5=$(md5 -q "$OUTPUT_DMG" | tee "$OUTPUT_DMG.md5")
msg_status "MD5: $MD5"

if [ -n "$SUDO_UID" ] && [ -n "$SUDO_GID" ]; then
	msg_status "Fixing permissions.."
	chown -R $SUDO_UID:$SUDO_GID \
		"$OUT_DIR"
fi

msg_status "Done. Built image is located at $OUTPUT_DMG. Add this iso and its checksum to your template."

cleanup
exit 0
