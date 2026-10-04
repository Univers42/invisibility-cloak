# hide — keep your real IP away from apps and websites

`hide` builds on ip-changer (5 Tor instances whose exit IP rotates every few seconds)
and makes it **enforced by the kernel**, not something each app has to agree to.

```
sudo ./setup.sh install      # same command on every Linux device (apt, dnf or pacman)
hide-test                    # proves it works; exit code 0 = every check passed
sudo ./setup.sh uninstall    # removes everything, restores what was there before
```

Everything is driven by one file, `hide.conf` (copied once to `/etc/hide/hide.conf`):

| Setting | Meaning |
|---|---|
| `GLOBAL=on` | every app, user (root too) and container reaches the internet only through Tor |
| `GLOBAL=off` | only jailed apps (`hide run`, `hide add`) and proxy-aware apps use Tor |
| `ROTATE=30` | seconds between new Tor exits |
| `APPS="…"` | launchers that always start inside the Tor jail |

## Commands

| Command | What it does |
|---|---|
| `hide` | status: engine, rules, global mode, current Tor exit, jailed apps |
| `hide global on\|off` | switch global mode (asks for sudo, takes effect at once) |
| `hide run <cmd> [args…]` | run one command inside the Tor jail, as you |
| `hide add` | list the apps installed on this machine |
| `hide add <app>` | that app's menu entry and autostart always start it inside the jail |
| `hide remove <app>\|--all` | undo `hide add` |
| `global-proxy on\|off` | point KDE/GNOME/Chrome/Firefox proxy settings at Tor (setup turns it on) |
| `hide-test [--rotation] [--full] [--docker]` | self-test, see below |
| `hide-rescue [--direct]` | **internet back now**, whatever state hide is in: global off, its rules removed, DNS reset, NetworkManager restarted if still offline. `--direct` also turns the proxy settings off (browsers go direct). Needs no network |
| `hide-rescue --in 5m` / `--cancel` | safety net before a risky change: rescue runs by itself in 5 min unless cancelled |
| `journalctl -fu ip-changer` | live log of the Tor engine |

## How it works

### 1. The engine — `ip-changer.service`

