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
    for branch in $(ls /mnt/data/); do
        (crontab -l; echo "$(yq '.Schedule' /mnt/data/$branch/bbmon.yml) monitor.sh $branch") | crontab -
    done
fi

crontab -l 

cron -f