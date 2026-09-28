#!/usr/bin/env bash
# The forge interface the issue-* skills call. It dispatches to
# adapters/<forge.type>/forge.sh (default: github); run with no arguments for the verbs.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

type=$(cfg github forge.type)
adapter="$PLUGIN_SCRIPTS/adapters/$type/forge.sh"
if [ ! -x "$adapter" ]; then
  have=$(cd "$PLUGIN_SCRIPTS/adapters" && ls -d */ 2>/dev/null | tr -d / | tr '\n' ' ' | sed 's/ $//')
  die "no forge adapter for forge.type '$type' (available: ${have:-none})"
fi
exec "$adapter" "$@"
