# 🧥 invisibility-cloak

> Throw a cloak of Tor over your whole Linux machine. Every app goes through Tor, or it
> doesn't go anywhere. There's no "oops, that one went direct".

[![CI](https://github.com/Univers42/invisibility-cloak/actions/workflows/ci.yml/badge.svg)](https://github.com/Univers42/invisibility-cloak/actions/workflows/ci.yml)
![License](https://img.shields.io/badge/license-BSD--3--Clause-blue)
![Tor](https://img.shields.io/badge/Tor-7D4698?logo=torproject&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-systemd-FCC624?logo=linux&logoColor=black)
![Termux](https://img.shields.io/badge/Termux-level%200-000000?logo=android&logoColor=white)

Most "use Tor" setups ask every app nicely to use a proxy, and hope it listens. Some apps
don't listen: WebRTC in your browser, a DNS lookup, a desktop app with its own network
code, `sudo apt` and the Docker container you forgot about. invisibility-cloak doesn't ask.
It tells the **kernel** to send the traffic to Tor, and to **drop** whatever Tor can't carry.
If Tor is down, you're offline, not exposed.

Under the hood: 5 Tor instances, each with a new exit IP every 30 seconds, started at boot.
On top of them sit nftables rules, a network-namespace jail, and browser policies that keep
WebRTC from blurting out your address.

## 🎚️ Pick your level

| | Level | What you get | Needs |
|---|---|---|---|
| 🧦 | **0 · ip-changer** | 5 rotating Tor SOCKS proxies. Point an app at them yourself | no root: any Linux, Android (Termux) |
| 🥷 | **1 · the jail** | apps you pick (`hide add discord`) can *only* reach the internet through Tor. Everything else stays normal | root, systemd |
| 🧥 | **2 · global mode** | **every** app, user, root and container goes through Tor, or nothing does | root, systemd |

Levels 1 and 2 come from the same install: global mode is one switch away (`hide global on|off`).

```
                  ┌──────────────────────────── your machine ───────────────────────────┐
 Firefox, Chrome ─┼─► SOCKS 9050…9090 ───┐                                              │
 hide run <app>  ─┼─► 🥷 jail (netns) ───┼─► 🧅 Tor ×5 ─────────────────────────────────┼──► 🌍
 everything else ─┼─► 🧥 global mode ────┘    new exit every 30 s                       │
  (global on)     │      UDP, ICMP, IPv6 ──► ✋ dropped (fail-closed)                   │
                  └─────────────────────────────────────────────────────────────────────┘
```

## ⚡ 60-second install

```bash
curl -fsSL https://raw.githubusercontent.com/Univers42/invisibility-cloak/main/installer.sh | bash
```

That downloads the repo to `~/.local/share/invisibility-cloak` and runs `sudo ./setup.sh install`
from there. Piping a script into bash means trusting it: [read installer.sh](installer.sh)
first, it's 50 lines. Options go after `--`: `… | bash -s -- --global on`.

Or the classic way:

```bash
git clone https://github.com/Univers42/invisibility-cloak.git
cd invisibility-cloak
sudo ./setup.sh check      # dry run: will it work on this machine? changes nothing
sudo ./setup.sh install    # installs packages + services, asks about global mode (default: no)
```

Setup speaks apt, dnf, pacman and zypper. Run it again any time: it's safe, and that's how
you update. Your `/etc/hide/hide.conf` is never overwritten.

## 🔍 Did it work?

```console
$ hide-test

1. Engine
  PASS hide.service active
  PASS ip-changer.service active
  PASS tcp 9050 listening, owned by ipchanger
  …
4. Tor jail (hide run / jailed launchers)
  PASS hide run curl → Tor exit <a Tor exit IP>
  PASS STUN (WebRTC-style UDP) gets nothing (blocked); the probe's local control got its reply
  PASS LAN (your router) unreachable from the jail
  …
5. Global mode (on)
  PASS root, no proxy settings → Tor exit <a Tor exit IP>
  PASS DNS to any server is answered by Tor (query to unroutable 192.0.2.1 answered)
  PASS all 6 live internet connection(s) of your apps go through Tor (firefox,ssh,…)
  …
40 passed, 0 failed, 0 warnings, 0 skipped
```

hide-test **never looks up your real IP**. A pass means `check.torproject.org` answered
`"IsTor":true`, and a Tor exit is by definition not you. Want more? `hide-test --rotation`
watches the exit change. `hide-test --full` stops Tor and checks that everything now
*fails* instead of going direct. `hide-test --docker` checks a container too.

## 🕹️ Everyday commands

| Command | What it does |
|---|---|
| `hide` | what's on, and whether Tor answers |
| `hide global on` / `off` | the whole machine through Tor, or back to normal |
| `hide run firefox` | run one command inside the Tor jail |
| `hide add` / `hide add discord` | list your apps / make one always start in the jail |
| `hide remove discord` | undo that |
| `hide bridges obfs4` | your network blocks Tor? Sneak in (see below) |
| `hide-test` | prove it works |
| `journalctl -fu ip-changer` | watch Tor's log live |

## 🚨 Help, I'm offline!

> ```bash
> hide-rescue
> ```
> Your internet is back in seconds, **with no network needed**. It turns global mode off,
> removes the kernel rules, resets DNS, and restarts your network service if it has to.
> Browsers still can't load anything? `hide-rescue --direct` also turns their proxy off.
>
> About to try something risky? `hide-rescue --in 5m` arms a timer that rescues you
> by itself unless you `hide-rescue --cancel` it. setup.sh does this for you whenever it
> turns global mode on.

## 💔 What global mode breaks

Honesty corner. Global mode is strict on purpose, so:

- **Sites that hate Tor:** some banks, streaming services, shops and even claude.ai's web app
  answer with a 403 or an endless captcha. Do a `hide global off`, do your thing, then
  `hide global on`.
- **Anything that needs UDP:** voice and video calls (they fall back to TCP or fail),
  online games, WireGuard/OpenVPN over UDP, and NTP (your clock drifts slowly).
- **Captive-portal Wi-Fi** (hotels, trains): turn global mode off to log in.
- **Speed:** everything takes the scenic route through 3 relays. Seconds, not milliseconds.
- **Boards without a clock battery** (Raspberry Pi): they boot in the past, and Tor won't
  start until the clock is right. Keep global mode off on those, or set the time first.

The full list, and the reasons behind it: [docs/HIDE.md](docs/HIDE.md#what-global-mode-breaks-honest-list).

## 🧱 Censored network?

Some countries, schools and offices block Tor. Bridges hide the fact that you're using it:

```bash
hide bridges obfs4        # looks like random noise
hide bridges snowflake    # looks like a video call
hide bridges ~/my-bridges.txt   # private lines from https://bridges.torproject.org
hide bridges off
```

If Tor won't start with the new bridges, the old setting comes back by itself. The program
each one needs is installed by `sudo ./setup.sh install --bridges obfs4` (or `snowflake`).
Two exceptions: Arch has them in the AUR only (`lyrebird-proxy`, `snowflake-pt-client`:
install one with your AUR helper first), and Fedora and openSUSE have no snowflake client
package (obfs4 works; openSUSE's `snowflake` package is the volunteer proxy, not the client).

## 🐧 Works on

Any Linux with **systemd**, **nftables ≥ 0.9.3** and **kernel ≥ 5.2**. `sudo ./setup.sh check`
tells you before anything gets installed.

| Distro | Status |
|---|---|
| Ubuntu 24.04 (KDE desktop) | ✅ in daily use, `hide-test`: 40 passed |
| Debian 13, Ubuntu 24.04, Fedora 44, Arch, openSUSE Tumbleweed | ✅ tested in containers running systemd: install, `hide-test` with global mode off and on, uninstall |
| Debian 13, Ubuntu 24.04, Fedora 43, Arch, openSUSE Tumbleweed in LXD (unprivileged containers) | ✅ the same tests, and the jail survives systemd-networkd reloads (openSUSE doesn't run networkd) |
| Other releases and relatives (Mint, Pop!_OS, Manjaro…) | 🤞 should work: `setup.sh check` tells you |
| RHEL, Alma, Rocky | 🤞 needs EPEL for `tor`; setup tells you |
| Alpine, Void, Gentoo/OpenRC, other systems without systemd | ❌ setup refuses before changing anything; use level 0 |
| Android | 🧦 level 0 only, through Termux |

The containers test the scripts and the kernel rules, not a desktop: browsers and the
KDE/GNOME proxy settings were only tried on the Ubuntu desktop.
On Arch the obfs4 program came from Tor's own expert bundle, standing in for the AUR package.

## 🕵️ What it hides, and what it doesn't

| ✅ Hidden from websites and apps | ❌ Not hidden: that's on you |
|---|---|
| your IP address, also in WebRTC | **who** you are: logins, cookies, browser fingerprint, what you write |
| your DNS lookups (Tor resolves them) | an app that's hostile on purpose and gets root |
| your LAN, router and public address, from jailed apps | anything if your account has `NOPASSWD: ALL` sudo: any app can turn hide off |
| containers' and VMs' traffic (global mode, NAT networking) | membership in the `docker`/`lxd` groups, which is root by another name |
| | VMs on a *bridged* adapter and macvlan containers: they skip the host's firewall |

Tor hides **where** you are, not **who** you are. If you log into your account, the site
knows it's you, whatever IP you come from.

## 🧦 No root? Android?

**Linux, no root (level 0):** you only need `tor`, `curl` and `nc` (netcat).

```bash
bash ip-changer-linux.sh -r 15    # 5 SOCKS proxies, new exits every 15 s
curl --socks5-hostname 127.0.0.1:9050 https://check.torproject.org/api/ip
```

The proxies are `127.0.0.1:9050`, `9060`, `9070`, `9080` and `9090`. Point your browser at one,
or use `proxychains4`. Ctrl+C stops everything.

**Android (Termux):** the same one-liner installs the original ip-changer, with Tor and an
HTTP proxy:

```bash
curl -fsSL https://raw.githubusercontent.com/Univers42/invisibility-cloak/main/installer.sh | bash
ip-changer -r 15                  # then set apps' HTTP proxy to 127.0.0.1:8118
```

(The Termux path is written but not tested on a real phone yet. Reports welcome.)

## 🧹 Uninstall

```bash
cd ~/.local/share/invisibility-cloak    # or wherever you cloned it
sudo ./setup.sh uninstall
```

It removes the services, rules, policies and the `ipchanger` user, and restores the
configs it changed: proxychains, Firefox policies, your desktop proxy, and your distro's
own Tor service if that was running before.

## ❓ FAQ

**Is this legal?** Using Tor is legal in most countries. A few restrict or block it, and
what you *do* through Tor is still covered by the law where you are. Check your local rules.

**Does this make me anonymous?** It makes you *harder to locate*. Anonymity also depends on
your habits: see the table above.

**Why is everything slower?** Your traffic hops through 3 volunteer relays around the
world. That's the price of the cloak.

**Why 5 Tor instances?** Firefox spreads its tabs over them (and proxychains its
connections), so one slow circuit doesn't stall everything, and sites see different exits.

**Can I use a VPN too?** A VPN over TCP works in global mode; it then runs *inside* Tor.
UDP VPNs (WireGuard) are blocked by global mode.

**Tor inside a container, on a cloaked host?** That's Tor over Tor, and Tor exit relays
refuse to connect to other relays: the inner Tor stays stuck at 10%. Give it bridges, which
aren't public relays: `--bridges obfs4`.

**Something's broken.** Run `hide-rescue` first, then `hide-test`, then read the
[troubleshooting table](docs/HIDE.md#troubleshooting). Still stuck? Open an issue with the
`hide-test` output. It contains no real IPs.

## 🙏 Credits & license

invisibility-cloak grew out of [ip-changer](https://github.com/Anon4You/Ip-Changer) by
Alienkrishn (Anon4You), which still powers level 0 and the Termux install. This fork adds the
kernel rules, the jail, setup and the tests; the original author doesn't endorse it.

BSD 3-Clause, see [LICENSE](LICENSE). The bridge lists in `bridges/` come from Tor Browser.

**Deep dive:** how every rule works, every limit, every file installed: [docs/HIDE.md](docs/HIDE.md).
