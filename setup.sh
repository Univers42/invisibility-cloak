#!/usr/bin/env bash
# setup.sh — install "hide" on any Linux machine with systemd (Debian/Ubuntu, Fedora/RHEL,
# Arch, openSUSE…): ip-changer as a boot service (5 rotating Tor instances), kernel rules that
# send every app (global mode) or chosen apps (the jail) through Tor, WebRTC-safe browser
# policies, proxychains and desktop proxy settings. Re-running install is safe.
#   sudo ./setup.sh install [--global on|off] [--bridges snowflake|obfs4|off]
#                               a first install asks about global mode (off without a terminal)
#   sudo ./setup.sh uninstall   removes everything and restores what was there before
#   sudo ./setup.sh check       will hide work on this machine? changes nothing
#   sudo ./setup.sh deps [--bridges snowflake|obfs4]   only install the packages
# Settings: hide.conf, copied once to /etc/hide/hide.conf.  Then: hide-test.  Docs: docs/HIDE.md
set -euo pipefail

if ((BASH_VERSINFO[0] * 100 + BASH_VERSINFO[1] < 404)); then
    echo "setup.sh: needs bash 4.4 or newer (this is $BASH_VERSION)" >&2
    exit 1
fi
SELF=$(readlink -f "$0")
SRC=$(dirname "$SELF")
ARGS=("$@")
usage() {
    sed -n '2,11s/^# \{0,1\}//p' "$SELF" >&2
    exit 2
}
CMD=${1:-}
[ $# -eq 0 ] || shift
WANT_GLOBAL="" WANT_BRIDGES=""
while [ $# -gt 0 ]; do
    case "$1=${2:-}" in
        --global=on | --global=off) WANT_GLOBAL=$2 ;;
        --bridges=off | --bridges=snowflake | --bridges=obfs4) WANT_BRIDGES=$2 ;;
        *) usage ;;
    esac
    shift 2
done
case "$CMD" in install | uninstall | check | deps) ;; *) usage ;; esac

# The kernel rules and services need systemd: say so before touching anything.
if [ "$CMD" != deps ] && [ ! -d /run/systemd/system ]; then
    echo "setup.sh: hide needs systemd, and this machine runs $(cat /proc/1/comm 2>/dev/null || echo something else)." >&2
    echo "  The Tor engine alone works anywhere, even without root: ./ip-changer-linux.sh (README: level 0)" >&2
    exit 1
fi
[ "$(id -u)" -eq 0 ] || exec sudo "$SELF" "${ARGS[@]}"
USER_NAME=${SUDO_USER:-}
if [ "$CMD" = install ] || [ "$CMD" = uninstall ]; then
    if [ -z "$USER_NAME" ] || [ "$USER_NAME" = root ]; then
        echo "setup.sh: run it from your own account: sudo ./setup.sh $CMD" >&2
        exit 1
    fi
    USER_UID=$(id -u "$USER_NAME")
    USER_HOME=$(getent passwd "$USER_NAME" | cut -d: -f6)
fi

ENGINE=ipchanger
ETC=/etc/hide
SUDOERS=/etc/sudoers.d/hide
FIREFOX_POLICY=/etc/firefox/policies/policies.json
CHROME_POLICY_DIRS=(/etc/opt/chrome/policies/managed /etc/chromium/policies/managed
    /etc/chromium-browser/policies/managed /etc/brave/policies/managed)
