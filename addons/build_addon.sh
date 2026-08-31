#!/bin/bash
if [[ -z "$1" ]]; then
    echo Specify the addon:
    find addons -maxdepth 1 -type d | tail -n +2
    exit 1
fi
echo Building: "addons/$1"
vpkeditcli --single-file --version=1 "addons/$1"