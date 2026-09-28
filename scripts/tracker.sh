#!/usr/bin/env bash
# The tracker interface the issue-* skills call. It dispatches to
# adapters/<tracker.type>/tracker.sh (default: github); run with no arguments for the verbs.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

# Verbs every tracker shares, answered from config without the adapter.
case "${1-}" in
  statuses) print_statuses; exit 0 ;;
esac

type=$(cfg github tracker.type)
adapter="$PLUGIN_SCRIPTS/adapters/$type/tracker.sh"
if [ ! -x "$adapter" ]; then
  have=$(cd "$PLUGIN_SCRIPTS/adapters" && ls -d */ 2>/dev/null | tr -d / | tr '\n' ' ' | sed 's/ $//')
  die "no tracker adapter for tracker.type '$type' (available: ${have:-none})"
fi

exec "$adapter" "$@"
