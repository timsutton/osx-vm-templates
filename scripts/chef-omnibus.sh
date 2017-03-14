#!/bin/bash

if [ "${CHEF_VERSION}" == "none" ]; then
    exit
fi

INSTALL_ARGS=""

if [ "${CHEF_VERSION}" != "latest" ]; then
    INSTALL_ARGS="-v ${CHEF_VERSION}"
fi

curl -LO https://www.chef.io/chef/install.sh
chmod +x ./install.sh
./install.sh "${INSTALL_ARGS}"
rm install.sh
