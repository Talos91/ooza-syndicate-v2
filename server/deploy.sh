#!/usr/bin/env bash
# Ooze Syndicate room server - deploy (Alpha 20). Run from Game/2.0 after the Web export (BUILD-LOG sec10):
#   server/deploy.sh                 the build in build/web -> the server's /opt/ooze/web (the test link AND the
#                                    build its match hosts run) + version.txt, so server rooms match that version
#   server/deploy.sh --relay         also server/relay.py + its service, then restart it (closes open rooms)
# The server is the SSH host alias "ooze-server" (~/.ssh/config on Daniele's PC) or $OOZE_SERVER.
# Players on another build still play: CREATE ROOM falls back to hosting in their browser.
set -euo pipefail
cd "$(dirname "$0")/.."
SERVER="${OOZE_SERVER:-ooze-server}"
WEB="build/web"
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
if [ "${1:-}" = "--relay" ]; then
	scp -q server/relay.py server/ooze-relay.service "$SERVER:/tmp/"
fi
ssh "$SERVER" RELAY="${1:-}" 'bash -s' <<'EOF'
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
	install -o ooze -g ooze -m 644 /tmp/relay.py /opt/ooze/relay.py
	install -m 644 /tmp/ooze-relay.service /etc/systemd/system/ooze-relay.service
	rm -f /tmp/relay.py /tmp/ooze-relay.service
	systemctl daemon-reload && systemctl restart ooze-relay
fi
echo "server build: $(cat /opt/ooze/web/version.txt)   relay: $(systemctl is-active ooze-relay)"
for f in /opt/ooze/web/*.pck; do echo "  $(basename "$f") $(stat -c %s "$f")"; done
EOF
rm -rf "$tmp"
