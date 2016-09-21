#!/bin/bash

sw_vers=$(sw_vers -productVersion)
sw_build=$(sw_vers -buildVersion)

# Dissable the spindump process
sudo launchctl unload -w /System/Library/LaunchDaemons/com.apple.spindump.plist

# Skip the whole iCloud setup step for all users
for USER_TEMPLATE in "/System/Library/User Template"/*
do
  /usr/bin/defaults write "${USER_TEMPLATE}"/Library/Preferences/com.apple.SetupAssistant DidSeeCloudSetup -bool TRUE
  /usr/bin/defaults write "${USER_TEMPLATE}"/Library/Preferences/com.apple.SetupAssistant GestureMovieSeen none
  /usr/bin/defaults write "${USER_TEMPLATE}"/Library/Preferences/com.apple.SetupAssistant LastSeenCloudProductVersion "${sw_vers}"
  /usr/bin/defaults write "${USER_TEMPLATE}"/Library/Preferences/com.apple.SetupAssistant LastSeenBuddyBuildVersion "${sw_build}"      
done
