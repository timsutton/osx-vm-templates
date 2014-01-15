#!/bin/sh
#
# Preparation script for an OS X automated installation for use with VeeWee/Packer/Vagrant
# 
# What the script does, in more detail:
# 
# 1. Mounts the InstallESD.dmg using a shadow file, so the original DMG is left
#    unchanged.
# 2. Depending on the version of OS X being built, the AutoPartition.app from
#    System Image Utility is copied to the ISO's 'Packages/Extra' directory.
#    A 10.7 image requires a download of Apple's Server Admin Tools package in
#    order to extract this utility, so this is done if needed. AutoPartition.app
#    makes use of PartitionInfo.plist, which is also copied over.
#    NOTE: This step should actually be replaced with a simple .local script that
#          performs the equivalent partitioning task using diskutil. The OS X
#          install environment supports a custom .local script which is run before
#          the rest of the installation logic proceeds. Removing the dependency on
#          AutoPartition.app would remove a lot of code to maintain.
# 3. minstallconfig.xml and PartitionInfo.plist are also copied, which are looked
#    for by the installer environment's rc.* files that first load with the system.
#    This allows us to never actually modify the BaseSystem.dmg and only drop in
#    these extra files.
# 4. A 'veewee-config.pkg' installer package is built, which is added to the OS X
#    install by way of the OSInstall.collection file. This package creates the
#    'vagrant' user, configures sshd and sudoers, and disables setup assistants.
# 5. veewee-config.pkg and the various support utilities are copied, and the disk
#    image is saved to the output path.
#
# Thanks:
# Idea and much of the implementation thanks to Pepijn Bruienne, who's also provided
# some process notes here: https://gist.github.com/4542016. The sample minstallconfig.xml,
# use of OSInstall.collection and readme documentation provided with Greg Neagle's
# createOSXInstallPkg tool also proved very helpful. (http://code.google.com/p/munki/wiki/InstallingOSX)
# User creation via package install method also credited to Greg, and made easy with Per
# Olofsson's CreateUserPkg (http://magervalp.github.io/CreateUserPkg)

usage() {
	cat <<EOF
Usage:
$(basename "$0") "/path/to/InstallESD.dmg" /path/to/output/directory
$(basename "$0") "/path/to/Install OS X [Mountain] Lion.app" /path/to/output/directory

Description:
Converts a 10.7/10.8/10.9 installer image to a new image that contains components
used to perform an automated installation. The new image will be named
'OSX_InstallESD_[osversion].dmg.'

EOF
}

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

SCRIPT_DIR="$(cd $(dirname "$0"); pwd)"
VEEWEE_DIR="$(cd "$SCRIPT_DIR/../../../"; pwd)"
VEEWEE_UID=$(stat -f %u "$VEEWEE_DIR")
VEEWEE_GID=$(stat -f %g "$VEEWEE_DIR")
DEFINITION_DIR="$(cd $SCRIPT_DIR/..; pwd)"

if [ "$2" == "" ]; then
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
	OUT_DIR="$(cd $SCRIPT_DIR; cd ../../../iso; pwd)"
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

# Check if we might be 10.9
if [ ! -d "$MNT_ESD/System" ] && [ -d "$MNT_ESD/Packages" ]; then
	msg_status "This looks like a 10.9 installer. Mounting BaseSystem.."

	BASE_SYSTEM_DMG="$MNT_ESD/BaseSystem.dmg"
	MNT_BASE_SYSTEM=$(/usr/bin/mktemp -d /tmp/veewee-osx-basesystem.XXXX)
	[ ! -e "$BASE_SYSTEM_DMG" ] && msg_error "Could not find BaseSystem.dmg in $MNT_ESD"
	hdiutil attach "$BASE_SYSTEM_DMG" -mountpoint "$MNT_BASE_SYSTEM" -nobrowse -owners on
	if [ $? -ne 0 ]; then
		msg_error "Could not mount $BASE_SYSTEM_DMG on $MNT_BASE_SYSTEM"
		exit 1
	fi
	SYSVER_PLIST_PATH="$MNT_BASE_SYSTEM/System/Library/CoreServices/SystemVersion.plist"
else
	SYSVER_PLIST_PATH="$MNT_ESD/System/Library/CoreServices/SystemVersion.plist"
fi

