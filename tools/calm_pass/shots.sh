#!/bin/bash
# shots.sh : baseline / a / b / c x (R-01 t5, t100, t245, E-01 t100); 812x375 --mobile, seed 7, AI vs AI (--demo)
G="/h/My Drive/PROJECTS/Ooze Syndicate/Tools/Godot/Godot_v4.6.1-stable_win64_console.exe"
OUT=C:/Users/itisf/ooze-wt/calm-pass-out/shots
cd /c/Users/itisf/ooze-wt/calm-pass
for v in ${VARIANTS:-base a b c}; do
  CALM=""; [ "$v" != base ] && CALM="--calm=$v"
  for spec in R-01-strait:5 R-01-strait:100 R-01-strait:245 E-01-spiral:100; do
    map=${spec%%:*}; t=${spec##*:}
    d=$OUT/$v/${map:0:4}_t$t; mkdir -p $d
    FF=""; [ $t -gt 10 ] && FF="--ff=$((t-4))"
    APPDATA=C:/Users/itisf/ooze-wt/calm-pass-appdata/shots timeout 300 "$G" --path . --resolution 812x375 --audio-driver Dummy --position -6000,-6000 -- --mobile --pt-height=375 --no-notice --no-telemetry --no-account --map=res://maps4/$map.json --demo --seed=7 $FF --shots=$t --out=$d $CALM > $d/log.txt 2>&1
    echo "$v $map $t exit $? $(ls $d/*.png 2>/dev/null | head -1)"
  done
done
