#!/bin/sh -e
#
# Preparation script for an OS X automated installation for use with VeeWee/Packer/Vagrant
# 
# What the script does, in more detail:
# 
# 1. Mounts the InstallESD.dmg using a shadow file, so the original DMG is left
#    unchanged.
# 2. Modifies the BaseSystem.dmg within in order to add an additional 'rc.cdrom.local'
#    file in /etc, which is a supported local configuration sourced in at boot time
#    by the installer environment. This file contains instructions to erase and format
#    'disk0', presumably the hard disk attached to the VM.
# 3. A 'veewee-config.pkg' installer package is built, which is added to the OS X
#    install by way of the OSInstall.collection file. This package creates the
#    'vagrant' user, configures sshd and sudoers, and disables setup assistants.
# 4. veewee-config.pkg and the various support utilities are copied, and the disk
#    image is saved to the output path.
#
# Thanks:
# Idea and much of the implementation thanks to Pepijn Bruienne, who's also provided
# some process notes here: https://gist.github.com/4542016. The sample minstallconfig.xml,
# use of OSInstall.collection and readme documentation provided with Greg Neagle's
# createOSXInstallPkg tool also proved very helpful. (http://code.google.com/p/munki/wiki/InstallingOSX)
#
# User creation via package install method also credited to Greg, and made easy with Per
# Olofsson's CreateUserPkg (http://magervalp.github.io/CreateUserPkg)
#
# Antony Blakey for updates to support OS X 10.11:
# https://github.com/timsutton/osx-vm-templates/issues/40

usage() {
	cat <<EOF
Usage:
$(basename "$0") [-upiD] "/path/to/InstallESD.dmg" /path/to/output/directory
$(basename "$0") [-upiD] "/path/to/Install OS X [Name].app" /path/to/output/directory

Description:
Converts an OS X installer to a new image that contains components
used to perform an automated installation. The new image will be named
'OSX_InstallESD_[osversion].dmg.'

Optional switches:
  -u <user>
    Sets the username of the root user, defaults to 'vagrant'.

  -p <password>
    Sets the password of the root user, defaults to 'vagrant'.

  -i <path to image>
    Sets the path of the avatar image for the root user, defaulting to the vagrant icon.

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
    rm -rf "$MNT_ESD" "$MNT_BASE_SYSTEM" "$BASE_SYSTEM_DMG_RW" "$SHADOW_FILE"
}

trap cleanup EXIT INT TERM


msg_status() {
	echo "\033[0;32m-- $1\033[0m"
}
msg_error() {
	echo "\033[0;31m-- $1\033[0m"
}

if [ $# -eq 0 ]; then
	usage
	exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")"; pwd)"
SUPPORT_DIR="$SCRIPT_DIR/support"

# Import shared code to generate first boot pkgs
FIRST_BOOT_PKG_SCRIPT="$SCRIPT_DIR/create_firstboot_pkg.sh"
[ -f "$FIRST_BOOT_PKG_SCRIPT" ] && . "$FIRST_BOOT_PKG_SCRIPT"

# Parse the optional command line switches
USER="vagrant"
PASSWORD="vagrant"
IMAGE_PATH="$SUPPORT_DIR/vagrant.jpg"

# Flags
DISABLE_REMOTE_MANAGEMENT=0
DISABLE_SCREEN_SHARING=0
DISABLE_SIP=0

while getopts u:p:i:D: OPT; do
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

if [ -e "$ESD.shadow" ]; then
	msg_status "Removing old shadow file.."
	rm "$ESD.shadow"
fi

MNT_ESD=$(/usr/bin/mktemp -d /tmp/veewee-osx-esd.XXXX)
SHADOW_FILE=$(/usr/bin/mktemp /tmp/veewee-osx-shadow.XXXX)
rm "$SHADOW_FILE"
msg_status "Attaching input OS X installer image with shadow file.."
hdiutil attach "$ESD" -mountpoint "$MNT_ESD" -shadow "$SHADOW_FILE" -nobrowse -owners on 
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

OUTPUT_DMG="$OUT_DIR/OSX_InstallESD_${DMG_OS_VERS}_${DMG_OS_BUILD}.dmg"
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

# We'd previously mounted this to check versions
hdiutil detach "$MNT_BASE_SYSTEM"

BASE_SYSTEM_DMG_RW="$(/usr/bin/mktemp /tmp/veewee-osx-basesystem-rw.XXXX).dmg"

msg_status "Creating empty read-write DMG located at $BASE_SYSTEM_DMG_RW.."
hdiutil create -o "$BASE_SYSTEM_DMG_RW" -size 10g -layout SPUD -fs HFS+J
hdiutil attach "$BASE_SYSTEM_DMG_RW" -mountpoint "$MNT_BASE_SYSTEM" -nobrowse -owners on