DMG_OS_VERS=$(/usr/libexec/PlistBuddy -c 'Print :ProductVersion' "$SYSVER_PLIST_PATH")
DMG_OS_VERS_MAJOR=$(echo $DMG_OS_VERS | awk -F "." '{print $2}')
DMG_OS_VERS_MINOR=$(echo $DMG_OS_VERS | awk -F "." '{print $3}')
DMG_OS_BUILD=$(/usr/libexec/PlistBuddy -c 'Print :ProductBuildVersion' "$SYSVER_PLIST_PATH")
msg_status "OS X version detected: 10.$DMG_OS_VERS_MAJOR.$DMG_OS_VERS_MINOR, build $DMG_OS_BUILD"

OUTPUT_DMG="$OUT_DIR/OSX_InstallESD_${DMG_OS_VERS}_${DMG_OS_BUILD}.dmg"
if [ -e "$OUTPUT_DMG" ]; then
	msg_error "Output file $OUTPUT_DMG already exists! We're not going to overwrite it, exiting.."
	hdiutil detach "$MNT_ESD"
	exit 1
fi

SUPPORT_DIR="$SCRIPT_DIR/support"

# We need to copy over the AutoPartition.app from System Image Utility, and it needs to match the version of the Guest OS
# 10.7 systems need to get Server Admin Tools here:
# http://support.apple.com/kb/DL1596
# direct link: http://support.apple.com/downloads/DL1596/en_US/ServerAdminTools.dmg
OSX_VERS=$(sw_vers -productVersion | awk -F "." '{print $2}')
# AutoPartition.app lives in different places depending on 10.7/10.8 and 10.9
if [ $OSX_VERS -le 8 ]; then
	AUTOPART_APP_IN_SIU="System Image Utility.app/Contents/Library/Automator/Create Image.action/Contents/Resources/AutoPartition.app"
elif [ $OSX_VERS -eq 9 ]; then
	AUTOPART_APP_IN_SIU="System Image Utility.app/Contents/Frameworks/SIUFoundation.framework/Versions/A/XPCServices/com.apple.SIUAgent.xpc/Contents/Resources/AutoPartition.app"
fi

if [ $DMG_OS_VERS_MAJOR -ge 8 ]; then
	if [ $OSX_VERS -eq 7 ]; then
		msg_status "To build OS X 10.$DMG_OS_VERS_MAJOR on Lion, we need to extract AutoPartition.app from the installer ESD."
		SIU_TMPDIR=$(/usr/bin/mktemp -d /tmp/siu-108.XXXX)
		msg_status "Expanding flat package.."
		pkgutil --verbose --expand "$MNT_ESD/Packages/Essentials.pkg" "$SIU_TMPDIR/expanded"

		msg_status "Generating BOM.."
		mkbom -s -i "$SUPPORT_DIR/10_${DMG_OS_VERS_MAJOR}_AP_bomlist" "$SUPPORT_DIR/BOM"

		msg_status "Extracting AutoPartition.app using ditto.."
		ditto --bom "$SUPPORT_DIR/BOM" -x "$SIU_TMPDIR/expanded/Payload" "$SIU_TMPDIR/ditto"
		if [ ! -d "$SUPPORT_DIR/AutoPartition-10.${DMG_OS_VERS_MAJOR}" ]; then
			mkdir "$SUPPORT_DIR/AutoPartition-10.${DMG_OS_VERS_MAJOR}"
		fi

		msg_status "Copying out AutoPartition.app.."
		cp -R "$SIU_TMPDIR/ditto/System/Library/CoreServices/$AUTOPART_APP_IN_SIU" "$SUPPORT_DIR/AutoPartition-10.${DMG_OS_VERS_MAJOR}/"
		msg_status "Removing temporary extracted files.."
		rm -rf "$SIU_TMPDIR"
		rm "$SUPPORT_DIR/BOM"

		AUTOPART_TOOL="$SUPPORT_DIR/AutoPartition-10.${DMG_OS_VERS_MAJOR}/AutoPartition.app"

	elif [ $OSX_VERS -ge 8 ]; then
		AUTOPART_TOOL="/System/Library/CoreServices/$AUTOPART_APP_IN_SIU"
		if [ ! -e "$AUTOPART_TOOL" ]; then
			msg_error "We're on 10.${OSX_VERS}, and should have System Image Utility available at $AUTOPART_TOOL, but it's not available for some reason."
			exit 1
		fi
		cp -R "$AUTOPART_TOOL" "$SUPPORT_DIR/AutoPartition-10.${DMG_OS_VERS_MAJOR}/"
	fi

