"""Ooze Syndicate 2.0 - put the soundtrack's used tracks into assets/audio/music/ (never committed: the repo is public
and the Cyberpunk Music Pack by SmellyCatCafe is a bought pack).

Run it before an import / export of the game (BUILD-LOG sec10, the publish step):

    python tools/copy_music.py              # copy the web-sized tracks from the project's Art folder
    python tools/copy_music.py --encode     # first (re)make those web-sized tracks with Blender, then copy
    python tools/copy_music.py --encode-phone   # (re)make the phone set (mono 22 kHz) from the web-sized tracks
    python tools/copy_music.py --web        # also fill build/web/music/ and build/web/music_phone/ (the publish)
    python tools/copy_music.py --check      # only say what is missing (exit 1 if anything is)

The track list and the numbers come from scripts/rules.gd's MUSIC block (MUSIC_TRACKS, MUSIC_STINGER_LEN,
MUSIC_STINGER_FADE, MUSIC_ENCODE_KBPS, MUSIC_PHONE_HZ, MUSIC_PHONE_KBPS), so this script never needs editing when a
slot's pick changes.

The web build plays the tracks in the browser (web/music.js, 0.22.4), loose beside index.html, not in a .pck:
build/web/music/<track>.ogg (the desktop set, OGG web/) and build/web/music_phone/<track>.ogg (the phone set, OGG phone/)
- --web copies both there (the gh-pages publish then copies build/web/music* along; BUILD-LOG sec10).

Where the files live (Art/Audio/Soundtrack - Cyberpunk Music Pack (SmellyCatCafe)/ in the project folder):
  OGG 96k/     the pack's 15 tracks as Daniele converted them (immutable; the --encode fallback source)
  OGG web/     the tracks the game ships, made by --encode: Vorbis MUSIC_ENCODE_KBPS kbps, 44.1 kHz stereo; a name
               ending " (stinger)" is the first MUSIC_STINGER_LEN s of its track, the last MUSIC_STINGER_FADE s fading
  OGG phone/   the same tracks for phones, made by --encode-phone from OGG web/: mono, MUSIC_PHONE_HZ Hz, Vorbis
               MUSIC_PHONE_KBPS kbps (Daniele 2026-09-29: "ok 22hz on mobile"); ffmpeg (pip imageio-ffmpeg) or Blender
The project folder is found by walking up from this file (a checkout inside Game/2.0), else $OOZE_ROOT, else the
canonical H:/My Drive/PROJECTS/Ooze Syndicate (a clean clone elsewhere). --art <pack folder> overrides it.
--encode source: --src <folder> (FLAC or OGG files named like the tracks), else the pack's FLAC/ folder if there,
else OGG 96k/. Blender: $BLENDER, else Blender 5.2's default install path (its aud module encodes; no ffmpeg here).
Only assets/audio/music/*.ogg (and their .import files) not in the list are removed; nothing else is touched.
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)                                   # the checkout (tools/..)
RULES = os.path.join(GAME, "scripts", "rules.gd")
DEST = os.path.join(GAME, "assets", "audio", "music")
PACK = os.path.join("Art", "Audio", "Soundtrack - Cyberpunk Music Pack (SmellyCatCafe)")
CANONICAL = "H:/My Drive/PROJECTS/Ooze Syndicate"
BLENDER = "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe"
WEB_DIR = "OGG web"
PHONE_DIR = "OGG phone"
BUILD_WEB = os.path.join(GAME, "build", "web")
WEB_OUT = {WEB_DIR: "music", PHONE_DIR: "music_phone"}         # Art folder -> build/web/<folder> (Rules.MUSIC_WEB_DIR*)
STINGER = " (stinger)"


def rules():
    """MUSIC_TRACKS' file names and the encode numbers, read from rules.gd."""
    s = open(RULES, encoding="utf-8").read()
    m = re.search(r"^const MUSIC_TRACKS := \{(.*?)\}\s*$", s, re.S | re.M)
    if not m:
        sys.exit("copy_music: no MUSIC_TRACKS in " + RULES)
    names = []
    for lst in re.findall(r"\[([^\]]*)\]", m.group(1)):
        for n in re.findall(r'"([^"]+)"', lst):
            if n not in names:
                names.append(n)

    def num(key):
        k = re.search(r"^const %s := ([0-9.]+)" % key, s, re.M)
        if not k:
            sys.exit("copy_music: no %s in %s" % (key, RULES))
        return float(k.group(1))
    return (names, num("MUSIC_STINGER_LEN"), num("MUSIC_STINGER_FADE"), int(num("MUSIC_ENCODE_KBPS")),
            int(num("MUSIC_PHONE_HZ")), int(num("MUSIC_PHONE_KBPS")))