msg_status "Restoring ('asr restore') the BaseSystem to the read-write DMG.."
# This asr restore was needed as of 10.11 DP7 and up. See
# https://github.com/timsutton/osx-vm-templates/issues/40
#
# Note that when the restore completes, the volume is automatically re-mounted
# and not with the '-nobrowse' option. It's an annoyance we could possibly fix
# in the future..
asr restore --source "$BASE_SYSTEM_DMG" --target "$MNT_BASE_SYSTEM" --noprompt --noverify --erase
rm -r "$MNT_BASE_SYSTEM"

if [ $DMG_OS_VERS_MAJOR -ge 9 ]; then
    MNT_BASE_SYSTEM="/Volumes/OS X Base System"
    BASESYSTEM_OUTPUT_IMAGE="$OUTPUT_DMG"
    PACKAGES_DIR="$MNT_BASE_SYSTEM/System/Installation/Packages"

    rm "$PACKAGES_DIR"
	msg_status "Moving 'Packages' directory from the ESD to BaseSystem.."
	mv -v "$MNT_ESD/Packages" "$MNT_BASE_SYSTEM/System/Installation/"

	# This isn't strictly required for Mavericks, but Yosemite will consider the
	# installer corrupt if this isn't included, because it cannot verify BaseSystem's
	# consistency and perform a recovery partition verification
	msg_status "Copying in original BaseSystem dmg and chunklist.."
	cp "$MNT_ESD/BaseSystem.dmg" "$MNT_BASE_SYSTEM/"
	cp "$MNT_ESD/BaseSystem.chunklist" "$MNT_BASE_SYSTEM/"
else
    MNT_BASE_SYSTEM="/Volumes/Mac OS X Base System"
    BASESYSTEM_OUTPUT_IMAGE="$MNT_ESD/BaseSystem.dmg"
    rm "$BASESYSTEM_OUTPUT_IMAGE"
	PACKAGES_DIR="$MNT_ESD/Packages"
fi

msg_status "Adding automated components.."
CDROM_LOCAL="$MNT_BASE_SYSTEM/private/etc/rc.cdrom.local"
cat > $CDROM_LOCAL << EOF
diskutil eraseDisk jhfs+ "Macintosh HD" GPTFormat disk0
if [ "\$?" == "1" ]; then
    diskutil eraseDisk jhfs+ "Macintosh HD" GPTFormat disk1
fi
EOF
chmod a+x "$CDROM_LOCAL"
mkdir "$PACKAGES_DIR/Extras"
cp "$SUPPORT_DIR/minstallconfig.xml" "$PACKAGES_DIR/Extras/"
cp "$SUPPORT_DIR/OSInstall.collection" "$PACKAGES_DIR/"
cp "$BUILT_PKG" "$PACKAGES_DIR/"
rm -rf "$SUPPORT_DIR/tmp"

msg_status "Unmounting BaseSystem.."
hdiutil detach "$MNT_BASE_SYSTEM"

if [ $DMG_OS_VERS_MAJOR -lt 9 ]; then
	msg_status "Pre-Mavericks we save back the modified BaseSystem to the root of the ESD."
	hdiutil convert -format UDZO -o "$MNT_ESD/BaseSystem.dmg" "$BASE_SYSTEM_DMG_RW"
fi

msg_status "Unmounting ESD.."
hdiutil detach "$MNT_ESD"

if [ $DMG_OS_VERS_MAJOR -ge 9 ]; then
	msg_status "On Mavericks and later, the entire modified BaseSystem is our output dmg."
	hdiutil convert -format UDZO -o "$OUTPUT_DMG" "$BASE_SYSTEM_DMG_RW"
else
	msg_status "Pre-Mavericks we're modifying the original ESD file."
	hdiutil convert -format UDZO -o "$OUTPUT_DMG" -shadow "$SHADOW_FILE" "$ESD"
fi
rm -rf "$MNT_ESD" "$SHADOW_FILE"

if [ -n "$SUDO_UID" ] && [ -n "$SUDO_GID" ]; then
	msg_status "Fixing permissions.."
	chown -R $SUDO_UID:$SUDO_GID \
		"$OUT_DIR"
fi

if [ -n "$DEFAULT_ISO_DIR" ]; then
	DEFINITION_FILE="$DEFINITION_DIR/definition.rb"
	msg_status "Setting ISO file in definition $DEFINITION_FILE.."
	ISO_FILE=$(basename "$OUTPUT_DMG")
	# Explicitly use -e in order to use double quotes around sed command
	sed -i -e "s/%OSX_ISO%/${ISO_FILE}/" "$DEFINITION_FILE"
fi

msg_status "Checksumming output image.."
MD5=$(md5 -q "$OUTPUT_DMG")
msg_status "MD5: $MD5"

msg_status "Done. Built image is located at $OUTPUT_DMG. Add this iso and its checksum to your template."
