#!/bin/sh

# Install the specified version of Puppet and tools
#
# PUPPET_VERSION, FACTER_VERSION and HIERA_VERSION are set to either
# 'latest' or specific versions via the Packer template
#
# install function mostly borrowed dmg function from hashicorp/puppet-bootstrap,
# except we just take an already-downloaded dmg

if [[ "${PUPPET_VERSION}" == "none" && \
      "${FACTER_VERSION}" == "none" && \
      "${HIERA_VERSION}" == "none" && \
      "${PUPPET_AGENT_VERSION}" == "none" ]]; then
    exit
fi

install_dmg() {
    local name="$1"
    local dmg_path="$2"

    echo "Installing: ${name}"

    # Mount the DMG
    echo "-- Mounting DMG..."
    tmpmount=$(/usr/bin/mktemp -d /tmp/puppet-dmg.XXXX)
    hdiutil attach "${dmg_path}" -mountpoint "${tmpmount}"

    echo "-- Installing pkg..."
    pkg_path=$(find "${tmpmount}" -name '*.pkg' -mindepth 1 -maxdepth 1)
    installer -pkg "${pkg_path}" -tgt /

    # Unmount
    echo "-- Unmounting and ejecting DMG..."
    hdiutil eject "${tmpmount}"
}

get_dmg() {
    local recipe_name="$1"
    local version="$2"
    local report_path=$(mktemp /tmp/autopkg-report-XXXX)

    # Run AutoPkg setting VERSION, and saving the results as a plist
    "${AUTOPKG}" run --report-plist "${report_path}" -k VERSION="${version}" "${recipe_name}" > \
        "$(mktemp "/tmp/autopkg-runlog-${recipe_name}")"
    /usr/libexec/PlistBuddy -c \
        'Print :summary_results:url_downloader_summary_result:data_rows:0:download_path' \
        "${report_path}"
}

# Default to installing the current version of Puppet - it's not 2013 anymore.
PUPPET_VERSION=${PUPPET_VERSION:-none}
FACTER_VERSION=${FACTER_VERSION:-none}
HIERA_VERSION=${HIERA_VERSION:-none}
PUPPET_AGENT_VERSION=${PUPPET_AGENT_VERSION:-latest}

# Get AutoPkg
AUTOPKG_DIR=$(mktemp -d /tmp/autopkg-XXXX)
git clone https://github.com/autopkg/autopkg "$AUTOPKG_DIR"
AUTOPKG="$AUTOPKG_DIR/Code/autopkg"

# Add the recipes repo containing Puppet/Facter
"${AUTOPKG}" repo-add recipes

# Redirect AutoPkg cache to a temp location
defaults write com.github.autopkg CACHE_DIR -string "$(mktemp -d /tmp/autopkg-cache-XXX)"

if [ "${PUPPET_VERSION}" != "none" ]; then
  # Hide all users from the loginwindow with uid below 500, which will include the puppet user
  defaults write /Library/Preferences/com.apple.loginwindow Hide500Users -bool YES
  PUPPET_DMG=$(get_dmg Puppet.download "${PUPPET_VERSION}")
  install_dmg "Puppet" "${PUPPET_DMG}"
fi

if [ "${PUPPET_AGENT_VERSION}" != "none" ]; then
  # Hide all users from the loginwindow with uid below 500, which will include the puppet user
  defaults write /Library/Preferences/com.apple.loginwindow Hide500Users -bool YES
  PUPPET_AGENT_DMG=$(get_dmg Puppet-Agent.download "${PUPPET_AGENT_VERSION}")
  install_dmg "Puppet Agent" "${PUPPET_AGENT_DMG}"
fi

if [ "${FACTER_VERSION}" != "none" ]; then
  FACTER_DMG=$(get_dmg Facter.download "${FACTER_VERSION}")
  install_dmg "Facter" "${FACTER_DMG}"
fi

if [ "${HIERA_VERSION}" != "none" ]; then
  HIERA_DMG=$(get_dmg Hiera.download "${HIERA_VERSION}")
  install_dmg "Hiera" "${HIERA_DMG}"
fi


# Clean up
rm -rf "${PUPPET_DMG}" "${FACTER_DMG}" "${HIERA_DMG}" "${PUPPET_AGENT_DMG}" "${AUTOPKG_DIR}" "~/Library/AutoPkg"

defaults delete com.github.autopkg
