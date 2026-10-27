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
#   server/deploy.sh --check         (with or without --staging) only the overwrite guard below, against the box: uploads
#                                    and changes nothing; exit 0 = this build may deploy, 4 = a room runs this version
# The overwrite guard (Daniele, 2026-10-27): every deploy refuses (exit 4) to rewrite /opt/ooze/packs/<tag>_<version>.pck
# while a match host runs from that pack - a host reopens its pack by path at every scene load, so a rebuilt pack under
# the same version string breaks the room (bump Rules.VERSION or wait). A pack byte-identical to this build (the staging
# pack a plain deploy promotes) is left as it is, not rewritten.
# The server is the SSH host alias "ooze-server" (~/.ssh/config on Daniele's PC) or $OOZE_SERVER.
# Players on another build still play: CREATE ROOM falls back to hosting in their browser.
set -euo pipefail
cd "$(dirname "$0")/.."
SERVER="${OOZE_SERVER:-ooze-server}"
WEB="build/web"
RELAY=""
FORCE=""
STAGING=""
CHECK=""
for a in "$@"; do
	case "$a" in
		--relay) RELAY="--relay" ;;
		--force) FORCE="--force" ;;
		--staging) STAGING="--staging" ;;
		--check) CHECK="--check" ;;
		*) echo "unknown option $a (use --relay, --relay --force, --staging, --check)"; exit 1 ;;
	esac
done
[ -f "$WEB/index.pck" ] || { echo "no $WEB/index.pck - export Web first"; exit 1; }
tag=$(sed -n 's/^const VERSION_TAG := "\([^"]*\)".*/\1/p' scripts/net.gd)
ver=$(sed -n 's/^const VERSION := "\([^"]*\)".*/\1/p' scripts/rules.gd)
[ -n "$tag" ] && [ -n "$ver" ] || { echo "could not read the version"; exit 1; }
# The overwrite guard, run on the box before anything is uploaded (and again there right before the pack is written):
# "free" = no match host runs from the pack, "same" = one does but the pack on the box is already this build, "busy" = refuse.
# Fed through stdin so the remote command line never contains the pattern (pgrep -f would match its own ssh shell).
GUARD='P=/opt/ooze/packs/$VER.pck
if ! pgrep -f -- "--main-pack $P( |\$)" > /dev/null; then echo free
elif [ -f "$P" ] && [ "$(sha256sum < "$P" | cut -d" " -f1)" = "$SUM" ]; then echo same
else echo busy; fi'
SUM=$(sha256sum < "$WEB/index.pck" | cut -d" " -f1)
guard=$(ssh "$SERVER" VER="${tag}_${ver}" SUM="$SUM" 'bash -s' <<< "$GUARD")
case "$guard" in
	free|same) echo "overwrite guard: ${tag}_${ver}.pck $guard${CHECK:+ - this build may deploy}" ;;
	busy) echo "a room runs this version - bump Rules.VERSION or wait (${tag}_${ver}.pck is in use on the server)"; exit 4 ;;
	*) echo "overwrite guard: no answer from $SERVER ($guard)"; exit 1 ;;
esac
[ -z "$CHECK" ] || exit 0
if [ -n "$STAGING" ]; then                       # the pack only: nothing the live site or its rooms use changes
	[ -z "$RELAY" ] || { echo "--staging uploads a pack only; run --relay separately"; exit 1; }
	scp -q "$WEB/index.pck" "$SERVER:/tmp/ooze-staging.pck"
	ssh "$SERVER" VER="${tag}_${ver}" 'bash -s' <<'EOF'
set -e
mkdir -p /opt/ooze/packs
P="/opt/ooze/packs/$VER.pck"
if [ -f "$P" ] && cmp -s /tmp/ooze-staging.pck "$P"; then rm /tmp/ooze-staging.pck; echo "staging pack already this build"
elif pgrep -f -- "--main-pack $P( |\$)" > /dev/null; then   # the overwrite guard, again: a room may have opened since the check
	rm /tmp/ooze-staging.pck; echo "a room runs this version - bump Rules.VERSION or wait ($VER.pck is in use)"; exit 4
else install -o ooze -g ooze -m 644 /tmp/ooze-staging.pck "$P" && rm /tmp/ooze-staging.pck; fi
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
ssh "$SERVER" RELAY="$RELAY" FORCE="$FORCE" VER="${tag}_${ver}" 'bash -s' <<'EOF'
set -e
rm -rf /opt/ooze/web.new && mkdir -p /opt/ooze/web.new
tar xzf /tmp/ooze-web.tgz -C /opt/ooze/web.new --strip-components=1 && rm /tmp/ooze-web.tgz
# the overwrite guard, again, before anything live changes: a room may have opened since the check
P="/opt/ooze/packs/$VER.pck"
if ! { [ -f "$P" ] && cmp -s /opt/ooze/web.new/index.pck "$P"; } && pgrep -f -- "--main-pack $P( |\$)" > /dev/null; then
	rm -rf /opt/ooze/web.new /tmp/relay.py /tmp/ooze-relay.service /tmp/Caddyfile
	echo "a room runs this version - bump Rules.VERSION or wait ($VER.pck is in use; nothing changed on the server)"; exit 4
fi
rm -rf /opt/ooze/web.old && { [ -d /opt/ooze/web ] && mv /opt/ooze/web /opt/ooze/web.old || true; }
mv /opt/ooze/web.new /opt/ooze/web && rm -rf /opt/ooze/web.old
# Each build's pack is kept under its version: a running match host reopens its pack by path at every scene load (the
# next round), so replacing it in place broke rooms that were playing during a deploy (TWVG, 0.20.12). New hosts start
# from /opt/ooze/current.pck (resolved by the relay). Pruning is by VERSION, never by age (0.23.13: a deploy after two quiet
# weeks used to delete every rollback pack): the newest KEEP packs by version stay; the current one never goes, and neither
# does a pack a running match host was started from.
mkdir -p /opt/ooze/packs
cmp -s /opt/ooze/web/index.pck "$P" || cp /opt/ooze/web/index.pck "$P"   # identical (a promoted staging pack): left as it is
ln -sfn "/opt/ooze/packs/$VER.pck" /opt/ooze/current.pck
KEEP=4
ls /opt/ooze/packs/*.pck | sort -V | head -n "-$KEEP" | while read -r p; do
	[ "$p" = "/opt/ooze/packs/$VER.pck" ] && continue
	if pgrep -f -- "--main-pack $p " > /dev/null; then echo "keeping $(basename "$p"): a room is running from it"; continue; fi
	rm -f -- "$p"
done
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
