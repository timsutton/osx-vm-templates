OS X Templates for Packer
=========================

Build macOS [Vagrant](https://www.vagrantup.com/) boxes using [Packer](https://www.packer.io/).

- [Getting Started](#getting-started)
  - [Prerequisites](#prerequisites)
  - [Supported OS Versions](#supported-os-versions-and-build-sources)
  - [Supported Virtualization Providers](#supported-virtualization-providers)
- [Create a Source](#create-a-source)
- [Build and Provision using Packer](#build-and-provision-using-packer)
  - [ISO Builders](#iso-builders)
  - [VM Builders](#vm-builders)
- [Provisioning Options](#provisioning-options)
- [Tips and Troubleshooting](#tips-and-troubleshooting)
  - [Packer Build Tips](#packer-build-tips)
  - [How to Add the Vagrant Box](#how-to-add-the-vagrant-box)
- [Acknowledgements](#acknowledgements)

Getting Started
---------------

This repo is comprised of two main components: a set of [image preparation scripts](https://github.com/timsutton/osx-vm-templates/tree/master/prepare_iso)
to create a build source and a [versatile Packer template](https://github.com/timsutton/osx-vm-templates/blob/master/packer/template.json)
used to create a macOS Vagrant box. Along with the build template is a
complementary set of [provisioning scripts](https://github.com/timsutton/osx-vm-templates/tree/master/scripts)
that allow for a multitude of different provisioning and configuration options.

**General workflow:**

1. Create a build source from a macOS install bundle
1. Use Packer to provision and process the source into a Vagrant box

### Prerequisites

- **A Virtualization Provider**
  - [Parallels Desktop](https://www.parallels.com/products/desktop/buypd4) ($79/year)
  - [VirtualBox](https://www.virtualbox.org/manual/ch02.html#idm858) (Free)
  - [VMware Fusion](https://www.vagrantup.com/vmware/index.html) ($79/seat)
- **A macOS Installer app bundle**
  - [macOS High Sierra 10.13](https://itunes.apple.com/us/app/macos-high-sierra/id1246284741?mt=12)
  - [macOS Sierra](https://support.apple.com/en-us/HT208202)
  - [Older Versions](https://developer.apple.com/download/more/)
- [Packer](https://www.packer.io/intro/getting-started/install.html)
- [Vagrant](https://www.vagrantup.com/intro/getting-started/install.html)

Alternatively, each of the prerequisite tools are installable as
[Homebrew](https://brew.sh/) formulae or casks:

```plain
brew cask install parallels virtualbox vmware-fusion vagrant
brew install packer
```

If you're using Parallels or VMware Fusion, you'll need to install plugins to
use with Vagrant:

```plain
vagrant plugin install vagrant-parallels vagrant-vmware-fusion
```

### Supported OS Versions and Build Sources

This repo supports two types of Packer sources (i.e. builders):

- ISO images
- Virtual machine files assembled using a virtual hard disk (VHD)

Depending on the macOS version, there are some restrictions on what
source type you need to use. These restrictions may also change which prerequisites
you are required to have.

The table below shows which sources are supported on which operating system versions.

| Operating System Version           | ISO                | VHD + VM           |
| ---------------------------------- |:------------------:|:------------------:|
| OS X Lion 10.7                     | :white_check_mark: | :white_check_mark: |
| OS X Mountain Lion 10.8            | :white_check_mark: | :white_check_mark: |
| OS X Mavericks 10.9                | :white_check_mark: | :white_check_mark: |
| OS X Yosemite 10.10                | :white_check_mark: | :white_check_mark: |
| OS X El Capitan 10.11              | :white_check_mark: | :white_check_mark: |
| macOS Sierra <= 10.12.3            | :white_check_mark: | :white_check_mark: |
| macOS Sierra >= 10.12.4            | :x:                | :white_check_mark: |
| macOS High Sierra 10.13            | :x:                | :white_check_mark: |

### Supported Virtualization Providers

The table below shows which virtualization providers support each source type.

| Virtualization Providers           | ISO                | VHD + VM           |
| ---------------------------------- |:------------------:|:------------------:|
| [VMware Fusion](http://www.vagrantup.com/vmware)           | :white_check_mark: | :x:                |
| [Parallels](http://parallels.github.io/vagrant-parallels/) | :white_check_mark: | :white_check_mark: |
| [VirtualBox](https://www.vagrantup.com/docs/virtualbox/)   | :white_check_mark: | :white_check_mark: |

In general, using an ISO as the source is more desirable for several reasons:

- A single ISO can be used to create Vagrant boxes for multiple providers
- It does not require extra disk space
- The ISO can be created in a single step

Unfortunately, creating ISO sources from an installer of any version after 10.12.3
is not possible due to package signing restrictions by Apple. More details about
this issue can be found in [things to watch out for](#things-to-watch-out-for).

Create a Source
---------------

For either source type, it is recommended that your working directory be `osx-vm-templates/packer`.

### ISO

Apple's OS installer cannot be bootstrapped as easily as can Linux or Windows, and
so exists the[prepare_iso.sh](https://github.com/timsutton/osx-vm-templates/blob/master/prepare_iso/prepare_iso.sh)
script to perform modifications to it that will allow for an automated install
and ultimately allow Packer and later, Vagrant, to have SSH access.
`prepare_iso.sh` makes use of Apple's [custom NetInstall workflow](https://help.apple.com/systemimageutility/mac/10.12/#/sysmb1457f0b)

Run the `prepare_iso.sh` script with two arguments: the path to an
OS install bundle and an output directory. Root privileges are required in order
to write a new DMG with the correct file ownerships. For example, with an OS X
10.8.4 Mountain Lion installer:

```plain
sudo prepare_iso/prepare_iso.sh "/Applications/Install OS X Mountain Lion.app" out
```

...should output progress information ending in something this:

```plain
-- MD5: dc93ded64396574897a5f41d6dd7066c
-- Done. Built image is located at out/OSX_InstallESD_10.8.4_12E55.dmg. Add this iso and its checksum to your template.
```

`prepare_iso.sh` accepts command line options and parameters to modify the details
of the admin user created by the script.

```plain
  -u <user>
    Sets the username of the root user, defaults to 'vagrant'.

  -p <password>
    Sets the password of the root user, defaults to 'vagrant'.

  -i <path to image>
    Sets the path of the avatar image for the root user, defaulting to the vagrant icon.
```

For example:

```plain
$ sudo prepare_iso/prepare_iso.sh \
> -u admin \
> -p password \
> -i /path/to/image.jpg "/Applications/Install OS X Mountain Lion.app" out
```

Additionally, flags can be set to disable certain default configuration options.

```plain
  -D <flag>
    Sets the specified flag. Valid flags are:
      DISABLE_REMOTE_MANAGEMENT
      DISABLE_SCREEN_SHARING
      DISABLE_SIP
```

### VHD + Virtual Machine

Using the VHD/VM approach, it is possible to create a Vagrant box from a fresh
macOS install bundle - even with the restriction implemented in 10.12.4 and above.

#### IMPORTANT

- The VHD/VM approach currently requires VirtualBox
- Due to the nature of this approach, you'll (temporarily) need ~30GB of free
  storage space.

For the VHD/VM source type, we'll be using `prepare_vhd.sh`, which uses a strategy
similar to [AutoDMG](https://github.com/MagerValp/AutoDMG): utilize the installer's
own `OSInstall.pkg` by creating a fresh install in a temporary DMG sparse disk image.
Again, this is then converted into a VHD using VirtualBox's command line tools.
The basic workflow for the VHD/VM method takes two steps:

1. Create a virtual hard disk (VHD) from Apple OS install bundle.
1. Use VHD as the primary boot device for the assembly of a VirtualBox and/or
  Parallels virtual machine file.

Again, this approach requires VirtualBox, even if you are only using Parallels.
This is because its commandline tools are used to convert raw bytes into the VHD.

#### Step 1: Create a VHD

The `prepare_vhd.sh` script takes a base macOS installer straight from the App Store
and turns it into a VHD.  can then be used to assemble
either a VirtualBox or Parallels virtual machine.

**Note**: Similar to `prepare_iso.sh`, this script must be run with `sudo`.

```plain
sudo ../prepare_iso/prepare_vhd.sh "/Applications/Install macOS High Sierra.app" out
```

Where the first argument to the script is the installer bundle and the second is
the output directory for the VHD. In this example, the resulting artifact would
be a `macOS_10.13.1.vhd` file located in the same directory that the script
was run.

#### Step 2: Assemble a virtual machine file using the VHD

**VirtualBox:**

```plain
../prepare_iso/prepare_ovf.sh out/macOS_10.13.1.vhd
```

Where the first argument is VHD file obtained after finishing step one. The result
of step two would be something like `macOS_10.13.1.ovf` in the same directory.
This is the value of `source_url` in step three.

**Parallels:**

```plain
../prepare_iso/prepare_pvm.sh out/macOS_10.13.1.vhd
```

Where the first argument is VHD file obtained after finishing step one. The result
of step two would be something like `macOS_10.13.1.ovf` in the same directory.

Move on to the next phase and use the resulting `.ovf` and/or `.pvm` bundles as
the `source_path` variable for the `virtualbox-ovf` and/or `parallels-pvm`
Packer builders to create the Vagrant box.

Build and Provision using Packer
--------------------------------

The path to your source artifact from the previous step can now be using with the
Packer template or provided as a [user variable](http://www.packer.io/docs/templates/user-variables.html).
The `packer` directory contains a template that can be used with three ISO builders
and two VM builders. Which builder(s) you choose are strictly dependent on your
source type. Each of the builder names are suffixed with their corresponding
source/file type (i.e. `vmware-iso` is an ISO, `parallels-pvm` corresponds to a
Parallels VM file: `.pvm`).

Be sure to review the [provisioning options](#provisioning-options)
that are available before you begin the build process.

### ISO Builders

When using an ISO builder, the checksum does not need to be added because the `iso_checksum_type`
has been set to "none". However, since ISO files are so big, a checksum is
highly recommended.

The Packer template adds some additional VM options required for OS X guests. Note
that the paths given in the Packer template's `iso_url` builder key accepts file
paths, both absolute and relative (to the current working directory).

Given the example artifact shown earlier, we could run Packer like so:

```plain
$ cd packer
$ packer build \
> -var 'iso_url=./out/OSX_InstallESD_10.8.4_12E55.dmg' \
> template.json
```

You might also consider using `-only` to restrict the type of builder to `vmware-iso`,
`virtualbox-iso` or `parallels-iso` builders depending on what virtualization provider(s)
you want the Vagrant box to be used with.

If you modified the name or password of the admin account in the `prepare_iso` stage,
you'll need to pass in the modified details as Packer variables. You can also prevent
the Vagrant SSH keys from being installed for that user. For example:

```plain
$ packer build \
> -var 'iso_url=./out/OSX_InstallESD_10.8.4_12E55.dmg' \
> -var 'username=youruser' \
> -var 'password=yourpassword' \
> -var 'install_vagrant_keys=false' \
> template.json
```

### VM Builders

Depending which type of VM you build using the VHD, you'll have something
like `macOS_10.13.1.ovf` and/or `macOS_10.13.1.pvm` to use with the Packer
template as the source type. For example:

```plain
$ packer build  \
> -var 'source_url=./out/macOS_10.13.1.ovf' \
> -only virtualbox-ovf template.json
```

```plain
$ packer build  \
> -var 'source_url=./out/macOS_10.13.1.pvm' \
> -only virtualbox-pvm template.json
```

Provisioning Options
--------------------

Several provisioning options are available to be used in the template once you
are ready to execute your Packer build:

- [Automatic Login](#automatic-login)
- [Configuration Management Tools](#configuration-management-tools)
- [Xcode Command Line Tools](#xcode-command-line-tools)
- [Provisioning Delay](#provisioning-delay)
- [Software Updates](#software-updates)
- Guest Tools for [VMware Fusion](https://pubs.vmware.com/fusion-4/index.jsp?topic=%2Fcom.vmware.fusion.help.doc%2FGUID-82AEC35C-D3DC-42F4-A84B-542B1D501D2B.html)
  and [Parallels](http://blog.parallels.com/2017/02/21/parallels-tools/)
- Disk shrinking (VMware only)
- [Provisioner-specific configuration](https://www.vagrantup.com/docs/boxes/base.html)

The implementation of these options can be viewed in [scripts](https://github.com/timsutton/osx-vm-templates/tree/master/scripts).

### Automatic Login

For some kinds of automated tasks, it may be necessary to have an active GUI login
session (for example, test suites requiring a GUI, or Jenkins SSH slaves requiring
a window server for their tasks). The Packer templates support enabling this automatically
by using the `autologin` user variable, which can be set to `1` or `true`. For example:

```plain
$ packer build \
> -var 'autologin=true' \
> template.json
```

This was easily made possible thanks to Per Olofsson's [CreateUserPkg](http://magervalp.github.com/CreateUserPkg)
utility, which was used to help create the box's vagrant user in the `prepare_iso`
script, and which also supports generating the magic kcpassword file with a particular
hash format to set up the auto-login.

### Configuration Management Tools

By default, the Packer template does not install Chef nor Puppet. You can enable
the installation of configuration management by setting one or more of the following
Packer variables to `latest` or a specific version:

- `chef_version`
- `puppet_agent_version`
- `puppet_version`
- `facter_version`
- `hiera_version`

Install the latest version of **Chef** via the [Chef Omnitruck install script](https://docs.chef.io/install_omnibus.html):

```plain
$ packer build \
> -var 'chef_version=latest'
> template.json
```

Install the lastest version of **Puppet Agent** via [Puppetlabs Mac installers](https://downloads.puppetlabs.com/mac)

```plain
$ packer build \
> -var 'pupet_agent_version=latest'
> template.json
```

Install the latest versions of the (now deprecated) standalone Puppet, Facter
and Hiera packages:

```plain
$ packer build \
> -var 'puppet_version=latest' \
> -var 'facter_version=latest' \
> -var 'hiera_version=latest'
> template.json
```

### Xcode Command Line Tools

The Xcode CLI tools are installed by the packer template by default. To disable
the installation, set the `install_xcode_cli_tools` variable to `false`:

```plain
$ packer build \
> -var 'install_xcode_cli_tools=false'
> template.json
```

### Software Updates

Packer will instruct the system to download and install all available OS X updates,
if you want to disable this default behaviour, use `update_system` variable:

```plain
$ packer build \
> -var 'update_system=0'
> template.json
```

### Provisioning Delay

In some cases, it may be helpful to insert a delay into the beginning of the provisioning
process. Adding a delay of about 30 seconds may help subsequent provisioning steps
that install software from the internet complete successfully. By default, the delay
is set to `0`, but you can change the delay by setting the `provisioning_delay` variable:

```plain
$ packer build \
> -var 'provisioning_delay=30'
template.json
```

Tips and Troubleshooting
------------------------

### Packer Build Tips

#### Inspect

Run `packer inspect packer/template.json` to have a closer look at the
template. This may help clear up some confusion before you execute your build.

#### Validate

It's also good practice to validate the template with the expected variables
before executing your build:

```plain
$ packer validate \
> -var 'source_url=./out/macOS_10.13.1.ovf' \
> -only virtualbox-ovf template.json
Template validated successfully.
```

#### Var Files

It should also be known that Packer allows the use of dedicated JSON file for
setting variable values for ease of reuse and use in source control.
For example, the Packer build execution might look something like:

```plain
$ packer build \
> -var-file=parallels-packer.json \
> -only=parallels-pvm \
> template.json
```

Where the contents of `parallels-packer.json` might be something like:

```plain
$ cat packer/parallels-packer.json
{
    "chef_version": "latest",
    "autologin": "true",
    "source_path: "./out/macOS_10.13.1.pvm",
}
```

### How to Add the Vagrant Box

After the build finishes (regardless of your source type), you'll end up with a
freshly provisioned macOS Vagrant box that you can add to your `VAGRANT_HOME` directory:

```plain
vagrant box add packer_parallels_pvm.box --name macos-10.13.2
```

If you have a private Vagrant cloud set up using [vagrancy](https://github.com/ryandoyle/vagrancy),
you could add your new box like so:

```plain
curl --upload-file packer_parallels_pvm.box http://server-foo:8099/username-bar/macos-10.13.1/1.0.0/parallels
```

### Local VM builds take up a lot of disk space

It's possible to make Packer work with different directories.

- `PACKER_CACHE_DIR`: A [Packer environment variable](https://www.packer.io/docs/other/environment-variables.html#packer_cache_dir)
  that configures where Packer caches ISOs, etc.
- `PACKER_OUTPUT_DIR`: The directory where the virtual machine will be stored during
  provisioning. (ISO builder only)
- `PACKER_VAGRANT_BOX_DIR`: The parents directory of the box file that will be created
 by the Vagrant post-processor.

**Note:** Don't make `PACKER_OUTPUT_DIR` and `PACKER_VAGRANT_BOX_DIR` the same place.
`keep_input_artifacts` in the post-processor defaults to `false`, and it removes
them by removing the directory, not the individual files. So if you use the same
place, you'll end up with no output at all (packer `v1.0.0`).

Keep in mind that a built box with CLI tools, Puppet and Chef is over 5GB in size.
It might be advisable to remove (with care) some unwanted applications in an
additional postinstall script. It should also be possible to modify the OS X installer
package to install fewer components, but this is non-trivial. One can also supply
a custom "choice changes XML" file to modify the installer choices in a supported
way. Testing has shown that this only allows removing several auxiliary packages
that make up no more than 6-8% of the installed footprint (e.g, multilingual voices
and dictionary files).

### VMware Tools Flavor

As of version 8.5.4, to build a box of an OS version less than 10.11, you will need
to change the `tools_upload_flavor` from `darwin` to `darwinPre15`.

### Package Signing Restrictions

Starting with macOS 10.12.4, the macOS installer no longer supports including third-party
packages. Because of this (undocumented) additional requirement, we can't currently
install the necessary configuration that allows Packer to log in and perform additional
configuration, install guest tools, etc. Attempting to do so results in the following
output:

```plain
The package veewee-config.pkg is not signed.
```

The rest of the OS install still completes
successfully. It may be possible to work around this by modifying the rc script
directly with the contents of our postinstall script.

### Setting Remote Management in VirtualBox VMs causes intermitten unresponsiveness

The default `prepare_iso.sh` configuration enables Remote Management during installation.
This can cause the resulting virtual machine to [periodically freeze](https://github.com/timsutton/osx-vm-templates/issues/43).
To avoid this, disable remote management during ISO preparation by setting
`prepare_iso.sh`'s `-D` option to `DISABLE_REMOTE_MANAGEMENT`:

```plain
$ sudo ./prepare_iso/prepare_iso.sh \
> -D DISABLE_REMOTE_MANAGEMENT \
> "/Applications/Install OS X El Capitan.app" out
```

### Using Rsync for File Syncing

- VMware Fusion provider requires Vagrant 1.3+
- VirtualBox provider requires Vagrant 1.6.3+

### VeeWee Template Support

The `veewee` directory contains a definition, though it is not currently being
maintained. The VeeWee template also does not have any VirtualBox
or Parallels support.

### VirtualBox Shared Folders

Oracle's support for OS X in VirtualBox is very limited, including the lack of guest
tools to provide a shared folder mechanism. If using the VirtualBox provider in
Vagrant, you will need to configure the shared folder that's set up by default
(current folder mapped to `/vagrant`) to use either the `rsync` or `nfs` synced
folder mechanisms. You can do this like any other synced folder config in your Vagrantfile:

```ruby
Vagrant.configure("2") do |config|
  config.vm.provider "virtualbox" do |vb|
    config.vm.synced_folder ".", "/vagrant", type: "rsync"
  end
end
```

Alternative Options
-------------------

Joe Chilcote has written a tool, [vfuse](https://github.com/chilcote/vfuse), which
converts a never-booted OS X image (such as created with a tool like [AutoDMG](https://github.com/MagerValp/AutoDMG))
into a VMDK and configures a VMware Fusion VM. vfuse can also configure a Packer
template alongside the VM, configured with the `vmware-vmx` builder.

Acknowledgements
----------------

VirtualBox support is thanks entirely to the contributions of
[Matt Behrens (@zigg)](https://github.com/zigg) to not only this repo, but
Vagrant and Packer as well.
