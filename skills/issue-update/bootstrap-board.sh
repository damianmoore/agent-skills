#!/usr/bin/env bash
# Compatibility shim for `tracker.sh bootstrap` — run from inside the repo being onboarded.
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/tracker.sh" bootstrap "$@"
