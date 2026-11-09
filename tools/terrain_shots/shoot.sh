#!/bin/bash
# shoot <out.png> [extra user args...] : R-01 STRAIT, all-AI match, 1280x720 desktop, frame at 6.0 s
out="$1"; shift
tmp=$(mktemp -d -p C:/Users/itisf/ooze-wt/terrain-shots-tools)
size=1280x720
for a in "$@"; do [ "$a" = "--mobile" ] && size=740x340; done
cd C:/Users/itisf/ooze-wt/terrain-shots
timeout 300 "/h/My Drive/PROJECTS/Ooze Syndicate/Tools/Godot/Godot_v4.6.1-stable_win64_console.exe" --path . --audio-driver Dummy --position -6000,-6000 --resolution $size -- --test --map=res://maps4/R-01-strait.json --demo --seed=1 --shots=6 --out="$tmp" "$@" > "$tmp/log.txt" 2>&1
f=$(ls "$tmp"/shot_*.png 2>/dev/null | head -1)
if [ -n "$f" ]; then mv "$f" "$out"; echo "OK $out"; else echo "FAIL $out"; grep -i "error" "$tmp/log.txt" | head -5; fi
grep -i "debug texture" "$tmp/log.txt" | head -2
rm -rf "$tmp"
