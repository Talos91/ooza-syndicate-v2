#!/usr/bin/env bash
# After a gh-pages publish (workflow .github/workflows/published.yml), for each environment folder:
#   1. read what it holds from the last gh-pages commit that changed its index.pck - the publish scripts write
#      "<folder> = <version> (<branch> <sha>)" (live: "LIVE <version> (<branch> <sha>)");
#   2. check that the live site serves exactly that index.pck (Content-Length = size in git; Pages can lag, so it retries);
#   3. tag the source commit v<version> and write a GitHub Release with the facts (skipped if the release exists).
# DRY=1 does 1 and 2 only. Needs: origin/gh-pages history (blobs not needed), curl, gh with GH_TOKEN, GITHUB_REPOSITORY.
set -uo pipefail
REPO="${GITHUB_REPOSITORY:?}"
SITE="${SITE:-https://oozesyndicate.com}"
DRY="${DRY:-0}"
WAIT="${WAIT:-600}"
summary="${GITHUB_STEP_SUMMARY:-/dev/null}"
fail=0

{ echo "| env | version | source | gh-pages | index.pck (git) | live | release |"; echo "|---|---|---|---|---|---|---|"; } >> "$summary"

live_size() { curl -sI "$1" | tr -d '\r' | awk 'tolower($1) == "content-length:" { print $2 }' | tail -n 1; }

for env in live staging proto demo; do
	case "$env" in
		live) dir="" ;;
		staging) dir="staging/" ;;
		proto) dir="staging/proto/" ;;
		demo) dir="staging/demo/" ;;
	esac
	pck="${dir}index.pck"
	url="$SITE/$dir"
	gp=$(git log -1 --format=%h origin/gh-pages -- "$pck")
	if [ -z "$gp" ]; then echo "$env: no $pck on gh-pages"; continue; fi
	msg=$(git log -1 --format=%s "$gp")
	hit=$(grep -oE '(=|LIVE) [0-9][0-9A-Za-z.-]* \([^ ]+ [0-9a-f]{7,40}' <<<"$msg" | head -n 1)
	ver=$(sed -E 's/^(=|LIVE) ([^ ]+) .*/\2/' <<<"$hit")
	branch=$(sed -E 's/^(=|LIVE) [^ ]+ \(([^ ]+) .*/\2/' <<<"$hit")
	src=$(sed -E 's/.* ([0-9a-f]{7,40})$/\1/' <<<"$hit")
	if [ -z "$hit" ]; then
		echo "$env: cannot read version / source from gh-pages $gp: $msg"
		echo "| $env | ? | ? | $gp | ? | not checked | message not in the publish format |" >> "$summary"
		fail=1
		continue
	fi
	size=$(gh api -H "Accept: application/vnd.github.object" "repos/$REPO/contents/${pck}?ref=$gp" --jq .size)
	full=$(gh api "repos/$REPO/commits/$src" --jq .sha)

	served=""
	waited=0
	while :; do
		served=$(live_size "${url}index.pck")
		[ "$served" = "$size" ] && break
		[ "$waited" -ge "$WAIT" ] && break
		sleep 30
		waited=$((waited + 30))
	done
	if [ "$served" = "$size" ]; then live="ok"; else live="MISMATCH (serves ${served:-nothing})"; fail=1; fi

	tag="v$ver"
	rel="dry run"
	if [ "$DRY" != "1" ] && [ "$live" = "ok" ]; then
		if gh release view "$tag" -R "$REPO" > /dev/null 2>&1; then
			rel="exists"
		else
			notes="Published to **$env** - $url
Source: \`$branch\` $full
gh-pages: $gp - index.pck $size bytes, served by the live site (checked $(date -u +%Y-%m-%dT%H:%MZ))"
			if [ "$env" = live ]; then flags=(--latest); else flags=(--prerelease --latest=false); fi
			if gh release create "$tag" -R "$REPO" --target "$full" --title "$ver ($env)" --notes "$notes" "${flags[@]}" > /dev/null; then
				rel="created"
			else
				rel="FAILED"
				fail=1
			fi
		fi
	fi
	line="$env: $ver from $branch ${full:0:7}, gh-pages $gp, index.pck $size, live $live, release $tag $rel"
	echo "$line"
	echo "| $env | $ver | \`$branch\` ${full:0:7} | $gp | $size | $live | $tag $rel |" >> "$summary"
done
exit "$fail"
