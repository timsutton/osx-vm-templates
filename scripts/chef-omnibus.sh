#!/bin/bash

# http://www.opscode.com/chef/install
curl -L https://www.opscode.com/chef/install.sh | bash

# Force exiting zero because the installer doesn't yet recognize 10.9 as
# a valid install target
exit 0
