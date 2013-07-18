# OS X templates for Packer and VeeWee

This is a set of templates and scripts that will prepare an OS X installer media that performs an unattended install for use with [Packer](http://packer.io) and [VeeWee](http://github.com/jedi4ever/veewee). These were originally developed for VeeWee.

## Usage

Run the prepare_iso.sh script with two arguments: the path to an "Install OS X.app" or the InstallESD.dmg contained within, and an output directory. For example, with a 10.8.4 Mountain Lion installer:

`prepare_iso/prepare_iso.sh "/Applications/Install OS X Mountain Lion.app" out`

...should produce a DMG at `out/OSX_InstallESD_10.8.4_12E55.dmg`, and an MD5 checksum is printed at the end of the process.

The path and checksum can now be added to your Packer or VeeWee template/definition file. The `packer` and `veewee` folders contain templates that can be used with the `vmware` builder and `vmfusion` providers, for the respective build systems. Note that the Packer template adds some additional VMX options required for OS X guests.

## Automated installs on OS X

OS X's installer supports a kind of bootstrap install functionality similar to Linux and Windows, however it must be invoked using pre-existing files placed on the booted installation media. This approach is roughly equivalent to that used by Apple's System Image Utility for deploying automated OS X installations and image restoration.

The prepare_iso.sh script in this repo takes care of mounting and modifying a vanilla OS X installer downloaded from the Mac App Store. The resulting .dmg file and checksum can then be added to the Packer template or VeeWee definition. Because the preparation is done up front, no boot command sequences are required.

More details as to the modifications to the installer media are provided in the comments of the script.

## Supported guest OS versions

Currently the prepare script supports Lion and Mountain Lion. Support for Mavericks should be trivial to add, but will not be added prior to its public release due to NDA restrictions.

## Virtualbox support

I've heard a report that this method works with the Virtualbox provider in VeeWee, so it may be possible with Packer as well. However, Virtualbox's support for OS X guests is poor, has out of date documentation and no guest tools support, so VMware Fusion is recommended. VMware Fusion also provides support for NetBoot and FileVault 2 full-disk encryption in guests, which is useful for some enterprise environments.

## Box sizes

A built box with CLI tools, Puppet and Chef is over 5GB in size. It might be advisable to remove (with care) some unwanted applications in an additional postinstall script.

## Automated GUI logins

For certain automated tasks (tests requiring a GUI, for example), it's probably necessary to have an active GUI login session. Some extra effort needs to be done to have a user automatically logged in to the GUI, but[CreateUserPkg](http://magervalp.github.com/CreateUserPkg), which was used to help create the box's vagrant user, supports an auto-login option that can be used to do this, so it is possible.

## Alternate approaches to VM provisioning
Mads Fog Albrechtslund documents a [method](http://hazenet.dk/2013/07/17/creating-a-never-booted-os-x-template-in-vsphere-5-1) for converting unbooted .dmg images into VMDK files for use with ESXi.
