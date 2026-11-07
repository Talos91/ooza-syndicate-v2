#!/bin/bash
# full headless suite ONCE on the assembled release branch (Release worker 0.23.14). Usage: suites.sh
R="C:/Users/itisf/ooze-wt/rel"; L="C:/Users/itisf/ooze-wt/rel-logs"
G="H:/My Drive/PROJECTS/Ooze Syndicate/Tools/Godot/Godot_v4.6.1-stable_win64_console.exe"
cd "$R"
for i in 1 2; do timeout 900 "$G" --headless --import --path . > "$L/import_$i.log" 2>&1; echo "import $i exit=$?"; done
run() { cap=900; case "$1" in ai_curve|ai_coop) cap=2000;; esac; timeout $cap "$G" --headless --path . --script res://tests/test_$1.gd > "$L/t_$1.log" 2>&1; e=$?
  echo "$1 exit=$e $(grep -E 'ALL PASSED|PASS|FAIL|failed|SKIP' "$L/t_$1.log" | tail -1)"; }
lane() { for t in "$@"; do run $t; done; }
lane sim ai_curve tutorial campaign mission > "$L/lane1.txt" &
lane ai_coop > "$L/lane5.txt" &
lane map_pool progression account telemetry match_report > "$L/lane2.txt" &
lane net maps4 powers_ai preempt rematch room_limits ui_kit kit_hd map_batch_swap relay dedicated > "$L/lane3.txt" &
wait
timeout 900 "$G" --headless --path . res://tests/test_campaign_page.tscn > "$L/t_campaign_page.log" 2>&1; echo "campaign_page(tscn) exit=$? $(grep -E 'ALL PASSED|FAIL|failed' "$L/t_campaign_page.log" | tail -1)" > "$L/lane4.txt"
cat "$L"/lane*.txt
echo SUITES_DONE