# on Lion, we first check if Server Admin Tools are already installed..
elif [ $DMG_OS_VERS_MAJOR -eq 7 ]; then
	msg_status "Building OS X 10.${DMG_OS_VERS_MAJOR}, so trying to locate System Image Utility from Server Admin Tools.."
	AUTOPART_TOOL="/Applications/Server/$AUTOPART_APP_IN_SIU"
	# TODO: Sanity-check that this is actually the right version of SIU
	if [ ! -d "$AUTOPART_TOOL" ]; then
		# then we check if _we_ installed them in support/AutoPartition-10.7
		AUTOPART_TOOL="$SUPPORT_DIR/AutoPartition-10.${DMG_OS_VERS_MAJOR}/AutoPartition.app"
		if [ ! -d "$AUTOPART_TOOL" ]; then
			# Lion SAT download
			SAT_URL=http://support.apple.com/downloads/DL1596/en_US/ServerAdminTools.dmg
			
			msg_status "It doesn't seem to be installed and VeeWee hasn't yet cached it in the support dir.."
			msg_status "Attempting download of the Server Admin Tools.."
			SAT_TMPDIR=$(/usr/bin/mktemp -d /tmp/server-admin-tools.XXXX)
			
			curl -L "$SAT_URL" -o "$SAT_TMPDIR/sat.dmg"
			msg_status "Attaching Server Admin Tools.."
			hdiutil attach "$SAT_TMPDIR/sat.dmg" -mountpoint "$SAT_TMPDIR/mnt"

			msg_status "Expanding package.."
			pkgutil --expand "$SAT_TMPDIR/mnt/ServerAdminTools.pkg" "$SAT_TMPDIR/expanded"
			hdiutil detach "$SAT_TMPDIR/mnt"
			mkdir "$SAT_TMPDIR/cpio-extract"

			msg_status "Extracting payload.."
			tar -xz -C "$SAT_TMPDIR/cpio-extract" -f "$SAT_TMPDIR/expanded/ServerAdminTools.pkg/Payload"
			if [ ! -d "$SUPPORT_DIR/AutoPartition-10.${DMG_OS_VERS_MAJOR}" ]; then
				mkdir "$SUPPORT_DIR/AutoPartition-10.${DMG_OS_VERS_MAJOR}"
			fi

			msg_status "Copying out AutoPartition.app"
			cp -R "$SAT_TMPDIR/cpio-extract/Applications/Server/$AUTOPART_APP_IN_SIU" "$SUPPORT_DIR/AutoPartition-10.${DMG_OS_VERS_MAJOR}/"

			rm -rf "$SAT_TMPDIR"
			# AUTOPART_TOOL="$SUPPORT_DIR/AutoPartition-${DMG_OS_VERS_MAJOR}/AutoPartition.app"
		else msg_status "Found AutoPartition.app at $AUTOPART_TOOL.."
		fi
	fi
elif [ $DMG_OS_VERS_MAJOR -lt 7 ]; then
	msg_error "This script currently doesn't support building guest OS X versions prior to 10.7."
	exit 1
fi

# Build our post-installation pkg that will create a vagrant user and enable ssh
msg_status "Making firstboot installer pkg.."

# payload items
mkdir -p "$SUPPORT_DIR/pkgroot/private/var/db/dslocal/nodes/Default/users"
mkdir -p "$SUPPORT_DIR/pkgroot/private/var/db/shadow/hash"
cp "$SUPPORT_DIR/vagrant.plist" "$SUPPORT_DIR/pkgroot/private/var/db/dslocal/nodes/Default/users/vagrant.plist"
VAGRANT_GUID=$(/usr/libexec/PlistBuddy -c 'Print :generateduid:0' "$SUPPORT_DIR/vagrant.plist")
cp "$SUPPORT_DIR/shadowhash" "$SUPPORT_DIR/pkgroot/private/var/db/shadow/hash/$VAGRANT_GUID"

# postinstall script
mkdir -p "$SUPPORT_DIR/tmp/Scripts"
cp "$SUPPORT_DIR/pkg-postinstall" "$SUPPORT_DIR/tmp/Scripts/postinstall"
# executability should be copied over, warn if we had to chmod again
if [ ! -x "$SUPPORT_DIR/tmp/Scripts/postinstall" ]; then
	msg_status "'postinstall' script was for some reason not executable. Setting it again now, but it should have been already set when copying the definition."
	chmod a+x "$SUPPORT_DIR/tmp/Scripts/postinstall"
fi

# build it
BUILT_PKG="$SUPPORT_DIR/tmp/veewee-config.pkg"
pkgbuild --quiet \
	--root "$SUPPORT_DIR/pkgroot" \
	--scripts "$SUPPORT_DIR/tmp/Scripts" \
	--identifier com.vagrantup.veewee-config \
	--version 0.1 \
	"$BUILT_PKG"
rm -rf "$SUPPORT_DIR/pkgroot"

