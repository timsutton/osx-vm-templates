#!/bin/sh
date > /etc/vagrant_box_build_time
OSX_VERS=$(sw_vers -productVersion | awk -F "." '{print $2}')

# Install VMware tools if we were built with VMware
if [ -e .vmfusion_version ] || [ "$PACKER_BUILDER_TYPE" = "vmware" ]; then
	TMPMOUNT=`/usr/bin/mktemp -d /tmp/vmware-tools.XXXX`
	hdiutil attach darwin.iso -mountpoint "$TMPMOUNT"
	installer -pkg "$TMPMOUNT/Install VMware Tools.app/Contents/Resources/VMware Tools.pkg" -target /
	# This usually fails
	hdiutil detach "$TMPMOUNT"
	rm -rf "$TMPMOUNT"
	rm darwin.iso
fi

# Set computer/hostname
COMPNAME=vagrant-osx-10${OSX_VERS}
scutil --set ComputerName ${COMPNAME}
scutil --set HostName ${COMPNAME}.vagrantup.com

# Installing vagrant keys
mkdir /Users/vagrant/.ssh
chmod 700 /Users/vagrant/.ssh
curl -k 'https://raw.github.com/mitchellh/vagrant/master/keys/vagrant.pub' > /Users/vagrant/.ssh/authorized_keys
chmod 600 /Users/vagrant/.ssh/authorized_keys
chown -R vagrant /Users/vagrant/.ssh

# Disable iCloud prompts for GUI logins
#/usr/bin/defaults write "/Users/vagrant/Library/Preferences/com.apple.SetupAssitant" DidSeeCloudSetup -bool true
#/usr/bin/defaults write "/Users/vagrant/Library/Preferences/com.apple.SetupAssitant" LastSeenCloudProductVersion -string 10.8.2
#chown -R vagrant /Users/vagrant/Library
