#!/usr/bin/env bash
# setup.sh install|uninstall — install "hide" the same way on any Linux device:
# ip-changer as a boot service (5 rotating Tor instances), kernel rules that force every
# app (GLOBAL=on) or chosen apps (the jail) through Tor, WebRTC-safe browser policies,
# proxychains and desktop proxy settings. Re-running install is safe.
#   sudo ./setup.sh install      settings: hide.conf (copied once to /etc/hide/hide.conf)
#   sudo ./setup.sh uninstall    removes everything and restores what was there before
# Then check it: hide-test.  How it works: docs/HIDE.md
set -euo pipefail

SELF=$(readlink -f "$0")
SRC=$(dirname "$SELF")
[ "$(id -u)" -eq 0 ] || exec sudo "$SELF" "$@"
USER_NAME=${SUDO_USER:-}
if [ -z "$USER_NAME" ] || [ "$USER_NAME" = root ]; then
    echo "setup.sh: run it from your own account: sudo ./setup.sh ${1:-install}" >&2
    exit 1
fi
USER_UID=$(id -u "$USER_NAME")
USER_HOME=$(getent passwd "$USER_NAME" | cut -d: -f6)

ENGINE=ipchanger
ETC=/etc/hide
SUDOERS=/etc/sudoers.d/hide
FIREFOX_POLICY=/etc/firefox/policies/policies.json
CHROME_POLICY_DIRS=(/etc/opt/chrome/policies/managed /etc/chromium/policies/managed
    /etc/chromium-browser/policies/managed /etc/brave/policies/managed)
# repo file -> installed path
FILES=(
    "ip-changer-linux.sh /usr/local/lib/ip-changer/ip-changer-linux.sh 755"
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

packages() {
    local c absent=0
    for c in tor nft curl nc python3 ip ss nsenter setpriv; do command -v "$c" >/dev/null || absent=1; done
    command -v proxychains4 >/dev/null || command -v proxychains >/dev/null || absent=1
    [ "$absent" = 1 ] || return 0
    say "installing packages"
    if command -v apt-get >/dev/null; then
        apt-get update -q
        DEBIAN_FRONTEND=noninteractive apt-get install -y tor proxychains4 nftables curl netcat-openbsd python3 iproute2 util-linux
    elif command -v dnf >/dev/null; then
        dnf install -y tor proxychains-ng nftables curl nmap-ncat python3 iproute util-linux
    elif command -v pacman >/dev/null; then
        pacman -S --needed --noconfirm tor proxychains-ng nftables curl openbsd-netcat python iproute2 util-linux
    else
        echo "setup.sh: no apt, dnf or pacman: install tor, proxychains-ng, nftables, curl, netcat, python3, iproute2, util-linux yourself" >&2
        exit 1
    fi
}

proxychains_conf() {
    local f=/etc/proxychains4.conf
    [ -e "$f" ] || f=/etc/proxychains.conf
    [ -e "$f.hide-bak" ] || cp -p "$f" "$f.hide-bak"
    cat >"$f" <<EOF
# Written by hide's setup.sh — your original is $f.hide-bak (restored on uninstall).
# Each connection takes one of ip-changer's 5 Tor instances at random; DNS goes via Tor.
random_chain
chain_len = 1
proxy_dns
remote_dns_subnet 224
tcp_read_time_out 15000
tcp_connect_time_out 8000
# Apps talk to their own local helpers on 127.x: keep that local, not sent into Tor
# (that was the "127.0.0.1:49374 <--socket error or timeout!" failure).
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
    local f src dst mode u apps global up

    packages
    mkdir -p "$ETC"
    [ -e "$ETC/hide.conf" ] || install -m 644 "$SRC/hide.conf" "$ETC/hide.conf"

    say "Tor engine: system user '$ENGINE' + ip-changer.service"
    # The distro's own Tor would hold port 9050 (Debian's tor.service also pulls tor@default).
    if systemctl is-enabled --quiet tor.service 2>/dev/null; then
        touch "$ETC/reenable-tor"
        systemctl disable --quiet tor.service
    fi
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
    if pkill -u "$USER_NAME" -x tor; then
        echo "   stopped the Tor that ip-changer ran as $USER_NAME; if it still runs in a terminal, Ctrl+C it."
    fi
    # Global mode can cut this machine off (it did once: DNS). Safety net first, then prove it.
    global=$(sed -n 's/^GLOBAL=//p' "$ETC/hide.conf" | tail -n1)
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

    apps=$(sed -n 's/^APPS=//p' "$ETC/hide.conf" | tail -n1 | tr -d '"')
    if [ -z "$apps" ] && [ -t 0 ]; then
        say "apps to always start inside the Tor jail"
        as_user "$HIDE" add
        read -rp "Names from the list (space-separated, Enter = none): " apps
        apps=$(tr -cd 'A-Za-z0-9._ -' <<<"$apps")
        if [ -n "$apps" ]; then
            if grep -q '^APPS=' "$ETC/hide.conf"; then sed -i "s/^APPS=.*/APPS=\"$apps\"/" "$ETC/hide.conf"; else echo "APPS=\"$apps\"" >>"$ETC/hide.conf"; fi
        fi
    fi
    for u in $apps; do as_user "$HIDE" add "$u" || echo "   warning: couldn't jail '$u'"; done

    say "done"
    as_user "$HIDE" status
    echo "Verify: hide-test   (more: hide-test --rotation --full)"
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
    firefox_policy remove
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

case "${1:-}" in
install) install_all ;;
uninstall) uninstall_all ;;
*)
    sed -n '2,8s/^# \{0,1\}//p' "$SELF" >&2
    exit 2
    ;;
esac
