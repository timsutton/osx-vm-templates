#!/bin/bash

if [ "$UPDATE_SYSTEM" != "true" ] && [ "$UPDATE_SYSTEM" != "1" ]; then
  exit
fi

MAJOR_VERSION=$(/usr/bin/sw_vers -productVersion | /usr/bin/cut -d '.' -f 2,2)

if [ "$MAJOR_VERSION" -lt 13 ]; then
  echo "Ignoring automatic High Sierra updates..."
  softwareupdate --ignore "Install macOS High Sierra"
fi

echo "Downloading and installing system updates..."
softwareupdate --install --all
