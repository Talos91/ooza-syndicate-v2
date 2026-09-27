#!/usr/bin/env python3
"""Ooze Syndicate 2.0 - room server (Alpha 20).

Replaces PeerJS: every player keeps one WebSocket to this server and the server forwards strings
between a room's host and its guests. It speaks the same events net.gd already reads from
web/peer-transport.js (open / connection / data / closed / error), so the game rules stay in the
host's Godot Sim; this process never looks inside a packet.

Stage 2: {"op": "create"} opens a room HOSTED ON THE SERVER. The relay starts a headless Godot for it
(the same build the players run, `--dedicated`), which connects back as the room's host with
{"op": "host", "room": code, "secret": s}; the creator then joins as the first guest (the room owner, who
runs the lobby). Without a server build, or with another game version, create is refused with a "code"
("no-server" / "version" / "busy") and the game falls back to hosting in the creator's browser.

Client -> relay (text frames, JSON):
  {"op": "create", "version": v}          a server-hosted room (stage 2); then as a guest
  {"op": "host"}                          open a room hosted by this client; reply {"type": "open", "code": "ABCD"}
  {"op": "join", "code": "ABCD"}          join; reply open + {"type": "connection", "peer": "host"}
  {"op": "send", "to": id, "data": str}   forward (a guest's "to" is ignored: it always goes to the host)
  {"op": "kick", "peer": id}              host only: drop a guest
Relay -> client: {"type": "data", "peer": sender, "data": str}, {"type": "connection" | "closed", "peer": id},
  {"type": "error", "message": str}. A guest sees the host as peer "host".

Run: python3 relay.py [--host 127.0.0.1] [--port 8765]   (Caddy terminates TLS in front of it)
"""
import argparse
import asyncio
import json
import logging
import os
import secrets
import time

from websockets.asyncio.server import serve
from websockets.exceptions import ConnectionClosed

ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"   # the codes PeerJS rooms used (no I, O, 0, 1)
MAX_GUESTS = 5                                  # 6 seats: the host plus five
MAX_ROOMS = 200
MAX_PER_IP = 12                                 # open sockets from one address
GUEST_MAX = 4096                                # a guest's packet (net.gd's host drops longer ones too)
HOST_MAX = 8 * 1024 * 1024                      # a host's packet (net.gd MAX_PACKET)
GUEST_RATE = 60                                 # packets per second before the relay drops a guest
STATE_BACKLOG = 64 * 1024                       # skip a snapshot while this much is still queued to a guest
HELLO_TIMEOUT = 10.0
TEST_MAX_AGE = 600.0                            # a test room's match host is stopped after 10 min
BOOT_TIMEOUT = 25.0                             # a server match host has this long to connect back (the game gives up at 30 s)

cfg = None          # argparse namespace (main)

log = logging.getLogger("relay")
rooms = {}          # code -> Room
per_ip = {}         # address -> open sockets


class Room:
    def __init__(self, code, host):
        self.code = code
        self.host = host
        self.guests = {}        # peer id -> websocket
        self.serial = 0
        self.created = time.time()
        self.proc = None            # the headless Godot hosting this room (stage 2); host is None until it connects
        self.secret = ""
        self.ready = asyncio.Event()
        self.test = False           # created by a test (Net.test_room): a real player's room may take its slot


def server_matches():
    return sum(1 for r in rooms.values() if r.proc is not None)


def server_version():
    try:
        with open(cfg.version_file, encoding="utf-8") as f:
            return f.read().strip()
    except (OSError, TypeError):
        return ""


def packet(**kw):
    return json.dumps(kw, separators=(",", ":"))


async def say(ws, **kw):
    try:
        await ws.send(packet(**kw))
    except ConnectionClosed:
        pass


async def refuse(ws, message, code=""):
    """Send the reason and let the client hang up first: Godot drops a message that lands with the close."""
    await say(ws, type="error", message=message, code=code)
    try:
        await asyncio.wait_for(ws.wait_closed(), 5.0)
    except asyncio.TimeoutError:
        pass


def backlog(ws):
    transport = getattr(ws, "transport", None)
    return transport.get_write_buffer_size() if transport is not None else 0


async def forward(ws, sender, data):
    if data.startswith('{"kind":"state"') and backlog(ws) > STATE_BACKLOG:
        return                  # a slow guest skips snapshots instead of lagging further behind
    await say(ws, type="data", peer=sender, data=data)


def new_code():
    for _ in range(50):
        code = "".join(secrets.choice(ALPHABET) for _ in range(4))
        if code not in rooms:
            return code
    return None


async def run_host(ws):
    code = new_code()
    if code is None or len(rooms) >= MAX_ROOMS:
        await refuse(ws, "The room server is full. Try again in a minute.")
        return
    room = Room(code, ws)
    rooms[code] = room
    log.info("room %s opened (%d rooms)", code, len(rooms))
    await say(ws, type="open", code=code)
    await host_loop(ws, room)