# repo file -> installed path
FILES=(
    "ip-changer-linux.sh /usr/local/lib/ip-changer/ip-changer-linux.sh 755"
    "bridges/obfs4.txt /usr/local/lib/ip-changer/bridges/obfs4.txt 644"
    "bridges/snowflake.txt /usr/local/lib/ip-changer/bridges/snowflake.txt 644"
    "bin/hide /usr/local/bin/hide 755"
    "bin/hide-test /usr/local/bin/hide-test 755"
    "bin/global-proxy /usr/local/bin/global-proxy 755"
    "bin/hide-rescue /usr/local/bin/hide-rescue 755"
    "bin/hide-jail /usr/local/libexec/hide-jail 755"
    "systemd/ip-changer.service /etc/systemd/system/ip-changer.service 644"
    "systemd/hide.service /etc/systemd/system/hide.service 644"
    "docs/HIDE.md /usr/local/share/doc/hide/HIDE.md 644"
)
FIREFOX_PREFS='{
    "media.peerconnection.ice.proxy_only_if_behind_proxy": true,
    "media.peerconnection.ice.default_address_only": true,
    "media.peerconnection.ice.no_host": true,
    "network.proxy.allow_bypass": false,
    "network.proxy.failover_direct": false,
    "network.proxy.socks5_remote_dns": true
}'

say() { printf '\e[1m==> %s\e[0m\n' "$*"; }
conf_get() { [ ! -e "$ETC/hide.conf" ] || sed -n "s/^$1=//p" "$ETC/hide.conf" | tail -n1 | tr -d '"'; }
conf_set() { if grep -q "^$1=" "$ETC/hide.conf"; then sed -i "s|^$1=.*|$1=$2|" "$ETC/hide.conf"; else echo "$1=$2" >>"$ETC/hide.conf"; fi; }
as_user() {
    sudo -u "$USER_NAME" -H env XDG_RUNTIME_DIR="/run/user/$USER_UID" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$USER_UID/bus" "$@"
}

# mkdir -p that records each level it creates, so uninstall removes exactly those.
mkdirs() {
    local d=$1 missing=()
    while [ ! -d "$d" ]; do
        missing=("$d" "${missing[@]}")
        d=$(dirname "$d")
    done
    for d in "${missing[@]}"; do
        mkdir "$d"
        echo "$d" >>"$ETC/created-dirs"
    done
}

pm_install() {
    if command -v apt-get >/dev/null; then
        [ -n "${APT_UPDATED:-}" ] || apt-get update -q
        APT_UPDATED=1
        DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
    elif command -v dnf >/dev/null; then
        dnf install -y "$@"
    elif command -v pacman >/dev/null; then
        pacman -S --needed --noconfirm "$@"
    elif command -v zypper >/dev/null; then
        zypper --non-interactive install "$@"
    else
        return 1
    fi
}

have() {
    local c
    for c in "$@"; do command -v "$c" >/dev/null && return 0; done
    return 1
}