ip-changer runs at boot as the system user `ipchanger` (no login shell; its script is
root-owned in `/usr/local/lib/ip-changer/`, so that user can't change its own code).

- 5 Tor instances: SOCKS ports 9050, 9060, 9070, 9080, 9090. Every `ROTATE` seconds
  each is told `NEWNYM`, so new connections leave from a different exit.
- Instance 0 also opens a **TransPort** (9040) and a **DNSPort** (9053). The kernel
  rules below redirect ordinary traffic into these two, so apps need no proxy setting.
- Its own traffic is the only traffic allowed to leave directly: the kernel rules
  exempt the `ipchanger` uid. Without that Tor would be sent into itself.

### 2. Global mode — nftables table `inet hide` (`GLOBAL=on`)

`hide.service` runs `hide apply` before the network comes up (`network-pre.target`).
It loads one nftables table, atomically:

| Traffic | What happens |
|---|---|
| TCP to the internet, any user | sent to Tor's TransPort 9040 |
| DNS (port 53) to *any* server, LAN routers included | sent to Tor's DNSPort 9053 |
| Any other UDP (QUIC, STUN/WebRTC, NTP, games, VPNs), ICMP, global IPv6 | dropped. Local programs get `EPERM`, so they fail at once instead of hanging |
| UPnP (1900) / NAT-PMP (5351) to your router | dropped. Those protocols hand out your public IP |
| Containers and VMs (bridge, veth, vxlan: Docker, k8s, libvirt) | TCP and DNS redirected the same way; anything else forwarded to the internet is dropped |
| Loopback, LAN, Docker networks, multicast | untouched: printers, NAS and local dev keep working |
| Tor's control ports (9051…9091) | only the `ipchanger` user may connect. Otherwise any app could tell Tor to use an attacker's bridge and learn your IP |

The rules **fail closed**. If Tor is down, traffic stops; it never falls back to your
real address. Connections that were already open when you switched to global mode are cut.

"Sent to" means DNAT to **this machine's own address on the outgoing card**
(`dnat ip to ip saddr : 9053`), not `redirect` (which means 127.0.0.1). systemd-resolved
pins its upstream DNS sockets to the network card (`SO_BINDTOIFINDEX`); a packet pinned
to `enp7s0` and redirected to 127.0.0.1 is routed out of the card and lost, so every name
lookup on the machine failed. `hide-test` checks this with a pinned socket.

### 3. The app jail — `hide run`, `hide add` (works in both modes)

A Linux **network namespace** named `hide` is connected to the host by a virtual cable:
`hide0` (10.233.233.1) on the host and `hide1` (10.233.233.2) in the jail.

- Inside, an app sees only `lo` and `10.233.233.2`. It cannot read your LAN or public
  address, it has no IPv6, and it cannot reach your LAN or router.
- Everything the jail sends is redirected to Tor on the host side: TCP → 9040, DNS → 9053.
- DNS: `/etc/resolv.conf` says `127.0.0.53`, which inside the jail is the jail's own
  loopback. A rule inside the jail forwards those queries to Tor's DNSPort. This also
  works for snaps, which ignore mount tricks.
- Proxy settings: `global-proxy` points browsers and Electron apps at `127.0.0.1:9050`,
  which is also the jail's own loopback. The jail forwards the 5 SOCKS ports to Tor on
  the host (`route_localnet` on `hide0`). Tor's control ports are not forwarded.
- **Fail closed twice.** A routing rule (`ip rule iif hide0 lookup 233` → `unreachable`)
  means jail packets can never be forwarded to the internet, even if every nftables
  rule is flushed. The firewall also drops them.
- The app keeps its own private `localhost`. Your proxychains error
  `127.0.0.1:49374 <--socket error or timeout!` was proxychains sending the app's own
  localhost traffic into Tor. That cannot happen in the jail.

**How a command enters the jail**

1. `hide run` writes your environment and command to a private file (mode 600 in
   `$XDG_RUNTIME_DIR`). That keeps them off sudo's logged command line.
2. It calls `sudo -n /usr/local/libexec/hide-jail <file>`. The sudoers drop-in allows
   that single helper without a password, and nothing else.
3. The helper checks that the jail and its guard rules are up. It then moves into the
   namespace (`nsenter --net`) and **drops straight back to your uid and groups**
   (`setpriv`). Root never reads your arguments.
4. `hide __enter`, now running as you, rebuilds your environment and runs the command.

Two other approaches were tested and rejected:
- `sg`/group tagging lost access to your FUSE mounts, which breaks file pickers.
- `ip netns exec` remounts `/sys`, which breaks snaps.

**`hide add <app>`** copies the app's launcher to `~/.local/share/applications/`, where
it overrides the system one. The copy:
- prefixes every `Exec=` with `hide run --app`;
- removes `DBusActivatable`, so the menu can't start the app another way;
- adds " (Tor)" to the name.

The app's autostart entry is rewritten too, with a backup. `hide remove` restores both.

If the app is already running outside the jail, a launcher refuses to start it. A
single-instance app (browser, Electron) would otherwise hand the new window to that
unprotected copy. Quit it fully first.

### 4. Browsers and proxy-aware apps

- **WebRTC.** Chrome, Chromium and Brave get the managed policy
  `WebRtcIPHandling=disable_non_proxied_udp`. Firefox gets
  `/etc/firefox/policies/policies.json` with these prefs locked:
  - `media.peerconnection.ice.proxy_only_if_behind_proxy`, `ice.default_address_only` and `ice.no_host`: no local or public address in WebRTC candidates;
  - `network.proxy.allow_bypass=false` and `failover_direct=false`: if the proxy is down, fail instead of going direct;
  - `network.proxy.socks5_remote_dns=true`: Tor resolves hostnames.

  Check them at `chrome://policy` / `about:policies`.
- **`global-proxy on`** sets the KDE (kioslaverc; Chrome follows it) and GNOME proxy to
  SOCKS 127.0.0.1:9050. Firefox gets a PAC that spreads tabs over the 5 Tor ports.
  - Any site your previous PAC sent to a proxy *on this machine* keeps that route (a local dev site, for example).
  - `off` restores exactly what was set before.
  - Firefox reads this at startup, so restart it.
- **proxychains** (`proxychains4 <app>`) uses `random_chain` over the 5 ports and keeps
  `127.0.0.0/8` local (`localnet`). This is the fix for the 49374 error. It only works
  for dynamically linked apps; the jail works for everything.

## Verify — `hide-test`

It never fetches or prints your real IP. A pass is `check.torproject.org` answering
`"IsTor":true`, and a Tor exit is by definition not your address.

| Section | Checks |
|---|---|
| 1. Engine | both services up; ports 9050–9090, 9040 and 9053 owned by `ipchanger`; nothing else runs as that exempt uid |
| 2. SOCKS | all 5 ports reach Tor; how many distinct exits. `--rotation`: the exit changes after `ROTATE` (a WARN if Tor picked the same one) |
| 3. proxychains | reaches Tor, **and** a local web server is still reachable through it (the 49374 regression test) |
| 4. Jail | Tor; the 5 SOCKS ports work from inside (proxy settings); DNS works; only jail addresses are visible; STUN/WebRTC UDP gets no answer (with a positive control proving the probe works); no IPv6; your router is unreachable; routing guard present |
| 5. Global | you and root with no proxy reach Tor; a DNS query to an unroutable address is answered (all DNS captured); STUN, UPnP and NAT-PMP get `EPERM`; no IPv6; no interface holds a public address. `--docker`: a container reaches Tor |
| 6. Browsers | the policy files exist, parse, and hold the right values |
| 7. `--full` | stops the engine and checks that jailed and global traffic now **fail** (closed, not direct), then restarts it |

## What global mode breaks (honest list)

- **Sites that block Tor.** claude.ai on the web (HTTP 403, measured), some banks,
  streaming services and shops. Use `hide global off` while you need them.
- **Anything that needs UDP.** NTP (the clock slowly drifts; sync it now and then with
  global off), WireGuard/OpenVPN-over-UDP, voice and video calls (they fall back to TCP
  relays or fail), games, captive-portal Wi-Fi logins (turn global off to log in).
  Browsers fall back from QUIC to TCP on their own.
- **DNS.** Tor answers A, AAAA and PTR lookups only, so MX, TXT and SRV lookups fail.
  `.onion` names work through the SOCKS ports.
- **Email.** Gmail and IMAP providers may challenge logins from Tor exits. Port 25 is
  blocked by exits.
- **Speed.** Expect seconds of latency; large downloads are slow.
- **Inbound.** Docker ports you published to the internet stop answering the internet
  (LAN access still works).
- **Containers with ufw active.** ufw's input policy can drop container traffic to
  Tor's ports, and those containers then lose the internet (closed, not leaking). Allow
  their bridge: `sudo ufw allow in on docker0`.

## Limits — what this does *not* protect

- **Apps that are hostile on purpose** and run as you. The jail stops an app's own
  network use. A malicious app could still start a process outside the jail, through
  `systemd-run --user`, D-Bus activation or `sudo`. **Global mode** covers all of
  those, because it applies to every process.
- **`sudo` without a password.** If your account has `NOPASSWD: ALL`, any app you run
  can silently become root and switch all of this off. Remove that line from `/etc/sudoers.d/`.
  hide's own helper has its own narrow rule.
- **Who you are, as opposed to where you are.** Logins, cookies, browser fingerprinting
  and the content you post identify you whatever your IP. Use separate profiles or
  containers for identities you want kept apart.
- **Turning it off.** `hide global off`, `systemctl stop hide` and uninstall all remove
  the protection. That is what they are for.
- **The `ipchanger` uid** is allowed out directly. `hide-test` fails if anything other
  than ip-changer runs as that user, including a host-network container that uses the same uid.
- **Global IPv6 on an interface.** An app can read a public address straight from the
  interface list, with no network traffic at all. `hide-test` fails if any interface
  has one. Disable IPv6 on that interface, or use privacy addresses and treat the
  jail as the protection.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Nothing loads | Tor isn't up yet (bootstrapping takes 10–60 s), or is blocked: `journalctl -fu ip-changer`. Need the internet now? `hide-rescue` (works offline; add `--direct` if browsers still don't load) |
