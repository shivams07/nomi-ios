#!/usr/bin/env bash
# ui-gates.sh: grep gates for the blue/light restyle. Prints one line per gate,
# "G<n> <count>", for G1-G8. Patterns and baselines come from the build plan
# (nomi-ios-build-plan.md, "Grep gates"), measured on 626debe. G8 comes from
# DEC-07 (nomi-ios-decisions.md): a drift guard that fails when networking code
# appears in a Sources file, so the About privacy sentence gets re-read.
#
# Usage: scripts/ui-gates.sh [--require-zero G1,G2,...] [--files path...]
#   --files         count only in these paths (relative to the repo root)
#   --require-zero  exit 1 if any listed gate has a non-zero count
#
# Default scope is Packages/*/Sources/*.swift. git grep searches the tracked
# files as they are in the working tree.
#
# G6 and G7 skip doc-comment lines (a line whose code starts with ///). G6 does
# so by the plan. G7 does so because its baseline of 1 is reached only that way:
# the literal pattern also matches a doc comment in HeroTotalCard.swift. No
# other gate has doc-comment hits, so the filter changes nothing else.
set -euo pipefail

usage() {
  echo "usage: scripts/ui-gates.sh [--require-zero G1,G2,...] [--files path...]" >&2
  exit "${1:-2}"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO"

require=""
files_given=0
files=""
while [ $# -gt 0 ]; do
  case "$1" in
    --require-zero)
      if [ $# -lt 2 ]; then
        usage
      fi
      require="$2"
      shift 2
      ;;
    --require-zero=*)
      require="${1#--require-zero=}"
      shift
      ;;
    --files)
      files_given=1
      shift
      while [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; do
        files="$files
$1"
        shift
      done
      ;;
    -h|--help)
      usage 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage
      ;;
  esac
done

# SCOPE is a newline list of git pathspecs. It is never empty.
if [ "$files_given" -eq 1 ]; then
  SCOPE="$(printf '%s\n' "$files" | sed '/^$/d')"
  if [ -z "$SCOPE" ]; then
    echo "--files needs at least one path" >&2
    usage
  fi
else
  SCOPE='Packages/*/Sources/*.swift'
fi

DESIGN_OUT=':(exclude)Packages/NomiUI/Sources/NomiUI/Design/*'
DOC_LINE='^[^:]+:[0-9]+:[[:space:]]*///'

# gate_hits G<n>: "path:line:text" lines that match one gate in the scope.
gate_hits() {
  local -a sc=()
  local p
  while IFS= read -r p; do
    if [ -n "$p" ]; then
      sc+=("$p")
    fi
  done <<< "$SCOPE"
  case "$1" in
    G1)
      git grep -n -E 'Color\.(white|black)|Color\(hex:|Color\(red:|Color\(white:' -- "${sc[@]}" "$DESIGN_OUT" || true ;;
    G2)
      git grep -n -E '\.font\(\.system\(size' -- "${sc[@]}" || true ;;
    G3)
      git grep -n -F 'onTapGesture' -- "${sc[@]}" || true ;;
    G4)
      git grep -n -F 'preferredColorScheme(.dark)' -- "${sc[@]}" || true ;;
    G5)
      git grep -n -F 'montserrat' -- "${sc[@]}" "$DESIGN_OUT" || true ;;
    G6)
      git grep -n -P 'NomiColor\.(accent|overBudget|debitText|creditText|textQuaternary|glassFill|glassHairline|progressTrackFill|surfaceRow|surfaceInput)\b' \
        -- "${sc[@]}" "$DESIGN_OUT" | grep -vE "$DOC_LINE" || true ;;
    G7)
      git grep -n -F -e 'NomiTextStyle.dashboardHeroTotal' -e 'nomiTextStyle(.dashboardHeroTotal)' \
        -- "${sc[@]}" | grep -vE "$DOC_LINE" || true ;;
    G8)
      git grep -n -E 'URLSession|URLRequest' -- "${sc[@]}" || true ;;
  esac
}

GATES="G1 G2 G3 G4 G5 G6 G7 G8"
COUNTS=""
for g in $GATES; do
  n="$(gate_hits "$g" | grep -c '' || true)"
  echo "$g $n"
  COUNTS="$COUNTS$g $n
"
done

status=0
if [ -n "$require" ]; then
  for want in $(printf '%s' "$require" | tr ',' ' '); do
    case " $GATES " in
      *" $want "*) ;;
      *)
        echo "unknown gate in --require-zero: $want" >&2
        exit 2
        ;;
    esac
    n="$(printf '%s' "$COUNTS" | awk -v g="$want" '$1 == g { print $2 }')"
    if [ "$n" != "0" ]; then
      echo "FAIL $want: $n matches, must be 0" >&2
      status=1
    fi
  done
fi
exit "$status"
