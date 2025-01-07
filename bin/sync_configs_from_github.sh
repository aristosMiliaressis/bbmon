#!/bin/bash
set -xeuo pipefail

repo_url="$(gh repo view bbmon_data --json url --jq .url)"

(
    echo "PATH=$PATH";
    echo "0 0 * * * sync_configs_from_github.sh"
) | crontab -

for branch in $(git ls-remote --heads "$repo_url" | cut -d/ -f3); do
    if [[ -d "/mnt/data/$branch/" ]]; then
        rm -rf /mnt/data/$branch/
    fi

    git clone -b "$branch" "$repo_url" "/mnt/data/$branch/"
    if [[ ! -f "/mnt/data/$branch/bbmon.yml" ]]; then 
        continue
    fi

    (crontab -l; echo "$(yq '.Schedule' /mnt/data/$branch/bbmon.yml) monitor.sh $branch") | crontab -
done
