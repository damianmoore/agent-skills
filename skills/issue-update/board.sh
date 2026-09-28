#!/usr/bin/env bash
# Compatibility shim — the board now lives behind scripts/tracker.sh. Kept so older docs and
# project skills that call board.sh keep working; new text should call tracker.sh directly.
#
#   board.sh add <issue>              -> tracker.sh add <issue>
#   board.sh status <issue> <column>  -> tracker.sh set-status <issue> <column>
#   board.sh show <issue>             -> the card's column
#   board.sh list <column>            -> tracker.sh list <column>
set -euo pipefail
T="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/tracker.sh"
[ $# -ge 2 ] || { sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
case "$1" in
  add)    exec "$T" add "$2" ;;
  status) [ $# -ge 3 ] || { echo "usage: board.sh status <issue> <column>" >&2; exit 1; }; exec "$T" set-status "$2" "$3" ;;
  show)   "$T" status "$2" | cut -f2 ;;
  list)   exec "$T" list "$2" ;;
  *)      echo "board.sh: unknown command '$1'" >&2; exit 1 ;;
esac
