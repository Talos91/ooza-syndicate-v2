#!/usr/bin/env bash
# One headless suite, judged against the line's known failures. Used by CI (.github/workflows/suites.yml) and locally:
#   tools/ci/run_suite.sh <suite>            e.g. sim, net, maps4, map_pool, round_r, ui_kit, ai_curve
#   GODOT=<Godot 4.6.1 binary> (default: godot on PATH)   CAP=<timeout in s> (default 900)   LINE=main|proto|demo
# The line comes from Rules.VERSION ("-proto" -> proto, "-demo" -> demo, else main) unless LINE is set.
#   tools/ci/baseline/<line>/<suite>.txt   FAIL lines that are known and allowed (exactly as printed, one per line)
#   tools/ci/baseline/<line>/nonblocking   suites that are reported but never fail the run (one name per line)
# Exit 0 = no new FAIL line. A timeout, or a non-zero exit without any FAIL line (a crash), fails unless nonblocking.
# Logs: ci-logs/test_<suite>.log, plus <suite>.fails / .new / .gone (known lines that no longer fail: trim the baseline).
set -uo pipefail
suite="${1:?usage: tools/ci/run_suite.sh <suite>}"
GODOT="${GODOT:-godot}"
CAP="${CAP:-900}"
cd "$(dirname "$0")/../.."
logs="ci-logs"
mkdir -p "$logs"
log="$logs/test_$suite.log"
summary="${GITHUB_STEP_SUMMARY:-/dev/null}"

if [ -z "${LINE:-}" ]; then
	ver=$(sed -n 's/^const VERSION := "\([^"]*\)".*/\1/p' scripts/rules.gd)
	case "$ver" in
		*-proto*) LINE=proto ;;
		*-demo*) LINE=demo ;;
		*) LINE=main ;;
	esac
fi
base="tools/ci/baseline/$LINE"

if [ ! -f "tests/test_$suite.gd" ]; then
	echo "SKIP $suite: tests/test_$suite.gd is not on this branch" | tee -a "$summary"
	exit 0
fi

start=$(date +%s)
timeout "$CAP" "$GODOT" --headless --path . --script "res://tests/test_$suite.gd" > "$log" 2>&1
code=$?
secs=$(( $(date +%s) - start ))

clean() { sed 's/\r$//; s/[[:space:]]*$//' | grep -v '^$' | sort -u; }
grep -E '^FAIL' "$log" | clean > "$logs/$suite.fails"
if [ -f "$base/$suite.txt" ]; then clean < "$base/$suite.txt" > "$logs/$suite.known"; else : > "$logs/$suite.known"; fi
comm -23 "$logs/$suite.fails" "$logs/$suite.known" > "$logs/$suite.new"
comm -13 "$logs/$suite.fails" "$logs/$suite.known" > "$logs/$suite.gone"
nonblocking=0
if [ -f "$base/nonblocking" ] && sed 's/\r$//' "$base/nonblocking" | grep -qx "$suite"; then nonblocking=1; fi

total=$(wc -l < "$logs/$suite.fails")
new=$(wc -l < "$logs/$suite.new")
gone=$(wc -l < "$logs/$suite.gone")
verdict=ok
if [ "$code" -eq 124 ]; then
	verdict="timeout after ${CAP} s"
elif [ "$new" -gt 0 ]; then
	verdict="$new new FAIL line(s)"
elif [ "$code" -ne 0 ] && [ "$total" -eq 0 ]; then
	verdict="exit $code without FAIL lines (crash?)"
fi

line="$suite [$LINE]: exit $code in ${secs} s, $total FAIL ($new new, $gone known no longer failing) -> $verdict"
[ "$nonblocking" -eq 1 ] && line="$line (nonblocking)"
echo "$line"
echo "- $line" >> "$summary"
if [ "$new" -gt 0 ]; then
	echo "New FAIL lines ($suite):"
	head -n 40 "$logs/$suite.new"
	{ echo '```'; head -n 40 "$logs/$suite.new"; echo '```'; } >> "$summary"
fi
if [ "$gone" -gt 0 ]; then
	echo "Known FAIL lines that passed this time - remove them from $base/$suite.txt:"
	head -n 40 "$logs/$suite.gone"
fi

if [ "$verdict" != ok ] && [ "$nonblocking" -eq 0 ]; then exit 1; fi
exit 0
