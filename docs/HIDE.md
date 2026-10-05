# hide — keep your real IP away from apps and websites

`hide` builds on ip-changer (5 Tor instances whose exit IP rotates every few seconds)
and makes it **enforced by the kernel**, not something each app has to agree to.

```
sudo ./setup.sh check        # can this machine run hide? changes nothing
sudo ./setup.sh install      # any systemd Linux: apt, dnf, pacman or zypper
hide-test                    # proves it works; exit code 0 = no check failed
sudo ./setup.sh uninstall    # removes everything, restores what was there before
```

`install` takes `--global on|off` (skip the question) and `--bridges snowflake|obfs4|off`.
`sudo ./setup.sh deps` only installs the packages.

Everything is driven by one file, `hide.conf` (copied once to `/etc/hide/hide.conf`, and
never overwritten by a re-install):

| Setting | Meaning |
|---|---|
| `GLOBAL=on` | every app, user (root too) and container reaches the internet only through Tor |
| `GLOBAL=off` | only jailed apps (`hide run`, `hide add`) and proxy-aware apps use Tor. The default: a first install asks, and stays off without a terminal or `--global` |
| `ROTATE=30` | seconds between new Tor exits |
| `APPS="…"` | launchers that always start inside the Tor jail |
| `BRIDGES=…` | `snowflake`, `obfs4`, or a file of your own bridge lines: reach Tor where it is blocked. Empty = direct |
| `FAST_SITES="…"` | the fast lane's sites: `youtube`, `twitch` or domains. They skip Tor in browsers set up by `global-proxy`. Set it with `hide fast` |
| `FAST_APPS=off` | `on`: apps started with `hide fast run` skip Tor, UDP included. Off until you add an app |

## Commands

| Command | What it does |
|---|---|
| `hide` / `hide status` | engine, bridges, rules, global mode, current Tor exit, jailed apps. In global mode it sends a real request with no proxy, so it notices when the rules are gone even though the config says on |
| `hide global on\|off` | switch global mode (asks for sudo, takes effect at once) |
| `hide bridges snowflake\|obfs4\|FILE\|off` | switch bridges and restart the engine. If Tor won't start with them, the old setting comes back |
| `hide run <cmd> [args…]` | run one command inside the Tor jail, as you |
| `hide add` | list the apps installed on this machine |
| `hide add <app>` | that app's menu entry and autostart always start it inside the jail |
| `hide remove <app>\|--all` | undo `hide add` |
| `hide fast` | the fast lane: what's in it, and whether its proxy runs |
| `hide fast add youtube\|twitch\|<domain>\|<app>` | a site (`youtube`, `twitch`, a domain) or an app skips Tor from now on. An app's launcher starts it in the fast lane, as `hide add` does for the jail |
| `hide fast remove …` | undo one |
| `hide fast run <cmd> [args…]` | run one command in the fast lane (a game: `hide fast run ./game`). Opens the lane for apps first if it's closed (sudo) |
| `hide fast off` | close the lane: no sites, no apps, the proxy stops |
| `hide check-rules` | can this kernel run hide? Checks every rule with `nft -c`, loads nothing (sudo) |
| `global-proxy on\|off` | point KDE/GNOME/Chrome/Firefox proxy settings at Tor (setup turns it on) |
| `hide-test [--rotation] [--full] [--docker]` | self-test, see below |
| `hide-rescue [--direct]` | **internet back now**, whatever state hide is in: global off, its rules removed, DNS reset, the network service restarted if still offline (NetworkManager, systemd-networkd, connman, iwd, wicked or ifupdown). `--direct` also turns the proxy settings off (browsers go direct). Needs no network |
| `hide-rescue --in 5m` / `--cancel` | safety net before a risky change: rescue runs by itself in 5 min unless cancelled |
| `journalctl -fu ip-changer` | live log of the Tor engine |

## How it works

### 1. The engine — `ip-changer.service`

ip-changer runs at boot as the system user `ipchanger`, which setup creates (no login
shell; its script is root-owned in `/usr/local/lib/ip-changer/`, so that user can't change
its own code). Your distro's own `tor.service` is disabled while hide is installed, and
uninstall turns it back on only if it was on before.

- 5 Tor instances: SOCKS ports 9050, 9060, 9070, 9080, 9090. Every `ROTATE` seconds
  each is told `NEWNYM`, so new connections leave from a different exit.
