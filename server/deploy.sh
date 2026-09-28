#!/usr/bin/env bash
# Ooze Syndicate room server - deploy (Alpha 20). Run from Game/2.0 after the Web export (BUILD-LOG sec10):
#   server/deploy.sh                 the build in build/web -> the server's /opt/ooze/web (the test link AND the
#                                    build its match hosts run) + version.txt, so server rooms match that version
#   server/deploy.sh --staging       (0.22.x) only this build's index.pck, as its versioned pack: the relay then hosts server
#                                    rooms for this version (the staging site) while the live site, version.txt and the test
#                                    link stay as they are. Promote later with a plain deploy.sh of the same build.
#   server/deploy.sh --relay         also server/relay.py + its service + server/Caddyfile, then restart the relay - only
#                                    while no room is open (0.21.4: checked here; --relay --force skips the check and
#                                    closes the open rooms)
# The server is the SSH host alias "ooze-server" (~/.ssh/config on Daniele's PC) or $OOZE_SERVER.
# Players on another build still play: CREATE ROOM falls back to hosting in their browser.
set -euo pipefail
cd "$(dirname "$0")/.."
SERVER="${OOZE_SERVER:-ooze-server}"
WEB="build/web"
RELAY=""
FORCE=""
STAGING=""
for a in "$@"; do
	case "$a" in
		--relay) RELAY="--relay" ;;
		--force) FORCE="--force" ;;
		--staging) STAGING="--staging" ;;
		*) echo "unknown option $a (use --relay, --relay --force, --staging)"; exit 1 ;;
	esac
done
if [ -n "$STAGING" ]; then                       # the pack only: nothing the live site or its rooms use changes
	[ -z "$RELAY" ] || { echo "--staging uploads a pack only; run --relay separately"; exit 1; }
	[ -f "$WEB/index.pck" ] || { echo "no $WEB/index.pck - export Web first"; exit 1; }
	tag=$(sed -n 's/^const VERSION_TAG := "\([^"]*\)".*/\1/p' scripts/net.gd)
	ver=$(sed -n 's/^const VERSION := "\([^"]*\)".*/\1/p' scripts/rules.gd)
	[ -n "$tag" ] && [ -n "$ver" ] || { echo "could not read the version"; exit 1; }
	scp -q "$WEB/index.pck" "$SERVER:/tmp/ooze-staging.pck"
	ssh "$SERVER" VER="${tag}_${ver}" 'bash -s' <<'EOF'
set -e
mkdir -p /opt/ooze/packs
install -o ooze -g ooze -m 644 /tmp/ooze-staging.pck "/opt/ooze/packs/$VER.pck" && rm /tmp/ooze-staging.pck
echo "staging pack: /opt/ooze/packs/$VER.pck $(stat -c %s "/opt/ooze/packs/$VER.pck")   live: $(cat /opt/ooze/web/version.txt)"
EOF
	exit 0
fi
# the live-room check (match hosts running, players connected to the relay); the same test runs again on the server
# right before the restart
ROOMS_CHECK='echo $(( $(pgrep -fc "^/opt/ooze/godot .*127.0.0.1:8765" || true) + $(ss -Htn state established "( sport = :8765 )" | wc -l) ))'
if [ -n "$RELAY" ] && [ -z "$FORCE" ]; then
	open=$(ssh "$SERVER" "$ROOMS_CHECK")
	[ "$open" = "0" ] || { echo "rooms are open on the server ($open match hosts + connections): --relay would close them."; 		echo "Retry when the server is idle, deploy the build only (no --relay), or add --force."; exit 3; }
fi
[ -f "$WEB/index.pck" ] || { echo "no $WEB/index.pck - export Web first"; exit 1; }
# Every extra pack a Web preset exports into build/web (skins.pck; from 0.21.1 hd.pck, skins_hd.pck, fetched on demand)
# must be there too, or the test link would miss it (0.21.0 went out without skins.pck).
for p in $(tr -d '\r' < export_presets.cfg | sed -n 's|^export_path="build/web/\([^"/]*\.pck\)"$|\1|p'); do
	[ -f "$WEB/$p" ] || { echo "no $WEB/$p - export its preset with --export-pack first (BUILD-LOG sec10)"; exit 1; }