async def run_server_host(ws, code, secret):
    """The headless Godot of a server-hosted room connects back (stage 2)."""
    room = rooms.get(code)
    if room is None or room.host is not None or not room.secret or not secrets.compare_digest(room.secret, secret):
        await refuse(ws, "Unknown room.")
        return
    room.host = ws
    room.ready.set()
    await say(ws, type="open", code=code)
    await host_loop(ws, room)


async def free_slot_for_real_room():
    """All match hosts busy and a real player wants a room: stop the oldest test room's host (its guests hear the host
    left) and wait for the slot. True when a slot is free."""
    tests = sorted((r for r in rooms.values() if r.proc is not None and r.test), key=lambda r: r.created)
    if not tests:
        return False
    victim = tests[0]
    log.info("room %s: test room stopped for a real player's room", victim.code)
    stop(victim)
    for _ in range(50):
        if server_matches() < cfg.max_matches:
            return True
        await asyncio.sleep(0.1)
    return server_matches() < cfg.max_matches


async def reap_old_tests():
    """Test rooms never outlive TEST_MAX_AGE, whatever the test did."""
    while True:
        await asyncio.sleep(30)
        now = time.time()
        for r in list(rooms.values()):
            if r.test and r.proc is not None and now - r.created > TEST_MAX_AGE:
                log.info("room %s: test room past %d s - stopped", r.code, int(TEST_MAX_AGE))
                stop(r)


async def run_create(ws, version, ip, test=False):
    """A server-hosted room: start its match host, then let the creator in as the first guest."""
    if not cfg.godot or not os.path.exists(cfg.godot) or not (cfg.pck or cfg.project):
        await refuse(ws, "No match server here.", code="no-server")
        return
    want = server_version()
    if want and version != want:
        await refuse(ws, "The server runs another game version.", code="version")
        return
    code = new_code()
    if code is not None and server_matches() >= cfg.max_matches and not test:
        await free_slot_for_real_room()                 # real players first: a test room gives its slot up
    if code is None or len(rooms) >= MAX_ROOMS or server_matches() >= cfg.max_matches:
        await refuse(ws, "The match server is busy.", code="busy")
        return
    room = Room(code, None)
    room.test = test
    room.secret = secrets.token_urlsafe(18)
    rooms[code] = room
    pck = os.path.realpath(cfg.pck) if cfg.pck else ""   # the versioned pack current.pck points to now (deploys swap it)
    cmd = [cfg.godot, "--headless"] + (["--main-pack", pck] if cfg.pck else ["--path", cfg.project]) + [
        "--", "--dedicated", "--relay=ws://127.0.0.1:%d/ooze" % cfg.port, "--room=" + code, "--secret=" + room.secret] + cfg.host_arg
    env = dict(os.environ, GODOT_SILENCE_ROOT_WARNING="1")
    if cfg.data:
        env["XDG_DATA_HOME"] = cfg.data
    out = asyncio.subprocess.DEVNULL
    if cfg.logs:
        os.makedirs(cfg.logs, exist_ok=True)
        out = open(os.path.join(cfg.logs, "room-%s.log" % code), "wb")
    try:
        room.proc = await asyncio.create_subprocess_exec(*cmd, stdin=asyncio.subprocess.DEVNULL, stdout=out,
                                                         stderr=asyncio.subprocess.STDOUT, env=env)
    except OSError as e:
        log.warning("room %s: could not start the match host: %s", code, e)
        rooms.pop(code, None)
        await refuse(ws, "The match server could not start.", code="busy")
        return
    finally:
        if out is not asyncio.subprocess.DEVNULL:
            out.close()
    log.info("room %s: starting a server match host for %s (%d server matches)%s", code, ip, server_matches(),
             " [test]" if test else "")
    asyncio.get_running_loop().create_task(reap(room))
    try:
        await asyncio.wait_for(room.ready.wait(), BOOT_TIMEOUT)
    except asyncio.TimeoutError:
        log.warning("room %s: the match host did not connect", code)
        if rooms.get(code) is room and room.host is None:
            rooms.pop(code, None)
        stop(room)
        await refuse(ws, "The match server did not start in time.", code="busy")
        return
    await run_guest(ws, code)


def stop(room):
    if room.proc is not None and room.proc.returncode is None:
        try:
            room.proc.terminate()
        except ProcessLookupError:
            pass


async def reap(room):
    """A server match host that exits early frees its room slot."""
    code = await room.proc.wait()
    log.info("room %s: match host exited (%s)", room.code, code)
    if room.host is None and rooms.get(room.code) is room:
        rooms.pop(room.code, None)


