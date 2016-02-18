#!/bin/sh
LAUNCHDAEMON=/Library/LaunchDaemons/com.github.timsutton.osx-vm-templates.disablebeamsync.plist
EXECUTABLE=/usr/local/bin/disable_beam_sync
OSX_VERS=$(sw_vers -productVersion | awk -F "." '{print $2}')

if [ "${OSX_VERS}" != 10 ]; then
    exit 0
fi

cat <<EOF > "${LAUNCHDAEMON}"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>LimitLoadToSessionType</key>
    <array>
        <string>LoginWindow</string>
        <string>Aqua</string>
    </array>
    <key>Label</key>
    <string>com.github.timsutton.osx-vm-templates.disablebeamsync</string>
    <key>ProgramArguments</key>
    <array>
        <string>${EXECUTABLE}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
EOF
chmod 644 "${LAUNCHDAEMON}"
chown root:wheel "${LAUNCHDAEMON}"

# Courtesy of Michael Lynn:
# https://gist.github.com/pudquick/2ab183707545413ae9c6
cat <<EOF > "${EXECUTABLE}"
#!/usr/bin/python
import ctypes, ctypes.util

# Import CoreGraphics as a C library, so we can call some private functions
c_CoreGraphics = ctypes.CDLL(ctypes.util.find_library('CoreGraphics'))

def disable_beam_sync(doDisable):
    if doDisable:
        # Disabling beam sync:
        # 1st: Enable Quartz debug
        err = c_CoreGraphics.CGSSetDebugOptions(ctypes.c_uint64(0x08000000))
        # 2nd: Set beam sync to disabled mode
        err = c_CoreGraphics.CGSDeferredUpdates(0)
    else:
        # Enabling beam sync:
        # 1st: Disable Quartz debug
        err = c_CoreGraphics.CGSSetDebugOptions(0)
        # 2nd: Set beam sync to automatic mode (the default)
        err = c_CoreGraphics.CGSDeferredUpdates(1)

# Disable beam sync
disable_beam_sync(True)
EOF
chmod 755 "${EXECUTABLE}"
