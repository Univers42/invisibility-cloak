#!/usr/bin/env bash
IPCHANGER="${IPCHANGER_DIR:-/usr/share/ip-changer}"
# No root? /usr/share isn't yours: keep Tor's data in your own state folder instead.
if [[ -z "${IPCHANGER_DIR:-}" && ! -w "$IPCHANGER" && ! -w "$(dirname "$IPCHANGER")" ]]; then
    IPCHANGER="${XDG_STATE_HOME:-$HOME/.local/state}/ip-changer"
fi
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
MAGENTA="\e[35m"
CYAN="\e[36m"
RESET="\e[0m"

printf '%b' "
${CYAN}⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⣀⣤⡶⠶⠟⠛⠛⠛⠋⠙⠛⠛⠿⢶⣦⣄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⣴⡾⠋⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠙⢿⣦⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⢠⣾⠏⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣀⣀⣀⣀⣽⣿⣆⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⢠⣿⠃⠀⠀⢰⡶⠾⠿⠿⠿⠛⠛⠻⣿⠋⠀⠀⢸⡟⠉⠉⣭⣍⢹⡿⣷⡀⠀⠀⠀⠀⠀⠀
⠀⣾⠃⠀⠀⠀⣿⡀⠀⠀⠰⠿⠆⣠⡿⠀⠀⠀⠈⢷⣤⣀⣼⡿⠟⠀⠹⣷⠀⠀⠀⠀⠀⠀⠀
⢸⡟⠀⠀⠀⠀⠘⠿⣶⣤⣤⣶⠾⠟⠁⠀⠀⠀⠀⠀⠈⠉⣁⣀⣀⠀⠀⢻⡇⠀⠀⠀⠀⠀⠀
⢸⡇⠀⠀⠀⠀⢀⣀⣠⣤⣤⣤⡶⠶⠶⠶⠶⠖⠛⠛⠛⠛⣿⠋⠉⠀⠀⢸⣿⠀⠀⠀⠀⠀⠀
⣺⡇⠀⠀⠀⠈⠉⠉⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣸⡇⠀⠀⠀⣼⡇⠀⠀⠀⣤⡄⠀
⠸⣷⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣶⠀⢠⡿⠁⠀⣠⣾⠏⠀⠀⠀⢀⣿⣇⠀
⠀⠹⣿⣄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣰⣿⣦⠟⠁⣠⣾⠟⠁⠀⠀⠀⠀⣿⠉⣽⠂
⠀⠀⠈⠻⢷⣦⣄⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣼⠋⣹⣿⣴⡿⠋⠀⠀⢀⣠⣤⣶⣿⡽⠞⠁⠀
⠀⠀⠀⠀⠀⣸⡿⠻⠿⢶⣶⣶⣶⣶⣶⠶⣛⣷⡾⠛⠉⣿⣁⣠⠴⢞⣫⡵⠟⠋⠁⠀⠀⠀⠀
⠀⠀⠀⠀⣰⡟⠀⠀⢀⣤⡴⠟⣋⣥⡶⠚⠋⠁⠀⠀⠀⣿⣋⣤⠶⠛⠉⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⢰⡿⠀⠀⠐⣋⣤⣶⠟⠋⠁⠀⠀⠀⠀⠀⠀⠀⣿⠋⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⢠⣿⠃⠀⠀⠘⠛⠉⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣿⠀⠀${MAGENTA}CATCH ME IF YOU CAN${CYAN}⠀⠀
⠀⠀⣼⡟⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣿⠀ ${MAGENTA}IP-CHANGER BY ALIENKRISHN${CYAN}
⠀⢠⣿⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⣿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⣼⡟⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠘⣿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀
${RESET}run ip-changer -h to see usage
${BLUE}SOCKS5 PROXY : 127.0.0.1 PORT 9050-9090${RESET}

"