- Instance 0 also opens a **TransPort** (9040) and two **DNSPorts** (127.0.0.1:9054 and
  9055). The kernel rules below redirect ordinary traffic into the TransPort and into
  **`hide-dns`** (9053), so apps need no proxy setting.
- `hide-dns` is there because Tor's DNSPort passes on whatever the exit says, and a few
  exits are wrong: about 1 in 40 said github.com doesn't exist. Every lookup then failed the
  same way until the next `NEWNYM`, and `git clone --recursive` lost half its submodules.
  `hide-dns` asks 9054 first. If the answer is "no such name", a server failure, or slow
  (3 s), it also asks 9055, which Tor keeps on other circuits, so another exit. The first
  good answer wins, and "no such name" stands only when both exits say it. It runs as a user
  systemd makes up (`DynamicUser`), so global mode does not exempt it. It starts, stops and
  restarts with `ip-changer.service`, and it never logs names. `hide-dns --self-test`
  checks it against two fake DNSPorts.
- Its own traffic is the only traffic allowed to leave directly: the kernel rules
  exempt the `ipchanger` uid. Without that Tor would be sent into itself.
- **Bridges** (`BRIDGES=`): `snowflake` and `obfs4` use the bridge lines built into Tor
  Browser (`bridges/*.txt`, with their source and date). They need `lyrebird` (it runs both),
  or `snowflake-client` for snowflake and `obfs4proxy` for obfs4; `setup.sh install --bridges …`
  installs one, and the engine asks each program which kinds it runs, the way Tor does. Arch
  has them in the AUR only (`lyrebird-proxy`): setup names the package. Fedora and
  openSUSE have no snowflake client package (obfs4 is fine; openSUSE's `snowflake` is the
  volunteer proxy, which setup won't install). These shared lines go stale over time: fresh
  private ones come from https://bridges.torproject.org (`hide bridges ./my-bridges.txt`).
- Tor's control ports (9051, 9061 … 9091) have no password, so **in both modes** only the
  `ipchanger` user may connect to them. Otherwise any app could tell Tor to use a bridge
  of its choice and learn your IP.

### 2. Global mode — nftables table `inet hide` (`GLOBAL=on`)

`hide.service` runs `hide apply` before the network comes up (`network-pre.target`).
It loads one nftables table, atomically:

| Traffic | What happens |
|---|---|
| TCP to the internet, any user | sent to Tor's TransPort 9040 |
| DNS (port 53) to *any* server, LAN routers included | sent to `hide-dns` (9053), which asks Tor |
| Any other UDP (QUIC, STUN/WebRTC, NTP, games, VPNs), ICMP, global IPv6 | dropped. Local programs get `EPERM`, so they fail at once instead of hanging |
| UPnP (1900) / NAT-PMP (5351) to your router | dropped. Those protocols hand out your public IP |
| Containers and VMs (bridge, veth, vxlan: Docker, k8s, libvirt) | TCP and DNS redirected the same way; anything else forwarded to the internet is dropped |
| Loopback, LAN, carrier-grade NAT and Tailscale (100.64.0.0/10), Docker networks, multicast | untouched: printers, NAS and local dev keep working |

The rules **fail closed**. If Tor is down, traffic stops; it never falls back to your
real address. Connections that were already open when you switched to global mode are cut.

"Sent to" means DNAT to **this machine's own address on the outgoing card**
(`dnat ip to ip saddr : 9053`), not `redirect` (which means 127.0.0.1). systemd-resolved
pins its upstream DNS sockets to the network card (`SO_BINDTOIFINDEX`); a packet pinned
to the card and redirected to 127.0.0.1 is routed out of the card and lost, so every name
lookup on the machine failed. `hide-test` checks this with a pinned socket.

### 3. The app jail — `hide run`, `hide add` (works in both modes)

A Linux **network namespace** named `hide` is connected to the host by a virtual cable:
`hide0` (10.233.233.1) on the host and `hide1` (10.233.233.2) in the jail.

- Inside, an app sees only `lo` and `10.233.233.2`. It cannot read your LAN or public
  address, it has no IPv6, and it cannot reach your LAN or router.
- Everything the jail sends is redirected to Tor on the host side: TCP → 9040, DNS → 9053 (`hide-dns`).
- DNS: `/etc/resolv.conf` usually names a resolver on loopback (127.0.0.53 with
  systemd-resolved, 127.0.1.1 or 127.0.0.1 with dnsmasq), which inside the jail is the
  jail's own loopback. A rule inside the jail forwards those queries to `hide-dns`.
  This also works for snaps, which ignore mount tricks.
- Proxy settings: `global-proxy` points browsers and Electron apps at `127.0.0.1:9050`,
  which is also the jail's own loopback. The jail forwards the 5 SOCKS ports to Tor on
  the host (`route_localnet` on `hide0`). Tor's control ports are not forwarded.
- **Fail closed twice.** A routing rule (`ip rule iif hide0 lookup 233` → `unreachable`)
  means jail packets can never be forwarded to the internet, even if every nftables
  rule is flushed. The firewall also drops them. The rule and its route are marked
  `protocol kernel`, the mark systemd-networkd leaves alone when it cleans up other
  programs' routing (`networkctl reload`).
- The app keeps its own private `localhost`. proxychains, by contrast, can send an app's
  own localhost traffic into Tor (`127.0.0.1:<port> <--socket error or timeout!`). That
  cannot happen in the jail.

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
- removes `DBusActivatable`, so the menu can't start the app another way, and `TryExec`;
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
  SOCKS 127.0.0.1:9050, or to the fast lane's 127.0.0.1:9049 while it has sites (see 5).
  Firefox gets a PAC in every profile it finds (`~/.mozilla`, `~/.config/mozilla`, the
  snap's and the Flatpak's). The PAC lists the 5 Tor ports in order, after 9049 when the
  lane has sites; Firefox moves to the next one only when a port doesn't answer.
  - Any site your previous PAC sent to a proxy *on this machine* keeps that route (a local dev site, for example).
  - `off` restores exactly what was set before.
  - Firefox reads this at startup, so restart it.
  - On other desktops (XFCE, MATE, a bare window manager…) only Firefox is set, and it
    says so: Chrome-family browsers need `hide add <browser>` or global mode.
- **proxychains** (`proxychains4 <app>`) uses `random_chain` over the 5 ports and keeps
  `127.0.0.0/8` local (`localnet`), so an app's own localhost still works. It only works
  for dynamically linked apps; the jail works for everything.

### 5. The fast lane — `hide fast` (off until you use it)

Tor makes video slow and drops UDP, so calls and games fail. The fast lane lets the sites
and apps you choose **skip Tor**. Everything else stays on Tor.

```
browser ──► 127.0.0.1:9049 hide-fast-proxy ──┬─ youtube.com, twitch.tv… ──► direct (fast)
                                             └─ every other site ─────────► Tor (9050)
hide fast run discord ──► group hide-fast ─────── TCP + UDP ───────────────► direct
everything else ────────────────────────────────────────────────────────────► Tor
```

**What it costs.** What's in the lane sees your real IP: YouTube (Google), Twitch, Discord,
and the game servers you play on. While apps are in the lane (`FAST_APPS=on`), any program
running as you could also start itself with `hide fast run` and go direct. Nothing can
stop that without a password on every launch. That's why the lane starts closed, and why
`hide fast off` closes it.

**Sites** go through `hide-fast-proxy`, a SOCKS5 proxy on 127.0.0.1:9049. It is
`hide-fast.service`, running as the system user `hide-fast`, and it only runs while
`FAST_SITES` has something. A request goes direct only when it:
- names a host (not an address) on port 80 or 443;
- matches `FAST_SITES` by whole labels: `www.youtube.com` matches `youtube.com`,
  `evilyoutube.com` and `youtube.com.evil.net` don't;
- resolves to public addresses only (no LAN, loopback or carrier-grade NAT).

Anything else is passed to Tor's SOCKS port 9050 exactly as it came, so Tor still resolves
the name. BIND and UDP ASSOCIATE are refused, and the proxy never logs a host name.
`youtube` and `twitch` are keywords for the domains their videos come from
(`hide-fast-proxy --keywords`; the list is at the top of the file).
- Browsers send everything to 9049, so the list lives in one place, `/etc/hide/hide.conf`.
  While `global-proxy` is on, `hide fast add` and `remove` re-run it for you, so browsers
  follow the lane.
- Proxy down? Chrome and KDE/GNOME apps fail (closed, never direct). Firefox moves on to
  Tor's 9050.
- TCP only: YouTube's QUIC falls back to TCP. It's still fast: no 3 relays in the way.

**Apps** go through `hide fast run`, or through a launcher written by `hide fast add <app>`
(`Exec=hide fast run --app …`, " (fast)" in its name). `hide fast run` asks
`sudo -n /usr/local/libexec/hide-jail --fast`, the same helper as the jail, under the same
sudoers line. The helper refuses unless `FAST_APPS=on`, then starts the command as you, with
the `hide-fast` group as your primary group (`setpriv --regid`).
- In global mode, two rules exempt that group, only while the lane is in use:
  `meta skgid hide-fast return` in `nat_out` and `meta skgid hide-fast accept` in
  `filter_out`. TCP, UDP and IPv6 then leave directly.
- They come after the rules that send DNS to Tor and block Tor's control ports, UPnP and
  NAT-PMP. So for an app in the lane, your ISP still doesn't see the names it looks up,
  it can't ask your router for your public IP, and it can't drive Tor.
- With global mode off, nothing needs exempting: the app simply runs as normal.
- The jail can never reach the lane. The jail sends its 127.0.0.1:9049 to Tor's 9050, and
  `hide-jail --fast` doesn't change network namespace, so a jailed app that calls
  `hide fast run` stays in the jail.
- Side effect: files a fast app creates belong to the `hide-fast` group. You still own them.
- A launcher refuses to start the app if it already runs outside the lane: quit it fully
  first, as with the jail.

## Verify — `hide-test`

It never fetches or prints your real IP. A pass is `check.torproject.org` answering
`"IsTor":true`, and a Tor exit is by definition not your address. The exit code is 0 when
no check failed; warnings and skips are listed but don't fail it.

| Section | Checks |
|---|---|
| 1. Engine | both services up; ports 9050–9090, 9040, 9054 and 9055 owned by `ipchanger`; `hide-dns` up on 9053 as another user, and its self-test; nothing else runs as that exempt uid |
| 2. SOCKS | all 5 ports reach Tor; how many distinct exits. `--rotation`: the exit changes after `ROTATE` (a WARN if Tor picked the same one) |
| 3. proxychains | reaches Tor, **and** a local web server is still reachable through it (localhost stays local) |
| 4. Jail | Tor; the 5 SOCKS ports work from inside (proxy settings); DNS to the server in `/etc/resolv.conf` works; only jail addresses are visible; STUN/WebRTC UDP gets no answer (with a positive control proving the probe works); no IPv6; your router is unreachable; routing guard present. A WARN when name lookups bypass DNS packets (`nss-resolve`, `nscd`; see Limits) |
| 5. Global | you and root with no proxy reach Tor; a DNS query to an unroutable address is answered (all DNS captured), also from a socket pinned to the network card (SKIP on kernels older than 5.7, which refuse the pin); STUN, UPnP and NAT-PMP get `EPERM`; no IPv6; every live internet connection of your apps has its twin on Tor's TransPort (names the apps, never addresses); no interface holds a public address. `--docker`: a container reaches Tor |
| 6. Browsers | the policy files exist, parse, and hold the right values |
| 7. Fast lane | only while it's in use. The proxy runs as `hide-fast` and passes `--self-test`; a site that isn't in the lane, through 9049, still reaches Tor, also from the jail; a site in the lane leaves no twin on Tor's TransPort (it went direct). Apps: in global mode a `hide fast run` UDP send is allowed and its DNS still answered by Tor; `hide run hide fast run` still reaches Tor. Apps off: the helper refuses |
| 8. `--full` | stops the engine and checks that jailed and global traffic now **fail** (closed, not direct), then restarts it |

## What global mode breaks (honest list)

- **Sites that block Tor.** claude.ai on the web (HTTP 403, measured), some banks,
  streaming services and shops. Use `hide global off` while you need them.
- **Anything that needs UDP.** NTP (the clock slowly drifts; sync it now and then with
  global off), WireGuard/OpenVPN-over-UDP, voice and video calls (they fall back to TCP
  relays or fail), games, captive-portal Wi-Fi logins (turn global off to log in).
  Browsers fall back from QUIC to TCP on their own. Calls and games work in the fast
  lane (`hide fast add discord`, `hide fast run ./game`), without Tor.
- **Machines without a battery-backed clock** (Raspberry Pi and other boards). They boot
  with a stale date, Tor refuses to connect with a clock that wrong, and NTP is blocked:
  nothing comes up. Set the date first (`hide-rescue`, let NTP sync, then `hide global on`),
  or keep global mode off on such boards.
- **DNS.** Tor answers A, AAAA and PTR lookups only, so MX, TXT and SRV lookups fail.
  `.onion` names work through the SOCKS ports.
- **Email.** Gmail and IMAP providers may challenge logins from Tor exits. Port 25 is
  blocked by exits.
- **Speed.** Expect seconds of latency; large downloads are slow.
- **Inbound.** Docker ports you published to the internet stop answering the internet
  (LAN access still works).
- **Containers with ufw or firewalld active.** Their input policy can drop container
  traffic to Tor's ports, and those containers then lose the internet (closed, not
  leaking). Allow their bridge: `sudo ufw allow in on docker0`, or
  `sudo firewall-cmd --permanent --zone=trusted --add-interface=docker0 && sudo firewall-cmd --reload`.