if [ $DMG_OS_VERS_MAJOR -eq 9 ]; then
	# We'd previously mounted this to check versions
	hdiutil detach "$MNT_BASE_SYSTEM"

	BASE_SYSTEM_DMG_RW="$(/usr/bin/mktemp /tmp/veewee-osx-basesystem-rw.XXXX).dmg"
	rm "$BASE_SYSTEM_DMG_RW"

	msg_status "Converting BaseSystem.dmg to a read-write DMG located at $BASE_SYSTEM_DMG_RW.."
	# hdiutil convert -o will actually append .dmg to the filename if it has no extn
	hdiutil convert -format UDRW -o "$BASE_SYSTEM_DMG_RW" "$BASE_SYSTEM_DMG"

#	BASE_SYSTEM_SHADOW=$(/usr/bin/mktemp /tmp/veewee-osx-basesystem-shadow.XXXX)

	msg_status "Growing new BaseSystem.."
	hdiutil resize -size 6G "$BASE_SYSTEM_DMG_RW"
	msg_status "Mounting new BaseSystem.."
	hdiutil attach "$BASE_SYSTEM_DMG_RW" -mountpoint "$MNT_BASE_SYSTEM" -nobrowse -owners on

	# Remove the symlink on the ESD that would reference the BaseSystem outside
	rm "$MNT_BASE_SYSTEM/System/Installation/Packages"
# 	msg_status "Copying Packages directory from the ESD to BaseSystem.."
# 	cp -Rv "$MNT_ESD/Packages" "$MNT_BASE_SYSTEM/System/Installation/"
	msg_status "Moving 'Packages' directory from the ESD to BaseSystem.."
	mv -v "$MNT_ESD/Packages" "$MNT_BASE_SYSTEM/System/Installation/"

	PACKAGES_DIR="$MNT_BASE_SYSTEM/System/Installation/Packages"
else
	PACKAGES_DIR="$MNT_ESD/Packages"
fi

# Add our auto-setup files: minstallconfig.xml, OSInstall.collection and PartitionInfo.plist
msg_status "Adding automated components.."
mkdir "$PACKAGES_DIR/Extras"
cp "$SUPPORT_DIR/minstallconfig.xml" "$PACKAGES_DIR/Extras/"
cp "$SUPPORT_DIR/OSInstall.collection" "$PACKAGES_DIR/"
cp "$SUPPORT_DIR/PartitionInfo.plist" "$PACKAGES_DIR/Extras/"
cp -R "$AUTOPART_TOOL" "$PACKAGES_DIR/Extras/AutoPartition.app"
cp "$BUILT_PKG" "$PACKAGES_DIR/"
rm -rf "$SUPPORT_DIR/tmp"


if [ $DMG_OS_VERS_MAJOR -eq 9 ]; then
	msg_status "Detaching BaseSystem.."
	hdiutil detach "$MNT_BASE_SYSTEM"
# 	msg_status "Removing original BaseSystem.dmg.."
# 	rm "$MNT_ESD/BaseSystem.dmg"
fi

msg_status "Unmounting.."
hdiutil detach "$MNT_ESD"

msg_status "Converting to final output file.."
if [ $DMG_OS_VERS_MAJOR -lt 9 ]; then
	hdiutil convert -format UDZO -o "$OUTPUT_DMG" -shadow "$SHADOW_FILE" "$ESD"
	rm "$SHADOW_FILE"
else
	msg_status "Converting BaseSystem back to read-only compressed.."
	hdiutil convert -format UDZO -o "$OUTPUT_DMG" "$BASE_SYSTEM_DMG_RW"

fi

rm -rf "$MNT_ESD"

if [ -n "$SUDO_UID" ] && [ -n "$SUDO_GID" ]; then
	msg_status "Fixing permissions.."
	chown -R $SUDO_UID:$SUDO_GID \
		"$OUT_DIR" \
		"$SUPPORT_DIR/AutoPartition-10.${DMG_OS_VERS_MAJOR}"
fi

if [ -n "$DEFAULT_ISO_DIR" ]; then
	DEFINITION_FILE="$DEFINITION_DIR/definition.rb"
	msg_status "Setting ISO file in definition "$DEFINITION_FILE".."
	ISO_FILE=$(basename "$OUTPUT_DMG")
	# Explicitly use -e in order to use double quotes around sed command
	sed -i -e "s/%OSX_ISO%/${ISO_FILE}/" "$DEFINITION_FILE"
fi

msg_status "Checksumming output image.."
MD5=$(md5 -q "$OUTPUT_DMG")
msg_status "MD5: $MD5"

msg_status "Done. Built image is located at $OUTPUT_DMG. Add this iso and its checksum to your template."