usage() {
    echo -e "${BLUE}Usage: ip-changer [-r SECONDS]${RESET}"
    echo -e "${BLUE}Options:${RESET}"
    echo -e "  -r SECONDS  Set IP rotation interval (default: 10 seconds, min: 5 seconds)"
    echo -e "  -h          Show this help message"
    echo -e "Environment:"
    echo -e "  BRIDGES=snowflake|obfs4|FILE   reach Tor where it's blocked"
    echo -e "  IPCHANGER_BASE_PORT=9050       SOCKS ports BASE, BASE+10 … BASE+40 (control ports: each +1)"
    echo -e "  IPCHANGER_HTTP_PORT=8118       also an HTTPS (CONNECT) proxy on that port, for apps without SOCKS"
    echo -e "\n${GREEN}Available SOCKS5 proxies:${RESET}"
    echo -e "127.0.0.1:9050 (Tor instance 1)"
    echo -e "127.0.0.1:9060 (Tor instance 2)"
    echo -e "127.0.0.1:9070 (Tor instance 3)"
    echo -e "127.0.0.1:9080 (Tor instance 4)"
    echo -e "127.0.0.1:9090 (Tor instance 5)"
    exit 1
}

DEFAULT_ROTATION_TIME=10
MIN_ROTATION_TIME=5
ROTATION_TIME=$DEFAULT_ROTATION_TIME

while getopts ":r:h" opt; do
    case $opt in
        r)
            if [[ "$OPTARG" =~ ^[0-9]+$ ]] && [[ "$OPTARG" -ge $MIN_ROTATION_TIME ]]; then
                ROTATION_TIME="$OPTARG"
            else
                echo -e "${RED}Invalid rotation interval. Using default $DEFAULT_ROTATION_TIME seconds.${RESET}"
            fi
            ;;
        h)
            usage
            ;;
        *)
            echo -e "${RED}Invalid option: -$OPTARG${RESET}"
            usage
            ;;
    esac
done

# SOCKS on BASE, BASE+10 … BASE+40; each instance's control port is its SOCKS port + 1.
BASE=${IPCHANGER_BASE_PORT:-9050}
if ! [[ $BASE =~ ^[0-9]+$ ]] || ((BASE < 1024 || BASE > 65000)); then
    echo -e "${RED}IPCHANGER_BASE_PORT=$BASE: pick a number from 1024 to 65000${RESET}" >&2
    exit 1
fi
PORTS=() CONTROL_PORTS=()
for i in {0..4}; do PORTS+=($((BASE + 10 * i))) CONTROL_PORTS+=($((BASE + 10 * i + 1))); done

# setup.sh runs ip-changer as a boot service; a second copy on its ports would only fight it.
if [[ -z "${INVOCATION_ID:-}" && $BASE = 9050 ]] && systemctl is-active --quiet ip-changer 2>/dev/null; then
    echo -e "${YELLOW}ip-changer already runs as a service. Live log: journalctl -fu ip-changer${RESET}"
    exit 0
fi

# Check if Tor is installed
if ! command -v tor &> /dev/null; then
    echo -e "${RED}Tor is not installed. Install the 'tor' package with your package manager first,${RESET}"
    echo -e "${BLUE}e.g. sudo apt install tor | sudo dnf install tor | sudo pacman -S tor | sudo zypper install tor${RESET}"
    exit 1
fi

