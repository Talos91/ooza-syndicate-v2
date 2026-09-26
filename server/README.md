# Ooze Syndicate room server (Alpha 20)

Stage 1 (live since 2026-09-27): `relay.py` replaces PeerJS. Every player keeps one WebSocket to the server,
which forwards strings between a room's host and guests; the host's Godot `Sim` still runs the match.
Stage 2 (next): a headless Godot on the server hosts the match, so no player's device is the host.

## The box

- Vultr, Singapore, `vhp-1c-1gb` (1 vCPU, 1 GB, NVMe, 2 TB traffic), Ubuntu 26.04 LTS, backups on.
- IPv4 `45.32.126.20`, hostname `ooze-server`. SSH: `ssh -i ~/.ssh/ooze_server root@45.32.126.20`
  (key on Daniele's PC; key-only login via `/etc/ssh/sshd_config.d/00-ooze.conf`, which must sort before
  `50-cloud-init.conf`).
- ufw: 22, 80, 443 only. fail2ban, unattended-upgrades, 2 GB swap. Game files in `/opt/ooze` (user `ooze`).
- Address until a domain exists: `45-32-126-20.sslip.io` (sslip.io resolves it to the IP; Caddy gets a
  Let's Encrypt certificate for it). The game connects to `wss://45-32-126-20.sslip.io/ooze`
  (`Net.RELAY_URL`). With a domain: point `play.<domain>` at the IP, change the Caddyfile site name and
  `Net.RELAY_URL`.

## Services

- `ooze-relay.service`: `python3 /opt/ooze/relay.py --host 127.0.0.1 --port 8765` as `ooze`, restarts
  itself, `MemoryMax=300M`. Needs `python3-websockets` (apt).
- Caddy (`/etc/caddy/Caddyfile`): TLS on 443, `/ooze*` -> `127.0.0.1:8765`, anything else answers
  "Ooze Syndicate room server".

## Update the relay

```bash
scp -i ~/.ssh/ooze_server server/relay.py root@45.32.126.20:/opt/ooze/relay.py
ssh -i ~/.ssh/ooze_server root@45.32.126.20 "systemctl restart ooze-relay && journalctl -u ooze-relay -n 5 --no-pager"
```

Restarting closes the open rooms, so do it between playtests.

## Test

```bash
python server/relay.py                    # local relay on 127.0.0.1:8765
Godot_v4.6.1-stable_win64_console.exe --headless --path . --script res://tests/test_relay.gd -- --relay=ws://127.0.0.1:8765
Godot_v4.6.1-stable_win64_console.exe --headless --path . --script res://tests/test_relay.gd   # the live server
```

In the browser, `?relay=ws://127.0.0.1:8765` points a build at a local relay and `?relay=peerjs` brings back
the old PeerJS rooms.