## Limits — what this does *not* protect

- **Apps that are hostile on purpose** and run as you. The jail stops an app's own
  network use. A malicious app could still start a process outside the jail, through
  `systemd-run --user`, D-Bus activation or `sudo`. **Global mode** covers all of
  those, because it applies to every process.
- **`sudo` without a password.** If your account has `NOPASSWD: ALL`, any app you run
  can silently become root and switch all of this off. Remove that line from `/etc/sudoers.d/`.
  hide's own helper has its own narrow rule.
- **The `docker` and `lxd` groups** are root in all but name: `docker run --network host`
  leaves the jail, and a privileged container can switch everything off. An app that can
  run docker (a coding agent in auto mode, say) can escape the jail; global mode still
  covers its traffic until it uses root.
- **Command-line apps.** `hide add` rewrites menu launchers only. For a terminal tool use
  `hide run <tool>`, or rely on global mode. A tool that serves other programs on
  localhost (an AI agent's local server, say) can't be jailed alone: whatever talks to it
  from outside the jail no longer reaches it.
- **Name lookups in the jail on Fedora, Arch and others using `nss-resolve` or `nscd`.**
  There, programs ask the host's resolver over a local socket instead of sending DNS
  packets, and the jail can't redirect a socket. With global mode **off**, your DNS
  provider sees which names a jailed app looks up (its traffic still goes through Tor).
  With global mode on, the host's own DNS goes through Tor too. `hide-test` warns about it.
- **VMs and containers that skip the host's firewall**: macvlan/ipvlan containers and
  bridged VM adapters (VirtualBox "Bridged", libvirt `macvtap`) put their packets straight
  on the card. Use NAT networking (Docker's default bridge, libvirt's `default` network,
  VirtualBox "NAT") so global mode covers them.
- **Something flushing every firewall rule.** `nft flush ruleset` by hand, or a tool doing
  the same, removes hide's rules until `sudo systemctl restart hide`; the jail stays
  closed meanwhile (its routing guard), and in global mode `hide status` says so.
  Restarting or reloading `nftables.service`, and booting with it enabled, are fine:
  `hide.service` puts its rules back right after (tested on Debian, Fedora, Ubuntu and Arch).
- **Tor inside a VM or container on a global-mode host** is Tor over Tor. Exit relays
  refuse connections to other relays, so the inner Tor stays stuck at 10%. Give it
  bridges, which aren't public relays (`--bridges obfs4`).
- **Who you are, as opposed to where you are.** Logins, cookies, browser fingerprinting
  and the content you post identify you whatever your IP. Use separate profiles or
  containers for identities you want kept apart.
- **The fast lane** (`hide fast`) skips Tor on purpose: its sites and apps see your real
  IP. While apps are in it, any program running as you could use `hide fast run` too.
  `hide fast off` closes it, and `hide-test` counts the live connections that use it.
- **Turning it off.** `hide global off`, `systemctl stop hide` and uninstall all remove
  the protection. That is what they are for.
- **The `ipchanger` uid** is allowed out directly. `hide-test` fails if anything other
  than ip-changer runs as that user, including a host-network container that uses the same uid.
- **Global IPv6 on an interface.** An app can read a public address straight from the
  interface list, with no network traffic at all. `hide-test` fails if any interface
  has one. Disable IPv6 on that interface, or use privacy addresses and treat the
  jail as the protection.
- **Flatpak Firefox** may not read `/etc/firefox/policies` (not verified): check
  `about:policies`, and rely on the PAC from `global-proxy` or on global mode.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Nothing loads | Tor isn't up yet (bootstrapping takes 10–60 s), or is blocked: `journalctl -fu ip-changer`. Need the internet now? `hide-rescue` (works offline; add `--direct` if browsers still don't load) |