# packages [BRIDGES]: what hide needs, plus the program for each bridge transport in use.
packages() {
    local c absent=0 t p aur
    local -a bins pkgs ts=()
    for c in tor nft curl nc python3 ip ss nsenter setpriv sysctl pkill awk; do have "$c" || absent=1; done
    have proxychains4 proxychains || absent=1
    if [ "$absent" = 1 ]; then
        say "installing packages"
        if have apt-get; then
            pm_install tor proxychains4 nftables curl netcat-openbsd python3 iproute2 util-linux procps
        elif have dnf; then
            if ! pm_install tor proxychains-ng nftables curl nmap-ncat python3 iproute util-linux procps-ng gawk; then
                grep -qi '^ID=fedora' /etc/os-release || echo "setup.sh: on RHEL, Alma or Rocky tor comes from EPEL: dnf install epel-release, then re-run" >&2
                exit 1
            fi
        elif have pacman; then
            if ! pm_install tor proxychains-ng nftables curl openbsd-netcat python iproute2 util-linux procps-ng gawk; then
                echo "setup.sh: pacman failed; an out-of-date system is the usual reason: pacman -Syu, then re-run" >&2
                exit 1
            fi
        elif have zypper; then
            # openSUSE's minimal images have no awk at all.
            pm_install tor proxychains-ng nftables curl netcat-openbsd python3 iproute2 util-linux procps gawk
        else
            echo "setup.sh: no apt, dnf, pacman or zypper here: install tor, proxychains-ng, nftables, curl, netcat, python3, iproute2, util-linux, procps and gawk yourself, then re-run" >&2
            exit 1
        fi
    fi
    # A keyword is its transport; a file of bridge lines can mix several.
    case "${1:-}" in
        "" | off) ;;
        /*) mapfile -t ts < <(awk '!/^[[:space:]]*(#|$)/ && $1 !~ /[:.]/ {print $1}' "$1" | sort -u) ;;
        *) ts=("$1") ;;
    esac
    for t in "${ts[@]}"; do
        case $t in
            obfs4 | webtunnel) bins=(lyrebird obfs4proxy) pkgs=(lyrebird obfs4proxy obfs4) aur=lyrebird-proxy ;;
            snowflake) bins=(snowflake-client snowflake-pt-client) pkgs=(snowflake-client snowflake-pt-client snowflake) aur=snowflake-pt-client ;;
            *) continue ;;
        esac
        have "${bins[@]}" && continue
        # The package name differs between distros and releases: take the first that has the program.
        say "installing the $t bridge program"
        for p in "${pkgs[@]}"; do
            pm_install "$p" >/dev/null 2>&1 || true
            have "${bins[@]}" && continue 2
        done
        echo "setup.sh: no package here has ${bins[*]} for $t bridges: install it yourself, or pick other bridges" >&2
        # Arch ships no bridge program; the AUR does, and AUR helpers don't run as root.
        if have pacman; then echo "setup.sh: on Arch it's in the AUR: install $aur with your AUR helper, then re-run" >&2; fi
        exit 1
    done
}

# Will hide work here? Changes nothing. Problems that would break it fail; the rest are notes.
check() {
    local bad=0 p line who
    for p in nft ip ss sysctl; do
        have "$p" || { echo "setup.sh: '$p' is missing; first: sudo ./setup.sh deps" >&2 && return 1; }
    done
    say "checking this machine"
    "$SRC/bin/hide" check-rules || bad=1
    # The jail's way in: a namespace, entered with nsenter.
    if ip netns add hide-check 2>/dev/null && nsenter --net=/run/netns/hide-check -- true 2>/dev/null; then
        echo "jail: network namespaces work."
    else
        echo "jail: this machine can't create or enter a network namespace." >&2
        bad=1
    fi
    ip netns del hide-check 2>/dev/null || true
    # ip-changer's Tor: SOCKS 9050…9090, control 9051…9091, TransPort 9040, DNSPort 9053.
    for p in 9040 9053 9050 9051 9060 9061 9070 9071 9080 9081 9090 9091; do
        line=$(ss -Hlntup "sport = :$p" 2>/dev/null) || true
        [ -n "$line" ] || continue
        who=$(grep -o 'users:(("[^"]*' <<<"$line" | head -n1 | cut -d'"' -f2) || true
        [ "$who" = tor ] && continue # the distro's or ip-changer's own Tor: setup stops it
        echo "port $p: taken by ${who:-another program}, and hide's Tor needs it. Stop or move that program (Fedora's Cockpit holds 9090: systemctl disable --now cockpit.socket)." >&2
        bad=1
    done
    if grep -Eqs '^hosts:.*[[:space:]]resolve' /etc/nsswitch.conf || [ -S /run/nscd/socket ] || [ -S /var/run/nscd/socket ]; then
        echo "note: apps here look names up through a local socket (nss-resolve or nscd), which the jail can't redirect:"
        echo "      with global mode off, your DNS server sees the names jailed apps look up (not their traffic)."
    fi
    if { have ufw && ufw status 2>/dev/null | grep -q '^Status: active'; } || systemctl is-active --quiet firewalld 2>/dev/null; then
        echo "note: a firewall (ufw/firewalld) is on. In global mode, containers' and VMs' traffic is redirected to Tor"
        echo "      on this machine (TCP 9040, DNS 9053): if they go offline, allow those in from docker0/lxdbr0/virbr0."
    fi
    if [ "$bad" = 1 ]; then
        echo "check: hide can't work on this machine as it is (see above)." >&2
        return 1
    fi
    echo "check: OK"
}

# First install: global mode only if you say yes. --global decides without asking; so does an existing hide.conf.
choose_global() {
    local a=""
    [ -z "$WANT_GLOBAL" ] && [ ! -e "$ETC/hide.conf" ] || return 0
    WANT_GLOBAL=off
    [ -t 0 ] || return 0
    cat <<'EOF'

Global mode sends EVERY app, user and container on this machine through Tor, or nothing at all.
  + nothing can leak your real IP by accident: no proxy setting to forget, no app that ignores it
  - slower; some sites block Tor; UDP (games, calls), ping and IPv6 stop (your LAN still works)
  - while Tor can't connect you're offline (hide-rescue brings the internet back in seconds)
Without it, proxy-aware apps and the apps you jail (hide run, hide add) use Tor; the rest is direct.
EOF
    read -rp "Turn global mode on? You can change it any time: hide global on|off  [y/N] " a || true
    case "$a" in [yY]*) WANT_GLOBAL=on ;; esac
}

proxychains_conf() {
    local f=/etc/proxychains4.conf
    [ -e "$f" ] || f=/etc/proxychains.conf
    [ -e "$f.hide-bak" ] || [ ! -e "$f" ] || cp -p "$f" "$f.hide-bak"
    cat >"$f" <<EOF
# Written by hide's setup.sh — your original is $f.hide-bak (restored on uninstall).
# Each connection takes one of ip-changer's 5 Tor instances at random; DNS goes via Tor.
random_chain
chain_len = 1
proxy_dns
remote_dns_subnet 224
tcp_read_time_out 15000
tcp_connect_time_out 8000
# Apps talk to their own local helpers on 127.x (a debug port, a language server…): keep that
# local, or proxychains sends it into Tor and fails with "127.0.0.1:… <--socket error or timeout!".
localnet 127.0.0.0/255.0.0.0

[ProxyList]
socks5 127.0.0.1 9050
socks5 127.0.0.1 9060
socks5 127.0.0.1 9070
socks5 127.0.0.1 9080
socks5 127.0.0.1 9090
EOF
}

sudoers() {
    local tmp
    tmp=$(mktemp)
    # The command runs with your own uid (hide-jail drops root first), so sudo's pty relay
    # protects nothing and only gets between the app and its terminal.
    printf '%s\n' "# hide: enter the Tor jail without a password (this one root helper only)." \
        "$USER_NAME ALL=(root) NOPASSWD: /usr/local/libexec/hide-jail" \
        'Defaults!/usr/local/libexec/hide-jail !use_pty' >"$tmp"
    mkdirs "$(dirname "$SUDOERS")"
    if ! visudo -cqf "$tmp"; then
        rm -f "$tmp"
        echo "setup.sh: sudoers drop-in failed visudo -c" >&2
        exit 1
    fi
    install -m 0440 -o root -g root "$tmp" "$SUDOERS"
    rm -f "$tmp"
}

# Full paths: sudo's secure_path lacks /usr/local/bin on some distros (Fedora).
HIDE=/usr/local/bin/hide
GLOBAL_PROXY=/usr/local/bin/global-proxy
RESCUE=/usr/local/bin/hide-rescue

# Firefox: merge our locked prefs into policies.json (other policies are kept), or take
# them out again. The file goes away when nothing else is left in it.
firefox_policy() {
    python3 - "$1" "$FIREFOX_POLICY" "$FIREFOX_PREFS" <<'PY'
import json, os, sys
mode, path, ours = sys.argv[1], sys.argv[2], json.loads(sys.argv[3])
data = json.load(open(path)) if os.path.exists(path) else {}
pol = data.setdefault("policies", {})
prefs = pol.setdefault("Preferences", {})
for key, value in ours.items():
    if mode == "add":
        prefs[key] = {"Value": value, "Status": "locked"}
    else:
        prefs.pop(key, None)
if not prefs:
    del pol["Preferences"]
if not pol and list(data) == ["policies"]:
    if os.path.exists(path):
        os.remove(path)
    sys.exit(0)
with open(path + ".tmp", "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
os.chmod(path + ".tmp", 0o644)
os.replace(path + ".tmp", path)
PY
}

policies() {
    local d
    for d in "${CHROME_POLICY_DIRS[@]}"; do
        mkdirs "$d"
        printf '{ "WebRtcIPHandling": "disable_non_proxied_udp" }\n' >"$d/hide-webrtc.json"
        chmod 644 "$d/hide-webrtc.json"
    done
    mkdirs "$(dirname "$FIREFOX_POLICY")"
    firefox_policy add
}

# A firewall's own input rules would drop the jail's packets to Tor on 9040/9053.
# hide's table still limits hide0 to those two ports.
firewall() {
    if command -v ufw >/dev/null && ufw status 2>/dev/null | grep -q '^Status: active'; then
        if [ "$1" = open ]; then ufw allow in on hide0 comment hide >/dev/null; else ufw delete allow in on hide0 >/dev/null 2>&1 || true; fi
    fi
    if command -v firewall-cmd >/dev/null && firewall-cmd --state >/dev/null 2>&1; then
        local op=--add-interface
        [ "$1" = open ] || op=--remove-interface
        firewall-cmd --permanent --zone=trusted "$op=hide0" >/dev/null 2>&1 || true
        firewall-cmd --reload >/dev/null
    fi
}

install_all() {
    local f src dst mode u apps global up b tor_was_on=no

    choose_global
    b=${WANT_BRIDGES:-$(conf_get BRIDGES)}
    # Before the packages: Debian's tor package switches tor.service on as it installs.
    if systemctl is-enabled --quiet tor.service 2>/dev/null; then tor_was_on=yes; fi
    packages "$b"
    check || exit 1
    mkdir -p "$ETC"
    [ -e "$ETC/hide.conf" ] || install -m 644 "$SRC/hide.conf" "$ETC/hide.conf"
    if [ -n "$WANT_GLOBAL" ]; then conf_set GLOBAL "$WANT_GLOBAL"; fi
    if [ -n "$WANT_BRIDGES" ]; then
        [ "$b" != off ] || b=""
        conf_set BRIDGES "\"$b\""
    fi

    say "Tor engine: system user '$ENGINE' + ip-changer.service"
    # The distro's own Tor would hold port 9050 (Debian's tor.service also pulls tor@default).
    if [ "$tor_was_on" = yes ]; then touch "$ETC/reenable-tor"; fi
    systemctl disable --quiet tor.service 2>/dev/null || true
    systemctl stop tor.service tor@default.service 2>/dev/null || true
    getent passwd "$ENGINE" >/dev/null ||
        useradd --system --user-group --no-create-home --home-dir /var/lib/ip-changer \
            --shell "$(command -v nologin || echo /usr/sbin/nologin)" "$ENGINE"
    for f in "${FILES[@]}"; do
        read -r src dst mode <<<"$f"
        mkdirs "$(dirname "$dst")"
        install -m "$mode" -o root -g root "$SRC/$src" "$dst"
    done

    say "proxychains, sudoers, browser policies, firewall"
    proxychains_conf
    sudoers
    policies
    firewall open

    say "starting hide.service (kernel rules + jail) and ip-changer.service"
    if pkill -u "$USER_NAME" -f "/\.tor_multi/tor[0-4]/torrc"; then
        echo "   stopped the Tor that ip-changer ran as $USER_NAME; if it still runs in a terminal, Ctrl+C it."
    fi
    # Global mode can cut this machine off (it did once: DNS). Safety net first, then prove it.
    global=$(conf_get GLOBAL)
    if [ "$global" != off ]; then "$RESCUE" --in 10m; fi
    systemctl daemon-reload
    systemctl enable --quiet hide.service ip-changer.service
    systemctl reload-or-restart hide.service
    systemctl restart ip-changer.service
    if [ "$global" != off ]; then
        say "global mode: waiting for Tor to answer with no proxy set (up to ~4 min)"
        up=no
        for _ in $(seq 18); do
            if curl -s --noproxy '*' --max-time 10 https://check.torproject.org/api/ip | grep -q '"IsTor":true'; then up=yes; break; fi
            sleep 5
        done
        if [ "$up" = yes ]; then
            "$RESCUE" --cancel >/dev/null
            echo "   works: this machine reaches the internet only through Tor."
        else
            echo "   NOT working yet: global mode turns itself off in 10 min (hide-rescue)." >&2
            echo "   If Tor comes up first and hide-test passes: hide-rescue --cancel" >&2
        fi
    fi

    say "desktop + Firefox proxy settings (global-proxy on)"
    as_user "$GLOBAL_PROXY" on || echo "   warning: global-proxy on failed; run it yourself later"

    apps=$(conf_get APPS)
    if [ -z "$apps" ] && [ -t 0 ]; then
        say "apps to always start inside the Tor jail"
        as_user "$HIDE" add
        read -rp "Names from the list (space-separated, Enter = none): " apps
        apps=$(tr -cd 'A-Za-z0-9._ -' <<<"$apps")
        if [ -n "$apps" ]; then conf_set APPS "\"$apps\""; fi
    fi
    for u in $apps; do as_user "$HIDE" add "$u" || echo "   warning: couldn't jail '$u'"; done

    say "done"
    as_user "$HIDE" status
    if [ "$global" = off ]; then echo "Global mode is off: proxy-aware and jailed apps use Tor. Everything: hide global on"; fi
    echo "Verify: hide-test   (give Tor 2 minutes to connect first; more: hide-test --rotation --full)"
    echo "Offline after a change? hide-rescue  (puts the internet back, needs no network)"
}

uninstall_all() {
    local f src dst mode u
    say "removing hide"
    if [ -x "$HIDE" ]; then as_user "$HIDE" remove --all || true; fi
    if [ -x "$GLOBAL_PROXY" ]; then as_user "$GLOBAL_PROXY" off || true; fi
    as_user find "$USER_HOME/.config/hide" -depth -type d -empty -delete 2>/dev/null || true
    systemctl disable --now ip-changer.service hide.service >/dev/null 2>&1 || true
    if [ -x "$HIDE" ]; then "$HIDE" teardown; fi
    firewall close
    for f in "${FILES[@]}"; do
        read -r src dst mode <<<"$f"
        rm -f "$dst"
    done
    systemctl daemon-reload
    rm -f "$SUDOERS"
    for f in "${CHROME_POLICY_DIRS[@]}"; do rm -f "$f/hide-webrtc.json"; done
    # No file, nothing of ours in it (and python3 may be missing after a failed install).
    if [ -f "$FIREFOX_POLICY" ]; then firefox_policy remove; fi
    for f in /etc/proxychains4.conf /etc/proxychains.conf; do
        if [ -e "$f.hide-bak" ]; then mv "$f.hide-bak" "$f"; fi
    done
    if [ -f "$ETC/created-dirs" ]; then
        tac "$ETC/created-dirs" | while read -r f; do rmdir "$f" 2>/dev/null || true; done
    fi
    if getent passwd "$ENGINE" >/dev/null; then userdel "$ENGINE"; fi
    if getent group "$ENGINE" >/dev/null; then groupdel "$ENGINE"; fi
    rm -rf /var/lib/ip-changer
    if [ -f "$ETC/reenable-tor" ]; then systemctl enable --quiet --now tor.service || true; fi
    rm -rf "$ETC"
    say "removed; your previous proxychains config and Tor service are back"
}

case "$CMD" in
install) install_all ;;
uninstall) uninstall_all ;;
check) check ;;
deps) packages "$WANT_BRIDGES" ;;
esac
