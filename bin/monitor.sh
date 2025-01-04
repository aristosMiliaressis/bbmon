#!/bin/bash
set -xeu

NOTIFY_CONFIG='/mnt/notify-config.yaml'
IFS=$'\n'

function extract_har() {
    har_file="$1"
    name="$2"
    [[ -z "$3" ]] && selectors="." || selectors="$3"

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

function monitor_page() {
    name="$1"
    pages=$(yq '.Targets[] | select(.Name == "'$name'") | .Pages' "$config_file")
    selectors="$(yq '.Targets[] | select(.Name == "'$name'" and .Selectors != null) | .Selectors' "$config_file")"
    matchers=$(yq '.Targets[] | select(.Name == "'$name'") | .Matchers' "$config_file")
    extra_headers="$(yq '.Targets[] | select(.Name == "'$name'" and .ExtraHeaders != null) | .ExtraHeaders' "$config_file")"
    post_processing="$(yq '.Targets[] | select(.Name == "'$name'" and .PostProcessing != null) | .PostProcessing' "$config_file")"
    mkdir -p "$name" 2>/dev/null

    headers=()
    for header in $extra_headers; do 
        headers+=("-H" "$header") 
    done

    find "$name/" -not -name 'matchers.txt' -type f -exec rm -rf -- {} \;

    for page in $pages; do 
        har_file="${name}/$(echo $(echo $page | head -c 249).har | tr '/\\' '_')"
        stealthy-har-capturer -A "--disable-web-security" ${headers[@]} -t 20000 -g 6000 -o "$har_file" "$page" || return 0
        extract_har "$har_file" "$name" "$selectors"
    done

    [[ -f "$name/matchers.txt" ]] && prev_checksum=$(md5sum "$name/matchers.txt" | cut -d ' ' -f1) || prev_checksum=""
    for matcher in $matchers; do
        eval "find '$name' -mindepth 2 -type f | grep -v '/cdn-cgi/' | $matcher >> $name/matchers.txt"
    done
    checksum=$(md5sum "$name/matchers.txt" | cut -d ' ' -f1)
    
    for processing in $post_processing; do
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

function monitor_custom() {
    name="$1"
    matchers=$(yq '.Targets[] | select(.Name == "'$name'") | .Matchers' "$config_file")
    extra_headers="$(yq '.Targets[] | select(.Name == "'$name'" and .ExtraHeaders != null) | .ExtraHeaders' "$config_file")"
    post_processing="$(yq '.Targets[] | select(.Name == "'$name'" and .PostProcessing != null) | .PostProcessing' "$config_file")"
    mkdir -p "$name" 2>/dev/null

    headers=()
    for header in $extra_headers; do 
        headers+=("-H" "$header") 
    done

    find "$name/" -not -name 'matchers.txt' -type f -exec rm -rf -- {} \;

    tmp_page="$(mktemp -p $tmpdir).html"
    yq '.Targets[] | select(.Name == "'$name'") | .Custom' "$config_file" > $tmp_page

    har_file="${name}/${name}.har"
    stealthy-har-capturer -A "--disable-web-security" ${headers[@]} -t 20000 -g 6000 -o "$har_file" "file://$tmp_page" || return 0
    extract_har "$har_file" "$name" .

    [[ -f "$name/matchers.txt" ]] && prev_checksum=$(md5sum "$name/matchers.txt" | cut -d ' ' -f1) || prev_checksum=""
    for matcher in $matchers; do
        eval "find '$name/' -mindepth 2 -type f | $matcher >> $name/matchers.txt"
    done
    checksum=$(md5sum "$name/matchers.txt" | cut -d ' ' -f1)

    for processing in $post_processing; do
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
    echo "$0 <config_file>"
    exit 1
fi

config_file="$(realpath $1)"
cd "$(dirname $config_file)"

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

for name in $(yq '.Targets[] | select(.Pages != null) | .Name' "$config_file"); do
    monitor_page "$name"
done

for name in $(yq '.Targets[] | select(.Custom != null) | .Name' "$config_file"); do
    monitor_custom "$name"
done
