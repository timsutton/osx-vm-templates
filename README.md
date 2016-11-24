# packer-osx

This is a set of [Packer][] templates and scripts to help automate the
installation of OS X. It's based off of [timsutton/osx-vm-templates][].

## Usage

This set of scripts supports all versions of OS X that are distributed through
the App Store: OS X Lion (10.7) through El Capitan (10.11), and macOS Sierra
(10.12).

This fork has a few templates to support different use cases:

* `vagrant.json`
* `standalone.json`
* `vmware-esxi.json`

### Preparing the ISO

`prepare_iso.sh` builds a custom ISO image which has been modified to automate 
the install.

Run the `prepare_iso.sh` script with two arguments: the path to an `Install OS
X.app` or the `InstallESD.dmg` contained within, and an output directory. Root
privileges are required in order to write a new DMG with the correct file
ownerships. For example, with a 10.8.4 Mountain Lion installer:

```
sudo prepare_iso/prepare_iso.sh "/Applications/Install OS X El Capitan.app" iso
```

...should output progress information ending in something this:

```
-- MD5: dc93ded64396574897a5f41d6dd7066c
-- Done. Built image is located at iso/OSX_InstallESD_10.11.6_15G31.dmg.
```

`prepare_iso.sh` accepts command line switches to modify the details of the
admin user installed by the script.

* `-u` modifies the name of the admin account, defaults to `vagrant`
* `-p` modifies the password of the same account, defaults to `vagrant`
* `-i` sets the path of the account's avatar image, defaults to
  `prepare_iso/support/vagrant.jpg`

For example:

```
sudo prepare_iso/prepare_iso.sh -u admin -p password -i /path/to/image.jpg \
  "/Applications/Install OS X El Capitan.app" iso
```

Additionally, flags can be set to disable certain default configuration options.

* `-D DISABLE_REMOTE_MANAGEMENT` disables the Remote Management service.
* `-D DISABLE_SCREEN_SHARING` disables the Screen Sharing service.

### Building with Packer

The templates include a set of additional VM options that are needed for OS X
guests. The output ISO can be passed to Packer in a user variable.

```sh
packer build \
  -var iso_url=iso/OSX_InstallESD_10.11.6_15G31.dmg \
  template.json
```

You might also use the `-only` option to restrict to either the `vmware-iso` or
`virtualbox-iso` builders.

#### Configuration Options

The installation is automated inside the disk image, so there is little inside
the Packer template itself. However, the provisioning scripts have a few
options:

##### Username & Password

```
-var username=youruser \
-var password=yourpassword \
```

##### Automated GUI logins

If you need to attach to a login session, this will cause the user to
automatically login:

`packer build -var autologin=true template.json`

##### Vagrant

```
packer build -var install_vagrant_keys=false template.json
```

##### Chef & Puppet

By default, the template doesn't install Chef or Puppet. To enable this, set
the version to `latest`, or to a specific version:

```
packer build -var chef_version=latest template.json
```

```
packer build -var puppet_version=latest template.json
```

##### Xcode CLI Tools

The Xcode CLI tools are installed by the packer template by default. To disable
the installation, set the `install_xcode_cli_tools` variable to `false`:

```
packer build -var install_xcode_cli_tools=false template.json
```

##### System updates

Packer will instruct the system to download and install all available OS X
updates, if you want to disable this default behaviour, use `update_system`
variable:

```
packer build -var update_system=0 template.json
```

##### Provisioning delay

In some cases, it may be helpful to insert a delay into the beginning of the
provisioning process. Adding a delay of about 30 seconds may help subsequent
provisioning steps that install software from the internet complete
successfully. By default, the delay is set to `0`, but you can change the delay
by setting the `provisioning_delay` variable:

```
packer build -var provisioning_delay=30 template.json`
```

[Packer]: https://packer.io
[timsutton/osx-vm-templates]: https://github.com/timsutton/osx-vm-templates
