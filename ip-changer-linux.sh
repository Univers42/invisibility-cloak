#!/bin/bash
IPCHANGER="${IPCHANGER_DIR:-/usr/share/ip-changer}"
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
MAGENTA="\e[35m"
CYAN="\e[36m"
WHITE="\e[37m"
RESET="\e[0m"

printf "
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

# setup.sh runs ip-changer as a boot service; a second copy would only fight it for the ports.
if [[ -z "${INVOCATION_ID:-}" ]] && systemctl is-active --quiet ip-changer 2>/dev/null; then
    echo -e "${YELLOW}ip-changer already runs as a service. Live log: journalctl -fu ip-changer${RESET}"
    exit 0
fi

# Check if Tor is installed
if ! command -v tor &> /dev/null; then
    echo -e "${RED}Tor is not installed. Please install it first:${RESET}"
    echo -e "${BLUE}sudo apt-get install tor${RESET}"
    exit 1
fi

printf "Starting multitor service...\n"
pkill -x tor
mkdir -p "$IPCHANGER/.tor_multi"

PORTS=(9050 9060 9070 9080 9090)
CONTROL_PORTS=(9051 9061 9071 9081 9091)

for i in {0..4}; do
    TOR_DIR="$IPCHANGER/.tor_multi/tor$i"
    mkdir -p "$TOR_DIR"
    cat <<EOF > "$TOR_DIR/torrc"
SocksPort ${PORTS[$i]}
ControlPort ${CONTROL_PORTS[$i]}
DataDirectory $TOR_DIR
CookieAuthentication 0
EOF
    # The service also makes instance 0 the transparent proxy used by `hide` (global mode + app jail).
    if [[ $i -eq 0 && -n "${IPCHANGER_TRANS_PORT:-}" ]]; then
        printf 'TransPort %s IsolateDestAddr\nDNSPort %s\n' "$IPCHANGER_TRANS_PORT" "$IPCHANGER_DNS_PORT" >> "$TOR_DIR/torrc"
    fi
    tor -f "$TOR_DIR/torrc" > /dev/null 2>&1 &
    sleep 2
done

while true; do
    echo -e "${YELLOW}Renewing Tor circuit to change IP...${RESET}"
    for ctrl_port in "${CONTROL_PORTS[@]}"; do
        echo -e "AUTHENTICATE \"\"\r\nSIGNAL NEWNYM\r\nQUIT" | nc 127.0.0.1 $ctrl_port > /dev/null 2>&1
    done

    # Check IP through first Tor instance
    NEW_IP=$(curl --socks5-hostname 127.0.0.1:9050 -s https://api64.ipify.org)
    if [[ -z "$NEW_IP" ]]; then
        echo -e "${RED}[!] Failed to get new IP. Retrying...${RESET}"
        sleep 5
        continue
    fi

    echo -e "${GREEN}New IP: $NEW_IP${RESET}"
    echo -e "${BLUE}Next IP change in $ROTATION_TIME seconds...${RESET}"
    echo -e "${CYAN}Available SOCKS5 proxies:${RESET}"
    echo -e "127.0.0.1:9050\n127.0.0.1:9060\n127.0.0.1:9070\n127.0.0.1:9080\n127.0.0.1:9090"

    sleep "$ROTATION_TIME"
done