| `hide-test` FAILs right after install or boot (SOCKS ports, proxychains) | Tor is still connecting: wait 2 minutes and re-run. `hide-test` warns when the engine has just started |
| Tor never connects: the log stays stuck below 100% | your network blocks Tor: `hide bridges obfs4` (or `snowflake`). Also check the clock: `date` |
| `setup.sh check`: a port is held by another program | stop it (Fedora's Cockpit holds 9090: `sudo systemctl disable --now cockpit.socket`), or remove the Tor you run on those ports, then install again |
| `setup.sh check`: the kernel rejects the rules | hide needs Linux ≥ 5.2 and nftables ≥ 0.9.3 |
| `hide run`: "the Tor jail is down" | `sudo systemctl restart hide` |
| A jailed app can't connect, a firewall (ufw/firewalld) was enabled after install | `sudo ufw allow in on hide0` / `sudo firewall-cmd --permanent --zone=trusted --add-interface=hide0 && sudo firewall-cmd --reload` |
| "already running outside the Tor jail" | quit the app completely (including its tray icon), then start it again |
| Firefox ignores the proxy | restart Firefox; check `about:policies` |
| Another script rewrote Firefox's `user.js` proxy prefs | `global-proxy on` again |
| A Chromium or Electron **snap** (Chromium, Discord…) shows `ERR_ACCESS_DENIED`, jailed or not | not hide: on some kernel/snapd versions AppArmor refuses `read()` on sockets inside snaps (seen with kernel 6.17 + snapd 2.77). Test: `snap run --shell chromium -c "python3 -c 'import socket,os; s=socket.create_connection((\"example.com\",80)); s.send(b\"HEAD / HTTP/1.0\\r\\n\\r\\n\"); os.read(s.fileno(),9)'"` fails with `Permission denied`. Use the deb/Flatpak build or wait for a snapd/kernel update |
| You started `ip-changer` by hand | it now refuses and points to the service: `journalctl -fu ip-changer` |

## Files installed

| Path | Role |
|---|---|
| `/etc/hide/hide.conf` | settings (kept across re-installs) |
| `/usr/local/bin/{hide,hide-test,hide-rescue,global-proxy}` | commands |
| `/usr/local/libexec/hide-jail` | the one root step of `hide run` and `hide fast run` |
| `/usr/local/libexec/hide-fast-proxy` | the fast lane's proxy for sites (127.0.0.1:9049) |
| `/usr/local/libexec/hide-dns` | DNS on 9053: Tor's answer, and a second exit's when the first says "no such name" |
| `/usr/local/lib/ip-changer/ip-changer-linux.sh` | engine (root-owned) |
| `/usr/local/lib/ip-changer/bridges/{obfs4,snowflake}.txt` | Tor Browser's built-in bridge lines |
| `/etc/hide/bridges.txt` | your own bridge lines, after `hide bridges FILE` |
| `/etc/systemd/system/{hide,ip-changer,hide-dns,hide-fast}.service` | boot services (`hide-dns` with `ip-changer`; `hide-fast` only while the lane has sites) |
| users `ipchanger`, `hide-fast` | system users for the engine and the fast lane, removed by uninstall |
| `/etc/sudoers.d/hide` | `NOPASSWD` for `hide-jail` only |
| `/etc/{opt/chrome,chromium,chromium-browser,brave}/policies/managed/hide-webrtc.json` | Chrome-family WebRTC policy |
| `/etc/firefox/policies/policies.json` | Firefox locked prefs (merged into an existing file) |
| `/etc/proxychains4.conf` (or `proxychains.conf`) | rewritten; original kept as `.hide-bak` |
| `/usr/local/share/doc/hide/HIDE.md` | this file |