| `hide run`: "the Tor jail is down" | `sudo systemctl restart hide` |
| A jailed app can't connect, a firewall (ufw/firewalld) was enabled after install | `sudo ufw allow in on hide0` / `sudo firewall-cmd --permanent --zone=trusted --add-interface=hide0 && sudo firewall-cmd --reload` |
| "already running outside the Tor jail" | quit the app completely (including its tray icon), then start it again |
| Firefox ignores the proxy | restart Firefox; check `about:policies` |
| born2root's `inception_host_access.sh` was re-run | `global-proxy on` again (it re-appends its Firefox block after ours) |
| A Chromium or Electron **snap** (Chromium, Discord…) shows `ERR_ACCESS_DENIED`, jailed or not | not hide: on some kernel/snapd versions AppArmor refuses `read()` on sockets inside snaps (kernel 6.17 + snapd 2.77 here). Test: `snap run --shell chromium -c "python3 -c 'import socket,os; s=socket.create_connection((\"example.com\",80)); s.send(b\"HEAD / HTTP/1.0\\r\\n\\r\\n\"); os.read(s.fileno(),9)'"` fails with `Permission denied`. Use the deb/Flatpak build or wait for a snapd/kernel update |
| You started `ip-changer` by hand | it now refuses and points to the service: `journalctl -fu ip-changer` |

## Files installed

| Path | Role |
|---|---|
| `/etc/hide/hide.conf` | settings (kept across re-installs) |
| `/usr/local/bin/{hide,hide-test,hide-rescue,global-proxy}` | commands |
| `/usr/local/libexec/hide-jail` | the one root step of `hide run` |
| `/usr/local/lib/ip-changer/ip-changer-linux.sh` | engine (root-owned) |
| `/etc/systemd/system/{hide,ip-changer}.service` | boot services |
| `/etc/sudoers.d/hide` | `NOPASSWD` for `hide-jail` only |
| `/etc/{opt/chrome,chromium,chromium-browser,brave}/policies/managed/hide-webrtc.json` | Chrome-family WebRTC policy |
| `/etc/firefox/policies/policies.json` | Firefox locked prefs (merged into an existing file) |
| `/etc/proxychains4.conf` (or `proxychains.conf`) | rewritten; original kept as `.hide-bak` |
