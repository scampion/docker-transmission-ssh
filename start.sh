#!/bin/bash
SSH_PASSWORD=`pwgen -c -n -1 12`
echo ssh password: $SSH_PASSWORD
usermod -p $(openssl passwd -1 $SSH_PASSWORD) scampion

set -o nounset                              # Treat unset variables as an error

dir="/var/lib/transmission-daemon"

### timezone: Set the timezone for the container
# Arguments:
#   timezone) for example EST5EDT
# Return: the correct zoneinfo file will be symlinked into place
timezone() { local timezone="${1:-EST5EDT}"
    [[ -e /usr/share/zoneinfo/$timezone ]] || {
        echo "ERROR: invalid timezone specified: $timezone" >&2
        return
    }

    if [[ $(cat /etc/timezone) != $timezone ]]; then
        echo "$timezone" >/etc/timezone
        ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
        dpkg-reconfigure -f noninteractive tzdata >/dev/null 2>&1
    fi
}

### usage: Help
# Arguments:
#   none)
# Return: Help text
usage() { local RC=${1:-0}
    echo "Usage: ${0##*/} [-opt] [command]
Options (fields in '[]' are optional, '<>' are required):
    -h          This help
    -t \"\"       Configure timezone
                possible arg: \"[timezone]\" - zoneinfo timezone for container
The 'command' (if provided and valid) will be run instead of transmission
" >&2
    exit $RC
}

while getopts ":ht:" opt; do
    case "$opt" in
        h) usage ;;
        t) timezone "$OPTARG" ;;
        "?") echo "Unknown option: -$OPTARG"; usage 1 ;;
        ":") echo "No argument value for option: -$OPTARG"; usage 2 ;;
    esac
done
shift $(( OPTIND - 1 ))

[[ "${TZ:-""}" ]] && timezone "$TZ"
[[ "${USERID:-""}" =~ ^[0-9]+$ ]] && usermod -u $USERID -o debian-transmission
[[ "${GROUPID:-""}" =~ ^[0-9]+$ ]]&& groupmod -g $GROUPID -o debian-transmission
for env in $(printenv | grep '^TR_'); do
    name=$(cut -c4- <<< ${env%%=*} | tr '_A-Z' '-a-z')
    val="\"${env##*=}\""
    [[ "$val" =~ ^\"([0-9]+|false|true)\"$ ]] && val=$(sed 's/"//g' <<<$val)
    if grep -q $name $dir/info/settings.json; then
        sed -i "/\"$name\"/s/:.*/: $val,/" $dir/info/settings.json
    else
        sed -i 's/\([0-9"]\)$/\1,/' $dir/info/settings.json
        sed -i "/^}/i\    \"$name\": $val" $dir/info/settings.json
    fi
done
[[ -d $dir/downloads ]] || mkdir -p $dir/downloads
[[ -d $dir/incomplete ]] || mkdir -p $dir/incomplete
[[ -d $dir/info/blocklists ]] || mkdir -p $dir/info/blocklists
chown -Rh debian-transmission. $dir 2>&1 | grep -iv 'Read-only' || :
if [[ $# -ge 1 && -x $(which $1 2>&-) ]]; then
    exec "$@"
elif [[ $# -ge 1 ]]; then
    echo "ERROR: command not found: $1"
    exit 13
elif ps -ef | egrep -v 'grep|transmission.sh' | grep -q transmission; then
    echo "Service already running, please restart container to apply changes"
else
    # Initialize blocklist
    url='http://list.iblocklist.com'
    curl -Ls "$url"'/?list=bt_level1&fileformat=p2p&archiveformat=gz' |
                gzip -cd >$dir/info/blocklists/bt_level1
    chown debian-transmission. $dir/info/blocklists/bt_level1
    exec su -l debian-transmission -s /bin/bash -c "exec transmission-daemon \
                --config-dir $dir/info --blocklist --encryption-preferred \
                --auth --dht --foreground --log-error -e /dev/stdout \
                --download-dir $dir/downloads --incomplete-dir $dir/incomplete \
                --username '${TRUSER:-admin}' --password '${TRPASSWD:-admin}' \
                --no-portmap --allowed \\* 2>&1"
fi

