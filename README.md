# OS X templates for Packer and VeeWee

This is a set of Packer templates and support scripts that will prepare an OS X installer media that performs an unattended install for use with [Packer](http://packer.io) and [VeeWee](http://github.com/jedi4ever/veewee). These were originally developed for VeeWee, but support for the VeeWee template has not been maintained since Packer's release and so it is only provided for historical purposes. I plan on removing VeeWee support from this repo soon, but VeeWee can still make use of the preparation script and the [OS X template](https://github.com/jedi4ever/veewee/tree/master/templates/OSX) remains in the core VeeWee repo.

The machine built by this Packer template defaults to being configured for use with [Vagrant](http://www.vagrantup.com), and supports three Vagrant providers by using Packer's respective builders:

- The [Hashicorp VMware Fusion provider](http://www.vagrantup.com/vmware) (recommended)
- Vagrant's included [VirtualBox provider](http://docs.vagrantup.com/v2/virtualbox/index.html)
- [Parallels](https://github.com/Parallels/vagrant-parallels)

It's possible to build a machine with different admin account settings, and without the vagrant ssh keys, for use with other systems, e.g. continuous integration.

Use with the Fusion provider requires Vagrant 1.3.0, and use with the VirtualBox provider Vagrant 1.6.3 if using the Rsync file sync mechanism. Note that the VeeWee template also does not have any VirtualBox or Parallels support.

Provisioning steps that are defined in the template via items in the [scripts](https://github.com/timsutton/osx-vm-templates/tree/master/scripts) directory:
- [Vagrant-specific configuration](http://docs.vagrantup.com/v2/boxes/base.html)
- VM guest tools installation if on VMware
- Xcode CLI tools installation
- Chef installation via the [Chef client installer for OS X](https://www.getchef.com/download-chef-client)
- Puppet installation via [Puppetlabs Mac installers](https://downloads.puppetlabs.com/mac) - no configuration for Puppet 4 yet, coming soon

## Supported guest OS versions

Currently this prepare script and template supports all versions of OS X that are distributed through the App Store: OS X Lion (10.7) through El Capitan (10.11).

This project currently only supplies a single Packer template (`template.json`), so the hypervisor's configured guest OS version (i.e. `darwin12-64`) does not accurately reflect the actual installed OS. I haven't found there to be any functional differences depending on these configured guest versions.

## Preparing the ISO

OS X's installer cannot be bootstrapped as easily as can Linux or Windows, and so exists the [prepare_iso.sh](https://github.com/timsutton/osx-vm-templates/blob/master/prepare_iso/prepare_iso.sh) script to perform modifications to it that will allow for an automated install and ultimately allow Packer and later, Vagrant, to have SSH access.

**Note:** VirtualBox users currently have to disable Remote Management to avoid [periodic freezing](https://github.com/timsutton/osx-vm-templates/issues/43) of the VM by adding `-D DISABLE_REMOTE_MANAGEMENT` to the `prepare_iso.sh` options. See [Remote Management freezing issue](#remote-management-freezing-issue) for more information.

Run the `prepare_iso.sh` script with two arguments: the path to an `Install OS X.app` or the `InstallESD.dmg` contained within, and an output directory. Root privileges are required in order to write a new DMG with the correct file ownerships. For example, with a 10.8.4 Mountain Lion installer:

`sudo prepare_iso/prepare_iso.sh "/Applications/Install OS X Mountain Lion.app" out`

...should output progress information ending in something this:

```
-- MD5: dc93ded64396574897a5f41d6dd7066c
-- Done. Built image is located at out/OSX_InstallESD_10.8.4_12E55.dmg. Add this iso and its checksum to your template.
```

`prepare_iso.sh` accepts command line switches to modify the details of the admin user installed by the script.

* `-u` modifies the name of the admin account, defaulting to `vagrant`
* `-p` modifies the password of the same account, defaulting to `vagrant`
* `-i` sets the path of the account's avatar image, defaulting to `prepare_iso/support/vagrant.jpg`

For example:

`sudo prepare_iso/prepare_iso.sh -u admin -p password -i /path/to/image.jpg "/Applications/Install OS X Mountain Lion.app" out`

Additionally, flags can be set to disable certain default configuration options.

* `-D DISABLE_REMOTE_MANAGEMENT` disables the Remote Management service.
* `-D DISABLE_SCREEN_SHARING` disables the Screen Sharing service.

#### Clone this repository

The `prepare_iso.sh` script needs the `support` directory and its content. In other words, the easiest way to run the script is after cloning this repository.

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

If you modified the name or password of the admin account in the `prepare_iso` stage, you'll need to pass in the modified details as packer variables. You can also prevent the vagrant SSH keys from being installed for that user.

For example:

```
packer build \
  -var iso_checksum=dc93ded64396574897a5f41d6dd7066c \
  -var iso_url=../out/OSX_InstallESD_10.8.4_12E55.dmg \
  -var username=youruser \
  -var password=yourpassword \
  -var install_vagrant_keys=false \
  template.json
```


## Automated installs on OS X

OS X's installer supports a kind of bootstrap install functionality similar to Linux and Windows, however it must be invoked using pre-existing files placed on the booted installation media. This approach is roughly equivalent to that used by Apple's System Image Utility for deploying automated OS X installations and image restoration.

The `prepare_iso.sh` script in this repo takes care of mounting and modifying a vanilla OS X installer downloaded from the Mac App Store. The resulting .dmg file and checksum can then be added to the Packer template. Because the preparation is done up front, no boot command sequences, attached devices or web server access is required.

More details as to the modifications to the installer media are provided in the comments of the script.


## Automated GUI logins

For some kinds of automated tasks, it may be necessary to have an active GUI login session (for example, test suites requiring a GUI, or Jenkins SSH slaves requiring a window server for their tasks). The Packer templates support enabling this automatically by using the `autologin` user variable, which can be set to `1` or `true`, for example:

`packer build -var autologin=true template.json`

This was easily made possible thanks to Per Olofsson's [CreateUserPkg](http://magervalp.github.com/CreateUserPkg) utility, which was used to help create the box's vagrant user in the `prepare_iso` script, and which also supports generating the magic kcpassword file with a particular hash format to set up the auto-login.

## System updates

Packer will instruct the system to download and install all available OS X updates, if you want to disable this default behaviour, use `update_system` variable:

```
packer build -var update_system=0 template.json
```

## VirtualBox support

VirtualBox support is thanks entirely to contributions by [Matt Behrens (@zigg)](https://github.com/zigg) to this repo, Vagrant and Packer.

### Caveats

#### Remote Management freezing issue

The default `prepare_iso.sh` configuration enables Remote Management during installation, which causes the resulting virtual machine to [periodically freeze](https://github.com/timsutton/osx-vm-templates/issues/43). You can avoid enabling Remote Management when using `prepare_iso.sh` by passing `-D DISABLE_REMOTE_MANAGEMENT` this:

```
sudo ./prepare_iso/prepare_iso.sh -D DISABLE_REMOTE_MANAGEMENT "/Applications/Install OS X El Capitan.app" out
```

#### Extension Pack

The VirtualBox Extension Pack, available from the [Download VirtualBox](https://www.virtualbox.org/wiki/Downloads) page or as the [Homebrew cask](http://caskroom.io/) [virtualbox-extension-pack](https://github.com/caskroom/homebrew-cask/blob/master/Casks/virtualbox-extension-pack.rb), is now required by default because we enable EHCI (USB 2.0) support like the default VirtualBox OS X template does.

If you cannot use the Extension Pack, you can remove the line that enables EHCI support from [`packer/template.json`](https://github.com/timsutton/osx-vm-templates/blob/master/packer/template.json):

```
        ["modifyvm", "{{.Name}}", "--usbehci", "on"],
```

#### Shared folders

Oracle's support for OS X in VirtualBox is very limited, including the lack of guest tools to provide a shared folder mechanism. If using the VirtualBox provider in Vagrant, you will need to configure the shared folder that's set up by default (current folder mapped to `/vagrant`) to use either the `rsync` or `nfs` synced folder mechanisms. You can do this like any other synced folder config in your Vagrantfile:

```ruby
Vagrant.configure("2") do |config|
  config.vm.provider "virtualbox" do |vb|
    config.vm.synced_folder ".", "/vagrant", type: "rsync"
  end
end
```


## Box sizes

A built box with CLI tools, Puppet and Chef is over 5GB in size. It might be advisable to remove (with care) some unwanted applications in an additional postinstall script. It should also be possible to modify the OS X installer package to install fewer components, but this is non-trivial. One can also supply a custom "choice changes XML" file to modify the installer choices in a supported way, but from my testing, this only allows removing several auxiliary packages that make up no more than 6-8% of the installed footprint (for example, multilingual voices and dictionary files).


## Alternate approaches to VM provisioning

Joe Chilcote has written a tool, [vfuse](https://github.com/chilcote/vfuse), which converts a never-booted OS X image (such as created with a tool like [AutoDMG](https://github.com/MagerValp/AutoDMG)) into a VMDK and configures a VMware Fusion VM. vfuse can also configure a Packer template alongside the VM, configured with the `vmware-vmx` builder.