def pack_dir(arg):
    if arg:
        return arg
    d = GAME
    while True:
        if os.path.isdir(os.path.join(d, PACK)):
            return os.path.join(d, PACK)
        up = os.path.dirname(d)
        if up == d:
            break
        d = up
    root = os.environ.get("OOZE_ROOT", CANONICAL)
    return os.path.join(root, PACK)


def encode(names, pack, src, length, fade, kbps):
    """(Re)make pack/OGG web/ with Blender's aud module: every track at kbps, the stingers cut and faded."""
    if not src:
        src = os.path.join(pack, "FLAC") if os.path.isdir(os.path.join(pack, "FLAC")) else os.path.join(pack, "OGG 96k")
    out = os.path.join(pack, WEB_DIR)
    os.makedirs(out, exist_ok=True)
    jobs = []
    for n in names:
        base = n[:-len(STINGER)] if n.endswith(STINGER) else n
        found = [os.path.join(src, base + ext) for ext in (".flac", ".ogg", ".wav") if os.path.isfile(os.path.join(src, base + ext))]
        if not found:
            sys.exit("copy_music: no source for %r in %s" % (base, src))
        jobs.append((found[0], os.path.join(out, n + ".ogg"), n.endswith(STINGER)))
    script = """import aud, sys
jobs = %r
for f, o, cut in jobs:
    s = aud.Sound(f).resample(44100, False)
    if cut:
        s = s.limit(0.0, %r).fadeout(%r, %r)
    s.write(o, 44100, aud.CHANNELS_STEREO, aud.FORMAT_S16, aud.CONTAINER_OGG, aud.CODEC_VORBIS, %d)
    print("ENCODED", o)
""" % (jobs, length, length - fade, fade, kbps * 1000)
    tmp = tempfile.NamedTemporaryFile("w", suffix=".py", delete=False, encoding="utf-8")
    tmp.write(script)
    tmp.close()
    blender = os.environ.get("BLENDER", BLENDER)
    try:
        r = subprocess.run([blender, "-b", "--factory-startup", "--python", tmp.name], capture_output=True, text=True)
    finally:
        os.unlink(tmp.name)
    done = [l for l in r.stdout.splitlines() if l.startswith("ENCODED")]
    if r.returncode != 0 or len(done) != len(jobs):
        sys.exit("copy_music: Blender failed (%d of %d encoded)\n%s\n%s" % (len(done), len(jobs), r.stdout[-2000:], r.stderr[-2000:]))
    print("copy_music: encoded %d tracks from %s into %s (%d kbps)" % (len(jobs), src, out, kbps))


def encode_phone(names, pack, hz, kbps):
    """(Re)make pack/OGG phone/ from pack/OGG web/: mono, hz, kbps (stingers are already cut in OGG web/)."""
    src = os.path.join(pack, WEB_DIR)
    out = os.path.join(pack, PHONE_DIR)
    os.makedirs(out, exist_ok=True)
    try:
        import imageio_ffmpeg                                  # pip install imageio-ffmpeg (a bundled ffmpeg)
        ff = imageio_ffmpeg.get_ffmpeg_exe()
    except ImportError:
        ff = None
    if ff is None:
        jobs = [(os.path.join(src, n + ".ogg"), os.path.join(out, n + ".ogg")) for n in names]
        script = """import aud
for f, o in %r:
    aud.Sound(f).resample(%d, False).rechannel(1).write(o, %d, aud.CHANNELS_MONO, aud.FORMAT_S16, aud.CONTAINER_OGG, aud.CODEC_VORBIS, %d)
    print("ENCODED", o)
""" % (jobs, hz, hz, kbps * 1000)
        tmp = tempfile.NamedTemporaryFile("w", suffix=".py", delete=False, encoding="utf-8")
        tmp.write(script)
        tmp.close()
        try:
            r = subprocess.run([os.environ.get("BLENDER", BLENDER), "-b", "--factory-startup", "--python", tmp.name],
                               capture_output=True, text=True)
        finally:
            os.unlink(tmp.name)
        if r.returncode != 0 or r.stdout.count("ENCODED") != len(jobs):
            sys.exit("copy_music: Blender failed on the phone set\n%s\n%s" % (r.stdout[-2000:], r.stderr[-2000:]))
    else:
        for n in names:
            r = subprocess.run([ff, "-v", "error", "-y", "-i", os.path.join(src, n + ".ogg"), "-ac", "1", "-ar", str(hz),
                                "-c:a", "libvorbis", "-b:a", "%dk" % kbps, os.path.join(out, n + ".ogg")],
                               capture_output=True, text=True)
            if r.returncode != 0:
                sys.exit("copy_music: ffmpeg failed on %s\n%s" % (n, r.stderr[-2000:]))
    print("copy_music: encoded %d phone tracks into %s (mono %d Hz, %d kbps)" % (len(names), out, hz, kbps))


