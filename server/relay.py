#!/usr/bin/env python3
"""Ooze Syndicate 2.0 - room relay (Alpha 20 stage 1).

Replaces PeerJS: every player keeps one WebSocket to this server and the server forwards strings
between a room's host and its guests. It speaks the same events net.gd already reads from
web/peer-transport.js (open / connection / data / closed / error), so the game rules stay in the
host's Godot Sim; this process never looks inside a packet.

Client -> relay (text frames, JSON):
  {"op": "host"}                          open a room; reply {"type": "open", "code": "ABCD"}
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


def packet(**kw):
    return json.dumps(kw, separators=(",", ":"))


async def say(ws, **kw):
    try:
        await ws.send(packet(**kw))
    except ConnectionClosed:
        pass


async def refuse(ws, message):
    """Send the reason and let the client hang up first: Godot drops a message that lands with the close."""
    await say(ws, type="error", message=message)
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
        rooms.pop(code, None)
        for guest in list(room.guests.values()):
            await say(guest, type="closed", peer="host")
            await guest.close(1000, "the host left")
        log.info("room %s closed (%d rooms)", code, len(rooms))


async def run_guest(ws, code):
    room = rooms.get(code)
    if room is None:
        await refuse(ws, "Room not found. Check the code and keep the host online.")
        return
    if len(room.guests) >= MAX_GUESTS:
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
        if op == "host":
            await run_host(ws)
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
    args = ap.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s")
    async with serve(handler, args.host, args.port, max_size=HOST_MAX + 1024, ping_interval=20,
                     ping_timeout=20, compression=None) as server:
        log.info("relay on %s:%d", args.host, args.port)
        await server.serve_forever()


if __name__ == "__main__":
    asyncio.run(main())
