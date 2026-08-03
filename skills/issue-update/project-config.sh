#!/usr/bin/env bash
# Read one value out of the consuming repo's .agent/project.yml.
#
# Usage:
#   project-config.sh <section.key>             Print the value; error if it is absent
#   project-config.sh <section.key> <default>   Print the value, or <default> if absent
#
# Examples:
#   repo=$(project-config.sh github.repo)
#   test_cmd=$(project-config.sh conventions.test_command "")
#
# Schema — .agent/project.yml, committed to each repo that uses these skills:
#
#   github:
#     owner: <login>                  # required  Projects v2 board owner (user or org)
#     repo: <owner>/<name>            # required  repo the issues live in
#     project_title: "<Board title>"  # required  Projects v2 board title
#     assignee: <login>               # required  human reviewer PRs are assigned to
#   conventions:
#     test_command: <shell command>   # optional
#     lint_command: <shell command>   # optional
#     test_notes: "<free text>"       # optional  context for reading a test run
#   deploy:
#     skill: <skill name>             # optional  project-specific release skill
#
# Supported YAML subset — deliberately tiny, so the dependencies stay bash + awk (plus jq
# and gh for the board scripts):
#   * exactly two levels: a top-level section, then indented `key: value` scalars
#   * only keys at the section's *first* indent level are visible — the indent of the first
#     key under a section sets that level (2 spaces by convention), and anything indented
#     deeper is treated as unsupported nesting and never matches
#   * values may be bare, "double quoted", or 'single quoted' (no escapes inside quotes)
#   * `#` starts a comment on its own line, or after whitespace in a bare value
#   * NOT supported: lists, deeper nesting, multi-line scalars, anchors, multiple documents
#
# The file is located from the current git repo (`git rev-parse --show-toplevel`), falling
# back to walking up from $PWD. A missing file is always fatal; a missing key is fatal
# unless a default argument was supplied.
#
# Sourcing this file defines project_config_file() and project_config(), and — like every
# script here — turns on `set -euo pipefail` in the sourcing shell.
set -euo pipefail

PROJECT_CONFIG_REL=${PROJECT_CONFIG_REL:-.agent/project.yml}

# Two-level `key: value` reader. Exits 3 when the key is not present.
PROJECT_CONFIG_AWK='
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function indent_of(s) { sub(/[^ \t].*$/, "", s); return s }
BEGIN { in_sect = 0; found = 0; have_indent = 0; sect_indent = "" }
{
  line = $0
  sub(/\r$/, "", line)
  if (line ~ /^[ \t]*$/ || line ~ /^[ \t]*#/) next
  if (line ~ /^[^ \t]/) {                    # top-level: a section header
    name = line; sub(/:.*$/, "", name)
    in_sect = (trim(name) == sect)
    have_indent = 0; sect_indent = ""        # first key in the section sets its indent level
    next
  }
  if (!in_sect || index(line, ":") == 0) next
  ind = indent_of(line)
  if (!have_indent) { sect_indent = ind; have_indent = 1 }
  if (ind != sect_indent) next               # deeper nesting is unsupported — never matches
  name = line; sub(/:.*$/, "", name)
  if (trim(name) != key) next
  val = line; sub(/^[^:]*:/, "", val); val = trim(val)
  q = substr(val, 1, 1)
  if (q == "\"" || q == "\047") {            # quoted: take up to the closing quote
    val = substr(val, 2)
    p = index(val, q)
    if (p > 0) val = substr(val, 1, p - 1)
  } else {                                   # bare: drop a trailing " # comment"
    sub(/[ \t]+#.*$/, "", val)
    val = trim(val)
  }
  print val
  found = 1
  exit
}
END { if (!found) exit 3 }
'

# Print this file's whole header comment block (usage, examples, schema) — no truncation.
project_config_usage() {
  awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}"
}

# Print the path of the nearest .agent/project.yml, or fail with a clear message.
project_config_file() {
  local rel=$PROJECT_CONFIG_REL root dir
  if root=$(git rev-parse --show-toplevel 2>/dev/null) && [ -n "$root" ] && [ -f "$root/$rel" ]; then
    printf '%s\n' "$root/$rel"
    return 0
  fi
  dir=$PWD
  while :; do
    if [ -f "$dir/$rel" ]; then
      printf '%s\n' "$dir/$rel"
      return 0
    fi
    [ "$dir" = / ] && break
    dir=$(dirname "$dir")
  done
  echo "project-config.sh: no $rel found from $PWD — create it in the repo root (schema: agent-skills README)" >&2
  return 1
}

# project_config <section.key> [default]
project_config() {
  local dotted=${1-} default='' have_default=0 file section key value rc

  if [ $# -ge 2 ]; then have_default=1; default=$2; fi

  if [ -z "$dotted" ] || [ "${dotted#*.}" = "$dotted" ] || [ "${dotted#*.*.}" != "$dotted" ]; then
    echo "project-config.sh: expected a two-level key such as 'github.repo', got '$dotted'" >&2
    return 2
  fi
  section=${dotted%%.*}
  key=${dotted#*.}

  file=$(project_config_file) || return 1

  value=$(awk -v sect="$section" -v key="$key" "$PROJECT_CONFIG_AWK" "$file") && rc=0 || rc=$?

  if [ "$rc" -eq 0 ]; then
    printf '%s\n' "$value"
    return 0
  fi
  if [ "$rc" -ne 3 ]; then
    echo "project-config.sh: could not read $file" >&2
    return 1
  fi
  if [ "$have_default" -eq 1 ]; then
    printf '%s\n' "$default"
    return 0
  fi
  echo "project-config.sh: key '$dotted' is not set in $file" >&2
  return 1
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  [ $# -ge 1 ] || { project_config_usage; exit 2; }
  project_config "$@"
fi