async def host_loop(ws, room):
    code = room.code
    try:
        async for raw in ws:
            if not isinstance(raw, str) or len(raw) > HOST_MAX + 256:
                continue
            try:
                msg = json.loads(raw)
            except ValueError:
                continue
            if not isinstance(msg, dict):
                continue
            op = msg.get("op")
            if op == "send":
                target = room.guests.get(str(msg.get("to", "")))
                data = msg.get("data")
                if target is not None and isinstance(data, str) and len(data) <= HOST_MAX:
                    await forward(target, "host", data)
            elif op == "kick":
                target = room.guests.get(str(msg.get("peer", "")))
                if target is not None:
                    await target.close(1000, "removed by the host")
    except ConnectionClosed:
        pass
    finally:
        if rooms.get(code) is room:
            rooms.pop(code, None)
        for guest in list(room.guests.values()):
            await say(guest, type="closed", peer="host")
            await guest.close(1000, "the host left")
        stop(room)
        log.info("room %s closed (%d rooms)", code, len(rooms))


async def run_guest(ws, code):
    room = rooms.get(code)
    if room is None:
        await refuse(ws, "Room not found. Check the code and keep the host online.")
        return
    if room.host is None:
        await refuse(ws, "That room is still starting. Try again in a moment.")
        return
    if len(room.guests) >= MAX_GUESTS + (1 if room.proc is not None else 0):   # a server host takes no seat
        await refuse(ws, "That room is full.")
        return
    room.serial += 1
    pid = "p%d" % room.serial
    room.guests[pid] = ws
    await say(ws, type="open", code=code)
    await say(ws, type="connection", peer="host")
    await say(room.host, type="connection", peer=pid)
    window, count = time.monotonic(), 0
    try:
        async for raw in ws:
            now = time.monotonic()
            if now - window > 1.0:
                window, count = now, 0
            count += 1
            if count > GUEST_RATE:
                await ws.close(1008, "too many packets")
                break
            if not isinstance(raw, str) or len(raw) > GUEST_MAX + 256:
                continue
            try:
                msg = json.loads(raw)
            except ValueError:
                continue
            if isinstance(msg, dict) and msg.get("op") == "send":
                data = msg.get("data")
                if isinstance(data, str) and len(data) <= GUEST_MAX and rooms.get(code) is room:
                    await say(room.host, type="data", peer=pid, data=data)
    except ConnectionClosed:
        pass
    finally:
        if room.guests.pop(pid, None) is not None and rooms.get(code) is room:
            await say(room.host, type="closed", peer=pid)


async def handler(ws):
    ip = (ws.request.headers.get("X-Forwarded-For") or str(ws.remote_address[0])).split(",")[0].strip()
    if per_ip.get(ip, 0) >= MAX_PER_IP:
        await ws.close(1008, "too many connections")
        return
    per_ip[ip] = per_ip.get(ip, 0) + 1
    try:
        raw = await asyncio.wait_for(ws.recv(), HELLO_TIMEOUT)
        msg = json.loads(raw) if isinstance(raw, str) and len(raw) < 512 else {}
        op = msg.get("op") if isinstance(msg, dict) else None
        if op == "host" and msg.get("room"):
            await run_server_host(ws, str(msg.get("room", "")), str(msg.get("secret", "")))
        elif op == "host":
            await run_host(ws)
        elif op == "create":
            await run_create(ws, str(msg.get("version", "")), ip, bool(msg.get("test", False)))
        elif op == "join":
            code = str(msg.get("code", "")).strip().upper()
            if len(code) == 4 and all(c in ALPHABET for c in code):
                await run_guest(ws, code)
            else:
                await refuse(ws, "Enter the four-character room code.")
    except (asyncio.TimeoutError, ConnectionClosed, ValueError):
        pass
    finally:
        per_ip[ip] -= 1
        if per_ip[ip] <= 0:
            per_ip.pop(ip, None)


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--godot", default="", help="Godot binary for server-hosted rooms (stage 2)")
    ap.add_argument("--pck", default="", help="the game build it runs (the web export's index.pck)")
    ap.add_argument("--project", default="", help="or a project folder (local tests)")
    ap.add_argument("--version-file", default="", help="holds Net.version() of that build; others fall back")
    ap.add_argument("--max-matches", type=int, default=2)
    ap.add_argument("--data", default="", help="XDG_DATA_HOME for the match hosts (user://)")
    ap.add_argument("--logs", default="", help="a log file per server-hosted room")
    ap.add_argument("--host-arg", action="append", default=[], help="tests: an extra argument for every match host (e.g. --match-end=20)")
    global cfg
    args = cfg = ap.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s")
    async with serve(handler, args.host, args.port, max_size=HOST_MAX + 1024, ping_interval=20,
                     ping_timeout=20, compression=None) as server:
        log.info("relay on %s:%d", args.host, args.port)
        asyncio.get_running_loop().create_task(reap_old_tests())
        await server.serve_forever()


if __name__ == "__main__":
    asyncio.run(main())
