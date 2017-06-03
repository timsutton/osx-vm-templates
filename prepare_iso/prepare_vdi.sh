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

. $(dirname "$0")/create_firstboot_pkg.sh

usage() {
	cat <<EOF
Usage:
$(basename "$0") [-upiD] "/path/to/InstallESD.dmg" /path/to/output/directory
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
	hdiutil detach -quiet -force "$MNT_ESD" || echo > /dev/null
	hdiutil detach -quiet -force "$MNT_BASE_SYSTEM" || echo > /dev/null

	if [ ! -z "$TEST" ]; then
		cp "$BASE_SYSTEM_DMG_RW_SPARSE" "$BASE_SYSTEM_DMG_RW_SPARSE.back"
	fi
	rm -rf "$MNT_ESD" "$MNT_BASE_SYSTEM" "$BASE_SYSTEM_DMG_RW" "${BASE_SYSTEM_DMG_RW%%.dmg}" "$BASE_SYSTEM_DMG_RW_SPARSE"
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

if [ $# -eq 0 ]; then
	usage
	exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")"; pwd)"
SUPPORT_DIR="$SCRIPT_DIR/support"

# Parse the optional command line switches
USER="vagrant"
PASSWORD="vagrant"
IMAGE_PATH="$SUPPORT_DIR/vagrant.jpg"

# Flags
DISABLE_REMOTE_MANAGEMENT=0
DISABLE_SCREEN_SHARING=0
DISABLE_SIP=0

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
	msg_error "This script must be run as root, as it saves a disk image with ownerships enabled."
	exit 1
fi

ESD="$1"
if [ ! -e "$ESD" ]; then
	msg_error "Input installer image $ESD could not be found! Exiting.."
	exit 1
fi

if [ -d "$ESD" ]; then
	# we might be an install .app
	if [ -e "$ESD/Contents/SharedSupport/InstallESD.dmg" ]; then
		ESD="$ESD/Contents/SharedSupport/InstallESD.dmg"
	else
		msg_error "Can't locate an InstallESD.dmg in this source location $ESD!"
	fi
fi

VEEWEE_DIR="$(cd "$SCRIPT_DIR/../../../"; pwd)"
VEEWEE_UID=$(/usr/bin/stat -f %u "$VEEWEE_DIR")
VEEWEE_GID=$(/usr/bin/stat -f %g "$VEEWEE_DIR")
DEFINITION_DIR="$(cd "$SCRIPT_DIR/.."; pwd)"

if [ "$2" = "" ]; then
    msg_error "Currently an explicit output directory is required as the second argument."
	exit 1
	# The rest is left over from the old prepare_veewee_iso.sh script. Not sure if we
    # should leave in this functionality to automatically locate the veewee directory.
	DEFAULT_ISO_DIR=1
	OLDPWD=$(pwd)
	cd "$SCRIPT_DIR"
	# default to the veewee/iso directory
	if [ ! -d "../../../iso" ]; then
		mkdir "../../../iso"
		chown $VEEWEE_UID:$VEEWEE_GID "../../../iso"
	fi
	OUT_DIR="$(cd "$SCRIPT_DIR"; cd ../../../iso; pwd)"
	cd "$OLDPWD" # Rest of script depends on being in the working directory if we were passed relative paths
else
	OUT_DIR="$2"
fi

if [ ! -d "$OUT_DIR" ]; then
	msg_status "Destination dir $OUT_DIR doesn't exist, creating.."
	mkdir -p "$OUT_DIR"
fi

MNT_ESD=$(/usr/bin/mktemp -d /tmp/veewee-osx-esd.XXXX)
msg_status "Attaching input OS X installer image"
hdiutil attach "$ESD" -mountpoint "$MNT_ESD" -nobrowse -owners on
if [ $? -ne 0 ]; then
	[ ! -e "$ESD" ] && msg_error "Could not find $ESD in $(pwd)"
	msg_error "Could not mount $ESD on $MNT_ESD"
	exit 1
fi

msg_status "Mounting BaseSystem.."
BASE_SYSTEM_DMG="$MNT_ESD/BaseSystem.dmg"
MNT_BASE_SYSTEM=$(/usr/bin/mktemp -d /tmp/veewee-osx-basesystem.XXXX)
[ ! -e "$BASE_SYSTEM_DMG" ] && msg_error "Could not find BaseSystem.dmg in $MNT_ESD"
hdiutil attach "$BASE_SYSTEM_DMG" -mountpoint "$MNT_BASE_SYSTEM" -nobrowse -owners on
if [ $? -ne 0 ]; then
	msg_error "Could not mount $BASE_SYSTEM_DMG on $MNT_BASE_SYSTEM"
	exit 1
fi
SYSVER_PLIST_PATH="$MNT_BASE_SYSTEM/System/Library/CoreServices/SystemVersion.plist"

DMG_OS_VERS=$(/usr/libexec/PlistBuddy -c 'Print :ProductVersion' "$SYSVER_PLIST_PATH")
DMG_OS_VERS_MAJOR=$(echo $DMG_OS_VERS | awk -F "." '{print $2}')
DMG_OS_VERS_MINOR=$(echo $DMG_OS_VERS | awk -F "." '{print $3}')
DMG_OS_BUILD=$(/usr/libexec/PlistBuddy -c 'Print :ProductBuildVersion' "$SYSVER_PLIST_PATH")
msg_status "OS X version detected: 10.$DMG_OS_VERS_MAJOR.$DMG_OS_VERS_MINOR, build $DMG_OS_BUILD"

msg_status "Unmounting BaseSystem.."
hdiutil detach "$MNT_BASE_SYSTEM"

if [ -z "$OUTPUT_DMG" ]; then
  OUTPUT_DMG="$OUT_DIR/macOS_${DMG_OS_VERS}_${DMG_OS_BUILD}.vdi"
fi

if [ -e "$OUTPUT_DMG" ]; then
	msg_error "Output file $OUTPUT_DMG already exists! We're not going to overwrite it, exiting.."
	hdiutil detach -force "$MNT_ESD"
	exit 1
fi

# Build our post-installation pkg that will create a user and enable ssh
msg_status "Making firstboot installer pkg.."
create_firstboot_pkg
if [ -z "$BUILT_PKG" ] || [ ! -e "$BUILT_PKG" ]; then
  msg_error "Failed building the firstboot installer pkg, exiting.."
  exit 1
fi

BASE_SYSTEM_DMG_RW="$(/usr/bin/mktemp /tmp/veewee-osx-basesystem-rw.XXXX).dmg"
DISK_SIZE_GB=32
DISK_SIZE_BYTES=$(($DISK_SIZE_GB * 1024 * 1024 * 1024))
msg_status "Creating empty read-write DMG located at $BASE_SYSTEM_DMG_RW.."
hdiutil create -size "${DISK_SIZE_GB}g" -type SPARSE -fs HFS+J -volname "Macintosh HD" -uid 0 -gid 80 -mode 1775 "$BASE_SYSTEM_DMG_RW"

BASE_SYSTEM_DMG_RW_SPARSE=$BASE_SYSTEM_DMG_RW.sparseimage
msg_status "Mounting empty read-write DMG located at $BASE_SYSTEM_DMG_RW.."
hdiutil attach "$BASE_SYSTEM_DMG_RW_SPARSE" -mountpoint "$MNT_BASE_SYSTEM" -nobrowse -owners on

msg_status "Installing macOS"
installer -verboseR -dumplog -pkg "$MNT_ESD/Packages/OSInstall.mpkg" -target "$MNT_BASE_SYSTEM"
if [ $? -ne 0 ]; then
	msg_error "Failed installing macOS"
	exit 1
fi

msg_status "Installing firstboot installer pkg"
installer -pkg "$BUILT_PKG" -target "$MNT_BASE_SYSTEM"
if [ $? -ne 0 ]; then
	msg_error "Failed installing the firstboot installer pkg"
	exit 1
fi

# Unmount and remount to make sure that is synchronized.
hdiutil detach -quiet -force "$MNT_BASE_SYSTEM" || echo > /dev/null
MOUNTOUTPUT=$(hdiutil attach "$BASE_SYSTEM_DMG_RW_SPARSE" -mountpoint "$MNT_BASE_SYSTEM" -nobrowse -owners on)
DISK_DEV=$(grep GUID_partition_scheme <<< "$MOUNTOUTPUT" | cut -f1 | tr -d '[:space:]')

msg_status "Exporting $OUTPUT_DMG"
cat "$DISK_DEV" | VBoxManage convertfromraw stdin "$OUTPUT_DMG" "$DISK_SIZE_BYTES"

if [ -n "$SUDO_UID" ] && [ -n "$SUDO_GID" ]; then
	msg_status "Fixing permissions.."
	chown -R $SUDO_UID:$SUDO_GID \
		"$OUT_DIR"
fi

msg_status "Checksumming output image.."
MD5=$(md5 -q "$OUTPUT_DMG")
msg_status "MD5: $MD5"

msg_status "Done. Built image is located at $OUTPUT_DMG. Add this iso and its checksum to your template."
