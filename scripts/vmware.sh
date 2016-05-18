#!/bin/sh

# VMware specific items
if [[ "$PACKER_BUILDER_TYPE" == vmware* ]]; then
    # VMware Fusion specific items
    TMPMOUNT=`/usr/bin/mktemp -d /tmp/vmware-tools.XXXX`
    TOOLS_PATH="/Users/$USERNAME/darwin.iso"
    if [ -e .vmfusion_version ]; then
      MOUNT_COMMAND='hdiutil attach'
      $MOUNT_COMMAND "$TOOLS_PATH" -mountpoint "$TMPMOUNT"
      if [ ! -e "$TOOLS_PATH" ]; then
        echo "Couldn't locate uploaded tools iso at $TOOLS_PATH!"
        exit 1
      fi
    else
      # location of tools when mounted by ESXi
      TMPMOUNT="/Volumes/VMware Tools"
    fi

    INSTALLER_PKG="$TMPMOUNT/Install VMware Tools.app/Contents/Resources/VMware Tools.pkg"
    if [ ! -e "$INSTALLER_PKG" ]; then
        echo "Couldn't locate VMware installer pkg at $INSTALLER_PKG!"
        exit 1
    fi

    echo "Installing VMware tools.."
    installer -pkg "$INSTALLER_PKG" -target /

    if [ -e .vmfusion_version ]; then
        # clean up for Fusion
        # This usually fails
        hdiutil detach "$TMPMOUNT"
        rm -rf "$TMPMOUNT"
        rm -f "$TOOLS_PATH"

        # Point Linux shared folder root to that used by OS X guests,
        # useful for the Hashicorp vmware_fusion Vagrant provider plugin
        mkdir /mnt
        ln -sf /Volumes/VMware\ Shared\ Folders /mnt/hgfs
    fi
fi
