#!/usr/bin/env bash
# installer.sh — invisibility-cloak in one line:
#   curl -fsSL https://raw.githubusercontent.com/Univers42/invisibility-cloak/main/installer.sh | bash
#   … | bash -s -- --global off        (setup.sh install options go after "--")
# Linux with systemd: downloads the repo to ~/.local/share/invisibility-cloak and runs
#   sudo ./setup.sh install from there (it asks before turning global mode on).
# Termux (Android, no root): installs the Tor engine alone, as the command `ip-changer`.
# Run it again to update.
set -euo pipefail

TARBALL=https://codeload.github.com/Univers42/invisibility-cloak/tar.gz/refs/heads/main

say() { printf '\033[1;36m==> %s\033[0m\n' "$*"; }
die() {
    printf '\033[1;31minstaller: %s\033[0m\n' "$*" >&2
    exit 1
}

# download DIR: the repo's current files into DIR (a previous copy is replaced).
download() {
    local tmp
    if [ -e "$1" ] && [ ! -f "$1/setup.sh" ]; then die "$1 exists and isn't invisibility-cloak: move it away first"; fi
    say "downloading invisibility-cloak into $1"
    tmp=$(mktemp -d)
    curl -fsSL "$TARBALL" | tar -xz --strip-components=1 -C "$tmp" || die "download failed: check your connection and re-run"
    rm -rf "$1"
    mkdir -p "$(dirname "$1")"
    mv "$tmp" "$1"
}

if [ -d /data/data/com.termux/files/usr ]; then
    # ip-changer.sh keeps its Tor and privoxy state next to itself: it has to live here.
    PREFIX=${PREFIX:-/data/data/com.termux/files/usr}
    dir=$PREFIX/share/ip-changer
    say "Termux: installing tor, privoxy, curl, netcat"
    pkg install -y tor privoxy curl netcat-openbsd
    download "$dir"
    printf '#!%s/bin/bash\ncd "%s" && exec bash ip-changer.sh "$@"\n' "$PREFIX" "$dir" >"$PREFIX/bin/ip-changer"
    chmod 755 "$PREFIX/bin/ip-changer"
    say "done: run ip-changer, then point apps at the HTTP proxy 127.0.0.1:8118 (privoxy → Tor)"
    exit 0
fi

[ "$(id -u)" -ne 0 ] || die "run it as yourself, not as root: it asks for sudo when it needs it"
download "${XDG_DATA_HOME:-$HOME/.local/share}/invisibility-cloak"
cd "${XDG_DATA_HOME:-$HOME/.local/share}/invisibility-cloak"
say "running sudo ./setup.sh install $*"
# Under "curl … | bash" stdin is the script itself: give setup.sh the terminal so it can ask.
if { : </dev/tty; } 2>/dev/null; then exec sudo ./setup.sh install "$@" </dev/tty; fi
exec sudo ./setup.sh install "$@"
