#!/bin/bash
set -xeu

NOTIFY_CONFIG='/mnt/notify-config.yaml'
IFS=$'\n'
CS_INJECTOR_MANIFEST=$(cat <<EOF
{
    "manifest_version": 3,
    "name": "content-script-injector",
    "content_scripts": [
        {
            "matches": ["<all_urls>"],
            "all_frames": true,
            "js": ["content_script.js"]
        }
    ],
    "host_permissions":[ "*://*/*" ]
}
EOF
)

function extract_har() {
    name="$1"
    har_file="$2"
    selectors=$(yq '.Targets[] | select(.Name == "'$name'" and .Selectors != null) | .Selectors' "$config_file")
    [[ -z "$selectors" ]] && selectors="."

    tmp_file=$(mktemp -p $tmpdir)
    for selector in $selectors; do 
        [[ -z "$selector" ]] && selector="."
        jq -c ".log.entries[] | . as \$reqResp | $selector | \$reqResp" "$har_file" >> $tmp_file
    done

    for url in $(jq -r '.request.url' $tmp_file | sort -u | awk '{ print length, $0 }' | sort -n -s -r | cut -d " " -f2-); do
        domain=$(echo "$url" | unfurl format %d)
        path=$(echo "$url" | unfurl format %p | rev | cut -d / -f 2- | rev | head -c 3800)
        file=$(echo "$url" | unfurl format %p | rev | cut -d / -f 1 | rev)

        mkdir -p "$name/${domain}${path}" 2>/dev/null

        filename="$name/${domain}${path}/$(echo $file | head -c 249)"
        if [[ -d "$filename" ]]; then
            filename="${filename%/}.html"
        fi

        jq -c 'select( .request.url == "'$url'" and .response.content.text != null)' "$tmp_file" | 
            head -n 1 | 
            jq -r '.response.content.text' >"$filename"
    done
}

function monitor() {
    name="$1"
    config=$(yq '.Targets[] | select(.Name == "'$name'")' "$config_file")
    mkdir -p "$name" 2>/dev/null

    args=()
    for header in $(yq 'select(.ExtraHeaders != null) | .ExtraHeaders' <<< $config); do 
        args+=("-H" "$header") 
    done

    if [[ $(yq 'select(.ContentScript != null)' <<< $config) != "" ]]; then
        echo "$CS_INJECTOR_MANIFEST" >$tmpdir/manifest.json
        yq '.ContentScript' <<< $config >$tmpdir/content_script.js
        args+=("-A" "--load-extension=$tmpdir")
    fi

    find "$name/" -not -name 'matchers.txt' -type f -exec rm -rf -- {} \;

    if [[ $(yq 'select(.Pages != null)' <<< $config) != "" ]]; then
        for page in $(yq '.Pages' <<< $config); do
            har_file="${name}/$(echo $(echo $page | head -c 249).har | tr '/\\' '_')"
            stealthy-har-capturer ${args[@]} -A "-disable-popup-blocking" -t 20000 -g 12000 -o "$har_file" "$page" || return 0
            extract_har "$name" "$har_file"
        done
    elif [[ $(yq 'select(.Custom != null)' <<< $config) != "" ]]; then
        tmp_page="$(mktemp -p $tmpdir).html"
        har_file="${name}/${name}.har"
        yq '.Custom' <<< $config >$tmp_page
        stealthy-har-capturer ${args[@]} -A "--disable-web-security" -t 20000 -g 12000 -o "$har_file" "file://$tmp_page" || return 0
        extract_har "$har_file" "$name" .
    fi

    [[ -f "$name/matchers.txt" ]] && prev_checksum=$(md5sum "$name/matchers.txt" | cut -d ' ' -f1) || prev_checksum=""
    for matcher in $(yq '.Matchers' <<< $config); do
        eval "find '$name' -mindepth 2 -type f | grep -v '/cdn-cgi/' | $matcher >> $name/matchers.txt"
    done
    checksum=$(md5sum "$name/matchers.txt" | cut -d ' ' -f1)

    for processing in $(yq 'select(.PostProcessing != null) | .PostProcessing' <<< $config); do
        eval "find '$name/' -mindepth 2 -type f | $processing" || true
    done

    if [[ -n "$prev_checksum" && "$checksum" != "$prev_checksum" ]]; then
        git add .
        printf "change detected at $name\n$(git status --short $name/*/ | sed "s,$name/,,")" | 
            notify -bulk -silent -provider-config "$NOTIFY_CONFIG" -id monitor
        git commit -m "change detected at $name"
        gh auth status && git push
    fi
}

if [[ $# -lt 1 ]]; then
    echo "$0 <target>"
    exit 1
fi

config_file="/mnt/data/$1/bbmon.yml"
cd "/mnt/data/$1/"

exec > >(tee "monitor.log") 2>&1

jitter=$(yq '.Jitter' "$config_file")
if [[ ! -z "$jitter" ]]; then
    min=$(date +%s)
    max=$(date -d "$jitter" +%s)
    sleep $(($RANDOM % ($max - $min)))
fi

echo "Starting at $(date)"

tmpdir=$(mktemp -d -p /tmp bbmon-XXXX)
trap "rm -rf $tmpdir" EXIT

for name in $(yq '.Targets[] | .Name' "$config_file"); do
    monitor "$name"
done
