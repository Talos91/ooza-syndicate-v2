# Ooze Syndicate room server (Alpha 20)

- Stage 1 (0.19.0): `relay.py` replaces PeerJS. Every player keeps one WebSocket to the server, which forwards
  strings between a room's host and guests.
- Stage 2 (2026-09-27): CREATE ROOM makes a **server-hosted room**. The relay starts this same web build
  headless (`godot --headless --main-pack index.pck -- --dedicated`); that match host runs the `Sim` with no
  seat of its own, and the creator joins as the room owner who runs the lobby (`Net.room_owner`, `can_control`).
  No player's device hosts, so a phone in the background only drops its own seat (RECONNECT). If the server
  has no free match host (`--max-matches`) or runs another game version (`version.txt`), the game falls back
  to hosting in the creator's browser, as in stage 1. An empty server lobby closes after 5 s (0.20.1; 0.20.0: 90 s); a match everyone dropped out of waits 90 s for a RECONNECT.

- Protocol `ooze20-net-5` (0.21.3): the host's packets (snapshots, effects, answers) reach guests as binary
  frames: host -> relay `[1][len][guest id][packet]`, relay -> guest `[2][4]host[packet]`; everything else stays JSON text.
  relay.py forwards both, so it must be at least as new as the game (the binary-aware relay has run since the 0.21.2
  deploy; the net-4 one is kept on the box as `/opt/ooze/relay.py.net4-backup`). A slow guest skips snapshots (backlog).

- Limits (0.21.4): frames are capped per socket on the frame header (bigger = the socket closes with 1009, nothing
  buffered): 64 KB for the hello, 8 KB for a guest, 1 MB for a host (the largest keyframe measured: 81 KB raw / 13 KB
  deflated); 64 sockets per address (carrier NAT). A booting match host starts at nice 10 and goes back to 0 once it
  connects (the service gives the relay `CAP_SYS_NICE`; the hosts inherit no capabilities), so loading a pack doesn't
  slow the rooms playing. The match hosts write no telemetry files (only their room log).

## The box

- Vultr, Singapore, `vhp-1c-1gb` (1 vCPU, 1 GB, NVMe, 2 TB traffic), Ubuntu 26.04 LTS, backups on.
- Access details (SSH key, login): Daniele / the server session - kept out of the repo. Key-only login via
  `/etc/ssh/sshd_config.d/00-ooze.conf`, which must sort before `50-cloud-init.conf`. `server/deploy.sh`
  uses the SSH alias `ooze-server` (or `$OOZE_SERVER`).
- ufw: 22, 80, 443 only. fail2ban, unattended-upgrades, 2 GB swap. Game files in `/opt/ooze` (user `ooze`):
  `godot` (the official 4.6.1 Linux binary), `relay.py`, `web/` (the build), `data/` (the match hosts'
  `user://`), `logs/room-<code>.log` (kept 7 days).
- Address until a domain exists: `45-32-126-20.sslip.io` (sslip.io resolves it to the IP; Caddy gets a
  Let's Encrypt certificate for it). The game connects to `wss://45-32-126-20.sslip.io/ooze`
  (`Net.RELAY_URL`). With a domain: point `play.<domain>` at the IP, change the Caddyfile site name and
  `Net.RELAY_URL`.

## Services

- `ooze-relay.service` (`server/ooze-relay.service`): the relay as `ooze`, restarts itself, `MemoryMax=900M`
  for the relay plus up to two match hosts (~250-350 MB each). Needs `python3-websockets`, `libfontconfig1`.
- Caddy (`/etc/caddy/Caddyfile`, kept in `server/Caddyfile` since 0.21.4; `deploy.sh --relay` validates and installs it when it
  differs, keeping `Caddyfile.previous`): TLS on 443, `/ooze*` -> `127.0.0.1:8765`; everything else serves
  `/opt/ooze/web` - the **test link** https://45-32-126-20.sslip.io/, always the build the match hosts run.

## Deploy (every publish, after the Web export and the skins pack)

```bash
server/deploy.sh            # build/web -> the server (test link + match hosts) + version.txt
server/deploy.sh --relay    # also relay.py + the service + Caddyfile, then restart - refused while a room is open
server/deploy.sh --relay --force   # the same, closing the open rooms
```

Until the server has the published build, players of that build still play: their rooms fall back to
browser hosting. A running match keeps its old pack; new rooms use the new one.

deploy.sh stops if a pack that a Web preset exports into `build/web` is missing (`skins.pck`; from 0.21.1 also
`hd.pck`, `skins_hd.pck`, fetched on demand), and prints the server's pack sizes to check against gh-pages.

## Test

```bash
python server/relay.py --godot <Godot console exe> --project <Game/2.0>     # local relay that can host rooms
Godot_v4.6.1-stable_win64_console.exe --headless --path . --script res://tests/test_dedicated.gd -- --relay=ws://127.0.0.1:8765
Godot_v4.6.1-stable_win64_console.exe --headless --path . --script res://tests/test_dedicated.gd   # the live server
Godot_v4.6.1-stable_win64_console.exe --headless --path . --script res://tests/test_relay.gd       # player-hosted rooms
```

Both exit 2 (SKIP) when no relay / no match server answers. In the browser, `?relay=ws://127.0.0.1:8765`
points a build at a local relay and `?relay=peerjs` brings back the old PeerJS rooms.
