# OS X templates for Packer and VeeWee

This is a set of Packer templates and support scripts that will prepare an OS X installer media that performs an unattended install for use with [Packer](http://packer.io) and [VeeWee](http://github.com/jedi4ever/veewee). These were originally developed for VeeWee, but support for the VeeWee template has not been maintained since Packer's release and so it is only provided for historical purposes.

The machine is also configured for use with [Vagrant](http://www.vagrantup.com), using either the [Hashicorp VMware Fusion provider](http://www.vagrantup.com/vmware) or Vagrant's included [VirtualBox provider](http://docs.vagrantup.com/v2/virtualbox/index.html). Use with the Fusion provider requires Vagrant 1.3.0, and use with the VirtualBox provider Vagrant 1.6.3 if using the Rsync file sync mechanism. Note that the VeeWee template also does not have any VirtualBox support.

Provisioning steps that are defined in the template via items in the [scripts](https://github.com/timsutton/osx-vm-templates/tree/master/scripts) directory:
- [Vagrant-specific configuration](http://docs.vagrantup.com/v2/boxes/base.html)
- VM guest tools installation if on VMware
- Xcode CLI tools installation
- Chef installation via the [Opscode Omnibus installer](http://www.opscode.com/chef/install)
- Puppet installation via [AutoPkg](https://github.com/autopkg/autopkg) [recipes](https://github.com/autopkg/recipes/tree/master/Puppetlabs)


## Preparing the ISO

OS X's installer cannot be bootstrapped as easily as can Linux or Windows, and so exists the [prepare_iso.sh](https://github.com/timsutton/osx-vm-templates/blob/master/prepare_iso/prepare_iso.sh) script to perform modifications to it that will allow for an automated install and ultimately allow Packer and later, Vagrant, to have SSH access.

Run the `prepare_iso.sh` script with two arguments: the path to an `Install OS X.app` or the `InstallESD.dmg` contained within, and an output directory. Root privileges are required in order to write a new DMG with the correct file ownerships. For example, with a 10.8.4 Mountain Lion installer:

`sudo prepare_iso/prepare_iso.sh "/Applications/Install OS X Mountain Lion.app" out`

...should output progress information ending in something this:

```
-- MD5: dc93ded64396574897a5f41d6dd7066c
-- Done. Built image is located at out/OSX_InstallESD_10.8.4_12E55.dmg. Add this iso and its checksum to your template.
```

#### Clone this repository

The `prepare_iso.sh` script needs the `support` directory and its content. In other words, the easiest way to run the script is after cloning this repository.

#### Snow Leopard

The `prepare_iso.sh` script depends on `pkgbuild` utility. As `pkgbuild` is not installed on Snow Leopard (contrary to the later OS X), you need to install XCode 3.2.6 which includes it.

## Use with Packer

The path and checksum can now be added to your Packer template or provided as [user variables](http://www.packer.io/docs/templates/user-variables.html). The `packer` directory contains a template that can be used with the `vmware-iso` and `virtualbox-iso` builders. The `veewee` directory contains a definition, though as mentioned above it is not currently being maintained.

The Packer template adds some additional VM options required for OS X guests. Note that the paths given in the Packer template's `iso_url` builder key accepts file paths, both absolute and relative (to the current working directory).

Given the above output, we could run then run packer:

```sh
cd packer
packer build \
  -var iso_checksum=dc93ded64396574897a5f41d6dd7066c \
  -var iso_url=../out/OSX_InstallESD_10.8.4_12E55.dmg \
  template.json
```

You might also use the `-only` option to restrict to either the `vmware-iso` or `virtualbox-iso` builders.

## Automated installs on OS X

OS X's installer supports a kind of bootstrap install functionality similar to Linux and Windows, however it must be invoked using pre-existing files placed on the booted installation media. This approach is roughly equivalent to that used by Apple's System Image Utility for deploying automated OS X installations and image restoration.

The `prepare_iso.sh` script in this repo takes care of mounting and modifying a vanilla OS X installer downloaded from the Mac App Store. The resulting .dmg file and checksum can then be added to the Packer template. Because the preparation is done up front, no boot command sequences, attached devices or web server access is required.

More details as to the modifications to the installer media are provided in the comments of the script.


## Supported guest OS versions

Currently the prepare script supports Lion, Mountain Lion, and Mavericks.


## Automated GUI logins

For some kinds of automated tasks, it may be necessary to have an active GUI login session (for example, test suites requiring a GUI, or Jenkins SSH slaves requiring a window server for their tasks). The Packer templates support enabling this automatically by using the `autologin_vagrant_user` user variable, which can be set to anything non-zero, for example:

`packer build -var autologin_vagrant_user=yes template.json`

This was easily made possible thanks to Per Olofsson's [CreateUserPkg](http://magervalp.github.com/CreateUserPkg) utility, which was used to help create the box's vagrant user in the `prepare_iso` script, and which also supports generating the magic kcpassword file with a particular hash format to set up the auto-login.


## VirtualBox support

VirtualBox support is thanks entirely to contributions by [Matt Behrens (@zigg)](https://github.com/zigg) to this repo, Vagrant and Packer.

### Caveats

#### Shared folders

Oracle's support for OS X in VirtualBox is very limited, including the lack of guest tools to provide a shared folder mechanism. If using the VirtualBox provider in Vagrant, you will need to configure the shared folder that's set up by default (current folder mapped to `/vagrant`) to use either the `rsync` or `nfs` synced folder mechanisms. You can do this like any other synced folder config in your Vagrantfile:

```ruby
Vagrant.configure("2") do |config|
  config.vm.provider "virtualbox" do |vb|
    config.vm.synced_folder ".", "/vagrant", type: "rsync"
  end
end
```

#### Additional VM configuration for Packer

So far we've seen that the `--cpuidset` option needs to be passed to `modifyvm` as a line in the packer template if a Haswell Intel Mac is used to build the VM, at least as of VirtualBox 4.3.12. It seems to cause a VM crash on at least one older Mac, a Core 2 Duo-based 2010 Mac Mini, though did not cause issues on an Ivy Bridge 2013 iMac I tested. If it's missing on a Haswell Mac, however, the VM hangs indefinitely. This behaviour is likely to change over time as Oracle keeps up with support for OS X guests.

```json
      "vboxmanage": [
        ["modifyvm", "{{.Name}}", "--cpuidset", "00000001", "000306a9", "00020800", "80000201", "178bfbff"],
      ]
```


## Box sizes

A built box with CLI tools, Puppet and Chef is over 5GB in size. It might be advisable to remove (with care) some unwanted applications in an additional postinstall script. It should also be possible to modify the OS X installer package to install fewer components, but this is non-trivial. One can also supply a custom "choice changes XML" file to modify the installer choices in a supported way, but from my testing, this only allows removing several auxiliary packages that make up no more than 6-8% of the installed footprint (for example, multilingual voices and dictionary files).


## Alternate approaches to VM provisioning

Mads Fog Albrechtslund documents an [interesting method](http://hazenet.dk/2013/07/17/creating-a-never-booted-os-x-template-in-vsphere-5-1) for converting unbooted .dmg images into VMDK files for use with ESXi.
