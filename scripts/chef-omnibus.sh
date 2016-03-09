#!/bin/bash
# http://www.opscode.com/chef/install

if [[ "$NOCM" =~ ^(true|yes|on|1|TRUE|YES|ON])$ ]]; then
    exit
fi

if [ "${CHEF_VERSION}" == "none" ]; then
    exit
fi

INSTALL_ARGS=""

if [ "${CHEF_VERSION}" != "latest" ]; then
    INSTALL_ARGS="-v ${CHEF_VERSION}"
fi

curl -LO https://www.opscode.com/chef/install.sh
bash ./install.sh "${INSTALL_ARGS}"
rm install.sh
