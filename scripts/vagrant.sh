#!/bin/sh
date > /etc/vagrant_box_build_time
OSX_VERS=$(sw_vers -productVersion | awk -F "." '{print $2}')

# Set computer/hostname
COMPNAME=vagrant-osx-10-${OSX_VERS}
scutil --set ComputerName ${COMPNAME}
scutil --set HostName ${COMPNAME}.vagrantup.com

# Installing vagrant keys
mkdir /Users/vagrant/.ssh
chmod 700 /Users/vagrant/.ssh
curl -k 'https://raw.github.com/mitchellh/vagrant/master/keys/vagrant.pub' > /Users/vagrant/.ssh/authorized_keys
chmod 600 /Users/vagrant/.ssh/authorized_keys
chown -R vagrant /Users/vagrant/.ssh

# If we're on 10.9 we need to symlink the site_suby folder so Puppet and Chef install to the right place.

if [ "$OSX_VERS" -ge 9 ]; then
    rm -rf /usr/lib/ruby/site_ruby/1.8
    ln -s /usr/lib/ruby/site_ruby/2.0.0/ /usr/lib/ruby/site_ruby/1.8
fi