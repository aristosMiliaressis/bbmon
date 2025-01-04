#!/bin/bash
set -xeuo pipefail

if [[ -f /mnt/gh_hosts.yml ]]; then
    mkdir -p $HOME/.config/gh
    cp /mnt/gh_hosts.yml $HOME/.config/gh/hosts.yml
    gh auth setup-git

    if ! gh repo view bbmon_data; then
        gh repo create bbmon_data --private
    fi

    sync_configs_from_github.sh
else
    echo "PATH=$PATH" | crontab -
    for yaml_file in $(ls /mnt/data/*/bbmon.yml); do
        (crontab -l; echo "$(yq '.Schedule' $yaml_file) monitor.sh $yaml_file") | crontab -
    done
fi

crontab -l 

cron -f