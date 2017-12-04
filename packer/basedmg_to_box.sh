#!/usr/bin/env bash

sudo ../prepare_iso/prepare_vhd.sh "$1" .
sudo -k
../prepare_iso/prepare_pvm.sh "$(find . -iname '*.vhd')"