# BRIDGES=snowflake|obfs4 (Tor Browser's lines, in bridges/ next to this script) or the path to
# a file of your own lines from https://bridges.torproject.org: reach Tor where it's blocked.
bridge_conf() {
    local file pt bin need
    case "${BRIDGES:-off}" in
        off | "") return 0 ;;
        /*) file=$BRIDGES ;;
        *) file="$(dirname "$(readlink -f "$0")")/bridges/$BRIDGES.txt" ;;
    esac
    if [[ ! -r "$file" ]]; then
        echo -e "${RED}BRIDGES=$BRIDGES: no bridge list at $file${RESET}" >&2
        return 1
    fi
    echo "UseBridges 1"
    while read -r pt; do
        case $pt in
            obfs4 | webtunnel) need="lyrebird (or obfs4proxy)" bin=$(command -v lyrebird || command -v obfs4proxy) ;;
            snowflake) need=snowflake-client bin=$(command -v snowflake-client || command -v snowflake-pt-client) ;;
            *) need="a program for '$pt'" bin="" ;;
        esac
        if [[ -z "$bin" ]]; then
            echo -e "${RED}BRIDGES=$BRIDGES: install $need with your package manager${RESET}" >&2
            return 1
        fi
        echo "ClientTransportPlugin $pt exec $bin"
    done < <(awk '!/^[[:space:]]*(#|$)/ && $1 !~ /[:.]/ {print $1}' "$file" | sort -u)
    awk '!/^[[:space:]]*(#|$)/ {print "Bridge " $0}' "$file"
}
BRIDGE_CONF=$(bridge_conf) || exit 1

printf "Starting multitor service...\n"
# Only the Tors of a previous ip-changer run (by their torrc), not Tor Browser or a system Tor.
pkill -f "$IPCHANGER/.tor_multi/tor[0-4]/torrc"
mkdir -p "$IPCHANGER/.tor_multi"
# Ctrl+C (or the service stopping) takes the 5 Tor instances down with it.
trap 'kill $(jobs -p) 2>/dev/null' EXIT

for i in {0..4}; do
    TOR_DIR="$IPCHANGER/.tor_multi/tor$i"
    mkdir -p "$TOR_DIR"
    cat <<EOF > "$TOR_DIR/torrc"
SocksPort ${PORTS[$i]}
ControlPort ${CONTROL_PORTS[$i]}
DataDirectory $TOR_DIR
CookieAuthentication 0
Log notice file $TOR_DIR/tor.log
EOF
    if [[ -n "$BRIDGE_CONF" ]]; then printf '%s\n' "$BRIDGE_CONF" >> "$TOR_DIR/torrc"; fi
    # The service also makes instance 0 the transparent proxy used by `hide` (global mode + app jail).
    if [[ $i -eq 0 && -n "${IPCHANGER_TRANS_PORT:-}" ]]; then
        printf 'TransPort %s IsolateDestAddr\nDNSPort %s\n' "$IPCHANGER_TRANS_PORT" "$IPCHANGER_DNS_PORT" >> "$TOR_DIR/torrc"
    fi
    # Tor's own HTTP CONNECT proxy, for apps (Android's Wi-Fi proxy setting) that can't do SOCKS.
    if [[ $i -eq 0 && -n "${IPCHANGER_HTTP_PORT:-}" ]]; then echo "HTTPTunnelPort $IPCHANGER_HTTP_PORT" >> "$TOR_DIR/torrc"; fi
    : > "$TOR_DIR/tor.log"
    tor -f "$TOR_DIR/torrc" > /dev/null 2>&1 &
    sleep 2
    if ! kill -0 $! 2>/dev/null; then
        echo -e "${RED}Tor instance $((i + 1)) (port ${PORTS[$i]}) did not start:${RESET}" >&2
        grep -E '\[(warn|err)\]' "$TOR_DIR/tor.log" | tail -n 3 >&2
        # Instance 1 carries the IP check (and hide's TransPort/DNSPort): nothing works without it.
        [[ $i -eq 0 ]] && exit 1
    fi
done

while true; do
    echo -e "${YELLOW}Renewing Tor circuit to change IP...${RESET}"
    for ctrl_port in "${CONTROL_PORTS[@]}"; do
        echo -e "AUTHENTICATE \"\"\r\nSIGNAL NEWNYM\r\nQUIT" | nc 127.0.0.1 "$ctrl_port" > /dev/null 2>&1
    done

    # Check IP through first Tor instance
    NEW_IP=$(curl --socks5-hostname "127.0.0.1:${PORTS[0]}" -s --max-time 20 https://api64.ipify.org)
    if [[ -z "$NEW_IP" ]]; then
        echo -e "${RED}[!] Failed to get new IP. Retrying...${RESET}"
        sleep 5
        continue
    fi

    echo -e "${GREEN}New IP: $NEW_IP${RESET}"
    echo -e "${BLUE}Next IP change in $ROTATION_TIME seconds...${RESET}"
    echo -e "${CYAN}Available SOCKS5 proxies:${RESET}"
    printf '127.0.0.1:%s\n' "${PORTS[@]}"
    if [[ -n "${IPCHANGER_HTTP_PORT:-}" ]]; then echo -e "${CYAN}HTTPS proxy:${RESET} 127.0.0.1:$IPCHANGER_HTTP_PORT"; fi

    sleep "$ROTATION_TIME"
done
