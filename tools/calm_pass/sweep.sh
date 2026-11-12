#!/bin/bash
# usage: sweep.sh <profile>  -> before (off) then after (on); output calm-pass-out/sweep/<profile>-<off|on>.txt
G="/h/My Drive/PROJECTS/Ooze Syndicate/Tools/Godot/Godot_v4.6.1-stable_win64_console.exe"
OUT=C:/Users/itisf/ooze-wt/calm-pass-out/sweep
mkdir -p "$OUT"
cd /c/Users/itisf/ooze-wt/calm-pass
case $1 in
  phone) R=812x375; X="--mobile --pt-height=375";;
  notch) R=812x375; X="--mobile --pt-height=375 --safe-insets=84,0,84,40";;
  duo) R=720x540; X="--mobile --pt-height=540";;
  fold-cover) R=840x360; X="--mobile --pt-height=360";;
  fold-inner) R=1092x984; X="--mobile --pt-height=984";;
esac
for m in ${MODES:-off on}; do
  APPDATA=C:/Users/itisf/ooze-wt/calm-pass-appdata/$1 timeout 3000 "$G" --path . --resolution $R --audio-driver Dummy --position -6000,-6000 res://tests/top_band_probe.tscn -- $X --no-notice --no-telemetry --top-band=$m tag=$1-$m out=$OUT/$1-$m.txt ${SHOTS:+shots=$OUT/shots-$1-$m} > $OUT/$1-$m.log 2>&1
  echo "$1-$m exit $?"
done
