#!/usr/bin/env bash
export APPDIR=$(mdfind -name "Install OS X Yosemite")
echo "Install found: $APPDIR"
pushd "$(dirname $0)/prepare_iso"
pwd
echo You will need to provider your pasword for sudo so that we can mount new images with full perms
echo sudo ./prepare_iso.sh "$APPDIR" out
sudo ./prepare_iso.sh "$APPDIR" out
#-- Fixing permissions..
#-- Checksumming output image..
#-- MD5: 53ba7c6bec259d8a5bf53eb0aa85889c
#-- Done. Built image is located at out/OSX_InstallESD_10.10.5_14F27.dmg. 
#      Add this iso and its checksum to your template.
popd
export PREPEDDMG=$(find prepare_iso/out -iname \*.dmg)
export PREPEDMD5=$(md5 -q $PREPEDDMG)
pushd packer
packer build \
	-var iso_checksum=$PREPEDMD5 \
	-var iso_url=../$PREPEDDMG \
	-var username=vagrant \
	-var password=vagrant \
	-var autologin=true \
	-var install_vagrant_keys=true \
	-except vmware-iso,parallels-iso \
	template.json
