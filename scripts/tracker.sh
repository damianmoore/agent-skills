#!/usr/bin/env bash
# The tracker interface the issue-* skills call. It dispatches to
# adapters/<tracker.type>/tracker.sh (default: github); run with no arguments for the verbs.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

# Verbs every tracker shares, answered from config without the adapter.
case "${1-}" in
  statuses) print_statuses; exit 0 ;;
  # score-preview <R> <I> <C> <E> <radius> [type]: what set-score would store, without writing.
  score-preview) shift; [ $# -ge 5 ] || die "usage: score-preview <R> <I> <C> <E> <radius> [type]"
    score_compute "$1" "$2" "$3" "$4" "$5" "${6-}"; exit 0 ;;
esac

type=$(cfg github tracker.type)
adapter="$PLUGIN_SCRIPTS/adapters/$type/tracker.sh"
if [ ! -x "$adapter" ]; then
  have=$(cd "$PLUGIN_SCRIPTS/adapters" && ls -d */ 2>/dev/null | tr -d / | tr '\n' ' ' | sed 's/ $//')
  die "no tracker adapter for tracker.type '$type' (available: ${have:-none})"
fi

# set-score: the score arithmetic is shared (lib.sh score_compute), so it is done here and only
# the storage is the adapter's (write-score). A score whose basis starts "Pinned" is the
# person's call and is never overwritten.
if [ "${1-}" = set-score ]; then
  shift
  [ $# -ge 7 ] || die "usage: set-score <id> <reach 1-5> <impact 3|2|1|0.5|0.25> <confidence 100|80|50> <effort 1-5> <critical|wide|limited|contained> <reason>"
  id=$1 r=$2 i=$3 c=$4 e=$5 radius=$6; shift 6
  reason=$(printf '%s' "$*" | tr '\t\r\n' '   ' | cut -c1-200)
  [ -n "$(cfg "" scoring.skill)" ] || { echo "no scoring.skill configured — skipped"; exit 0; }
  computed=$(score_compute "$r" "$i" "$c" "$e" "$radius" "")   # validate before any API call
  current=$("$adapter" score "$id")
  case "$(cut -f4 <<<"$current")" in
    Pinned*) echo "#${id#\#} is pinned ($(cut -f1 <<<"$current"), $(cut -f4 <<<"$current")) — left as it is"; exit 0 ;;
  esac
  type=$("$adapter" view "$id" | jq -r '[.labels[] | select(. == "feat" or . == "fix" or . == "chore" or . == "refactor")][0] // ""')
  computed=$(score_compute "$r" "$i" "$c" "$e" "$radius" "$type")
  IFS=$'\t' read -r priority score radius_name <<<"$computed"
  basis="R$r I$i C$c E$e — ${reason:-no reason given} (scored $(date +%F))"
  exec "$adapter" write-score "$id" "$priority" "$score" "$radius_name" "$basis"
fi

exec "$adapter" "$@"
