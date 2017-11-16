#!/bin/bash

# Handle the possibility of being sourced from outside this project dir
called=$_
if [[ $called != "${0}" ]]; then
  SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
else
  SCRIPT_DIR="$(cd "$(dirname "$0")" || exit; pwd)"
fi
SUPPORT_DIR="$SCRIPT_DIR/support"

# Parse the optional command line switches
USER="vagrant"
PASSWORD="vagrant"
IMAGE_PATH="$SUPPORT_DIR/vagrant.jpg"

# Flags
DISABLE_REMOTE_MANAGEMENT=0
DISABLE_SCREEN_SHARING=0
DISABLE_SIP=0

render_template() {
  eval "echo \"$(cat "$1")\""
}

create_firstboot_pkg() {
  # payload items
  mkdir -p "$SUPPORT_DIR/pkgroot/private/var/db/dslocal/nodes/Default/users"
  mkdir -p "$SUPPORT_DIR/pkgroot/private/var/db/shadow/hash"
  BASE64_IMAGE=$(openssl base64 -in "$IMAGE_PATH")
  ShadowHashData=$($SCRIPT_DIR/../scripts/support/generatehash.py "$PASSWORD")
  # Replace USER and BASE64_IMAGE in the user.plist file with the actual user and image
  render_template "$SUPPORT_DIR/user.plist" > "$SUPPORT_DIR/pkgroot/private/var/db/dslocal/nodes/Default/users/$USER.plist"
  USER_GUID=$(/usr/libexec/PlistBuddy -c 'Print :generateduid:0' "$SUPPORT_DIR/user.plist")
  # Generate a shadowhash from the supplied password
  "$SUPPORT_DIR/generate_shadowhash" "$PASSWORD" > "$SUPPORT_DIR/pkgroot/private/var/db/shadow/hash/$USER_GUID"

  # postinstall script
  mkdir -p "$SUPPORT_DIR/tmp/Scripts"
  cat "$SUPPORT_DIR/pkg-postinstall" \
      | sed -e "s/__USER__PLACEHOLDER__/${USER}/" \
      | sed -e "s/__DISABLE_REMOTE_MANAGEMENT__/${DISABLE_REMOTE_MANAGEMENT}/" \
      | sed -e "s/__DISABLE_SCREEN_SHARING__/${DISABLE_SCREEN_SHARING}/" \
      | sed -e "s/__DISABLE_SIP__/${DISABLE_SIP}/" \
      > "$SUPPORT_DIR/tmp/Scripts/postinstall"
  chmod a+x "$SUPPORT_DIR/tmp/Scripts/postinstall"

  # build it
  BUILT_COMPONENT_PKG="$SUPPORT_DIR/tmp/veewee-config-component.pkg"
  BUILT_PKG="$SUPPORT_DIR/tmp/veewee-config.pkg"
  pkgbuild --quiet \
  	--root "$SUPPORT_DIR/pkgroot" \
  	--scripts "$SUPPORT_DIR/tmp/Scripts" \
  	--identifier com.vagrantup.veewee-config \
  	--version 0.1 \
  	"$BUILT_COMPONENT_PKG"
  productbuild \
  	--package "$BUILT_COMPONENT_PKG" \
  	"$BUILT_PKG"
  rm -rf "$SUPPORT_DIR/pkgroot"
}