done
tag=$(sed -n 's/^const VERSION_TAG := "\([^"]*\)".*/\1/p' scripts/net.gd)
ver=$(sed -n 's/^const VERSION := "\([^"]*\)".*/\1/p' scripts/rules.gd)
[ -n "$tag" ] && [ -n "$ver" ] || { echo "could not read the version"; exit 1; }
echo "$tag/$ver" > "$WEB/version.txt"
cp web/*.js web/*.txt "$WEB/" 2>/dev/null || true
rm -f "$WEB"/*.import "$WEB/duo.html"
tmp=$(mktemp -d)
tar czf "$tmp/web.tgz" -C build web
scp -q "$tmp/web.tgz" "$SERVER:/tmp/ooze-web.tgz"
if [ -n "$RELAY" ]; then
	scp -q server/relay.py server/ooze-relay.service server/Caddyfile "$SERVER:/tmp/"
fi
ssh "$SERVER" RELAY="$RELAY" FORCE="$FORCE" 'bash -s' <<'EOF'
set -e
rm -rf /opt/ooze/web.new && mkdir -p /opt/ooze/web.new
tar xzf /tmp/ooze-web.tgz -C /opt/ooze/web.new --strip-components=1 && rm /tmp/ooze-web.tgz
rm -rf /opt/ooze/web.old && { [ -d /opt/ooze/web ] && mv /opt/ooze/web /opt/ooze/web.old || true; }
mv /opt/ooze/web.new /opt/ooze/web && rm -rf /opt/ooze/web.old
# Each build's pack is kept under its version: a running match host reopens its pack by path at every scene load (the
# next round), so replacing it in place broke rooms that were playing during a deploy (TWVG, 0.20.12). New hosts start
# from /opt/ooze/current.pck (resolved by the relay); packs older than 2 days go, except the current one.
VER=$(tr '/' '_' < /opt/ooze/web/version.txt)
mkdir -p /opt/ooze/packs
cp /opt/ooze/web/index.pck "/opt/ooze/packs/$VER.pck"
ln -sfn "/opt/ooze/packs/$VER.pck" /opt/ooze/current.pck
find /opt/ooze/packs -name '*.pck' -mtime +2 ! -name "$VER.pck" -delete
mkdir -p /opt/ooze/data /opt/ooze/logs
chown -R ooze:ooze /opt/ooze/web /opt/ooze/packs /opt/ooze/data /opt/ooze/logs
find /opt/ooze/logs -name 'room-*.log' -mtime +7 -delete
find /opt/ooze/data -path '*telemetry*' -name 'match_*.json' -mtime +7 -delete   # the match hosts' telemetry files
if [ "$RELAY" = "--relay" ]; then
	open=$(( $(pgrep -fc "^/opt/ooze/godot .*127.0.0.1:8765" || true) + $(ss -Htn state established "( sport = :8765 )" | wc -l) ))   # = ROOMS_CHECK
	if [ "$open" != "0" ] && [ -z "$FORCE" ]; then
		rm -f /tmp/relay.py /tmp/ooze-relay.service /tmp/Caddyfile
		echo "server build: $(cat /opt/ooze/web/version.txt) - a room opened meanwhile ($open): relay NOT restarted, retry --relay later"
		exit 3
	fi
	sed -i 's/\r$//' /tmp/relay.py /tmp/ooze-relay.service /tmp/Caddyfile   # a Windows checkout's line ends
	cp -p /opt/ooze/relay.py /opt/ooze/relay.py.previous 2>/dev/null || true
	install -o ooze -g ooze -m 644 /tmp/relay.py /opt/ooze/relay.py
	install -m 644 /tmp/ooze-relay.service /etc/systemd/system/ooze-relay.service
	if ! cmp -s /tmp/Caddyfile /etc/caddy/Caddyfile; then      # the repo's Caddyfile (0.21.4): validated before it replaces
		if caddy validate --config /tmp/Caddyfile --adapter caddyfile >/dev/null 2>&1; then
			cp -p /etc/caddy/Caddyfile /etc/caddy/Caddyfile.previous
			install -m 644 /tmp/Caddyfile /etc/caddy/Caddyfile && systemctl reload caddy && echo "Caddyfile updated"
		else
			echo "server/Caddyfile does not validate - the server keeps its Caddyfile"
		fi
	fi
	rm -f /tmp/relay.py /tmp/ooze-relay.service /tmp/Caddyfile
	systemctl daemon-reload && systemctl restart ooze-relay
fi
echo "server build: $(cat /opt/ooze/web/version.txt)   relay: $(systemctl is-active ooze-relay)"
for f in /opt/ooze/web/*.pck; do echo "  $(basename "$f") $(stat -c %s "$f")"; done
EOF
rm -rf "$tmp"