def sync(names, src, dest):
    """dest/<track>.ogg = src/<track>.ogg for every track (a changed file only); any other .ogg there (and its .import)
    goes. Returns the bytes in dest."""
    os.makedirs(dest, exist_ok=True)
    total = 0
    for n in names:
        a = os.path.join(src, n + ".ogg")
        b = os.path.join(dest, n + ".ogg")
        if not os.path.isfile(b) or os.path.getsize(b) != os.path.getsize(a) or open(b, "rb").read() != open(a, "rb").read():
            shutil.copyfile(a, b)                              # (a changed file only: Godot re-imports what changed)
        total += os.path.getsize(b)
    keep = {n + ".ogg" for n in names}
    for f in os.listdir(dest):                                 # a track no slot uses any more goes (and its .import)
        ogg = f[:-len(".import")] if f.endswith(".import") else f
        if ogg.endswith(".ogg") and ogg not in keep:
            os.remove(os.path.join(dest, f))
            print("copy_music: removed", os.path.join(dest, f))
    return total


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--encode", action="store_true", help="(re)make the web-sized tracks with Blender first")
    ap.add_argument("--encode-phone", action="store_true", help="(re)make the phone set (mono) from the web-sized tracks")
    ap.add_argument("--web", action="store_true", help="also copy both sets into build/web/music*/ (the publish)")
    ap.add_argument("--check", action="store_true", help="only report what is missing")
    ap.add_argument("--art", help="the music pack's folder (Art/Audio/Soundtrack - ...)")
    ap.add_argument("--src", help="--encode: the source folder (FLAC / OGG named like the tracks)")
    a = ap.parse_args()
    names, length, fade, kbps, phone_hz, phone_kbps = rules()
    pack = pack_dir(a.art)
    if a.encode:
        encode(names, pack, a.src, length, fade, kbps)
    if a.encode or a.encode_phone:
        encode_phone(names, pack, phone_hz, phone_kbps)
    web = os.path.join(pack, WEB_DIR)
    bad = False
    for d, fix in ((WEB_DIR, "--encode"), (PHONE_DIR, "--encode-phone")):
        missing = [n for n in names if not os.path.isfile(os.path.join(pack, d, n + ".ogg"))]
        if missing:
            print("copy_music: missing in %s: %s (run with %s)" % (os.path.join(pack, d), ", ".join(missing), fix))
            bad = True
    if bad:
        sys.exit(1)
    if a.check:
        print("copy_music: all %d tracks are in %s and %s" % (len(names), web, os.path.join(pack, PHONE_DIR)))
        return
    if a.web:
        for d, sub in WEB_OUT.items():
            n_bytes = sync(names, os.path.join(pack, d), os.path.join(BUILD_WEB, sub))
            print("copy_music: %d tracks in build/web/%s/ (%.1f MB)" % (len(names), sub, n_bytes / 1e6))
    total = sync(names, web, DEST)                             # native / editor runs play these from res://
    print("copy_music: %d tracks in %s (%.1f MB) - import the project before exporting" % (len(names), DEST, total / 1e6))


if __name__ == "__main__":
    main()
