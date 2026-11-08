#!/usr/bin/env bash
# clt-check.sh: typecheck and run the pure-logic Swift tests on a Mac that has
# only the Command Line Tools (no Xcode, so no SwiftData or Previews macros,
# no XCTest and no SwiftLint).
#
# It assembles a scratch SwiftPM package in ${TMPDIR:-/tmp}/nomi-clt-harness
# from the repo's sources, strips #Preview blocks with strip_previews.py, and
# runs `swift test` there. Exit status is swift test's.
#
# What gets compiled:
#   NomiCore       the SwiftData-free NomiCore files listed below, plus the
#                  value types above the first @Model line of each Model file,
#                  plus a stub of Category.uncategorizedID (T1, DEC-05): the
#                  marked InsightsAggregator needs that one constant
#   NomiCoreTests  the NomiCore test files listed below
#   NomiUI         Design/NomiFormatters and Design/CategoryPalette, plus every
#                  file under Packages/NomiUI/Sources carrying the line
#                  "// clt-harness: include"
#   NomiUITests, NomiApp, NomiAppTests
#                  every marked file under Packages/NomiUI/Tests,
#                  Packages/NomiApp/Sources and Packages/NomiApp/Tests; a target
#                  is left out when nothing in it is marked
#
# Needs python3 (run as `python3 -I`) and swift. Written for macOS bash 3.2.
set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 required" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
STRIP="$SCRIPT_DIR/strip_previews.py"

TMP_ROOT="${TMPDIR:-/tmp}"
TMP_ROOT="${TMP_ROOT%/}"
HARNESS="$TMP_ROOT/nomi-clt-harness"

MARKER_RE='^[[:space:]]*// clt-harness: include[[:space:]]*$'

CORE_SRC="$REPO/Packages/NomiCore/Sources/NomiCore"
CORE_TESTS="$REPO/Packages/NomiCore/Tests/NomiCoreTests"
UI_SRCS="$REPO/Packages/NomiUI/Sources"
UI_TESTS="$REPO/Packages/NomiUI/Tests"
APP_SRCS="$REPO/Packages/NomiApp/Sources"
APP_TESTS="$REPO/Packages/NomiApp/Tests"

# Paths relative to the folder named in each variable above.
CORE_FILES="Budget/BudgetAlert.swift
Budget/BudgetAlertEvaluator.swift
Contracts/CategorySuggesting.swift
Contracts/RecurringInsights.swift
Contracts/RuleScope.swift
Contracts/StorageMode.swift
Contracts/Types.swift
Support/Dedupe.swift
Support/NomiCalendar.swift
Support/PeriodRange.swift
Support/RecurrenceDetector.swift
Support/UPINarration.swift
Support/TransferGroupID.swift
Support/TransferRules.swift"

CORE_TEST_FILES="Support/RecurrenceDetectorTests.swift
Contracts/TypesTests.swift
Support/PeriodRangeTests.swift
Support/DedupeTests.swift
Support/UPINarrationTests.swift
Budget/BudgetAlertEvaluatorTests.swift
Support/TransferGroupIDTests.swift
Support/TransferRulesTests.swift"

MODEL_HEADS="Transaction Account Category Budget Rule"

# Always compiled into NomiUI, relative to Packages/NomiUI/Sources/NomiUI.
# Design/NomiColor.swift is not in the plan's list. CategoryPalette calls
# Color(hex:), and that initializer is defined in NomiColor.swift, so the
# palette does not compile without it. Flagged in the PR for Shaun to confirm.
UI_ALWAYS="Design/NomiFormatters.swift
Design/CategoryPalette.swift
Design/NomiColor.swift"

# marked_under ROOT: Swift files under ROOT carrying the marker line, printed
# relative to ROOT, sorted and de-duplicated.
marked_under() {
  if [ ! -d "$1" ]; then
    return 0
  fi
  (cd "$1" && grep -rlE --include='*.swift' "$MARKER_RE" . || true) | sed 's|^\./||' | sort -u
}

# marked_for ROOT TARGET: marked files under ROOT/TARGET, relative to TARGET.
# A marked file outside TARGET/ is an error, since it would otherwise be
# silently left out of the run.
marked_for() {
  local root="$1" target="$2" all stray
  all="$(marked_under "$root")"
  stray="$(printf '%s\n' "$all" | grep -v "^$target/" | grep -v '^$' || true)"
  if [ -n "$stray" ]; then
    echo "marked file outside $target/ under $root:" >&2
    echo "$stray" >&2
    exit 1
  fi
  printf '%s\n' "$all" | sed -n "s|^$target/||p"
}

# count_lines TEXT: number of non-empty lines.
count_lines() {
  printf '%s\n' "$1" | sed '/^$/d' | wc -l | tr -d ' '
}

# copy_swift SRC DEST: copy one Swift file, removing #Preview blocks.
copy_swift() {
  if [ ! -f "$1" ]; then
    echo "missing source file: $1" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$2")"
  python3 -I "$STRIP" "$1" "$2"
}

# copy_list SRC_DIR DEST_DIR REL_LIST: copy each relative path in REL_LIST.
copy_list() {
  local src="$1" dest="$2" rels="$3" rel
  while IFS= read -r rel; do
    if [ -z "$rel" ]; then
      continue
    fi
    copy_swift "$src/$rel" "$dest/$rel"
  done <<< "$rels"
}

# write_head MODEL_FILE DEST: the lines above the first @Model line, without
# `import SwiftData`. These are the SwiftData-free value types.
write_head() {
  if ! grep -q '^@Model' "$1"; then
    echo "no @Model line in $1" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$2")"
  awk '/^@Model/ { exit } { print }' "$1" | sed '/^import SwiftData$/d' > "$2"
}

# Start from an empty harness every run, so no stale file is compiled.
rm -rf "$HARNESS"
mkdir -p "$HARNESS"

# ---- NomiCore -------------------------------------------------------------
copy_list "$CORE_SRC" "$HARNESS/Sources/NomiCore" "$CORE_FILES"
for model in $MODEL_HEADS; do
  write_head "$CORE_SRC/Model/$model.swift" "$HARNESS/Sources/NomiCore/_head_$model.swift"
done

# Category is an @Model; InsightsAggregator needs only its uncategorizedID
# constant (InsightsAggregator.swift, one reference). T1, DEC-05.
UNCAT="$(grep -E '^[[:space:]]*public static let uncategorizedID' "$CORE_SRC/Model/Category.swift" || true)"
if [ -z "$UNCAT" ]; then
  echo "no uncategorizedID in Model/Category.swift" >&2
  exit 1
fi
printf 'import Foundation\npublic enum Category {\n%s\n}\n' "$UNCAT" > "$HARNESS/Sources/NomiCore/_stub_Category.swift"

# ---- NomiCoreTests --------------------------------------------------------
copy_list "$CORE_TESTS" "$HARNESS/Tests/NomiCoreTests" "$CORE_TEST_FILES"

# ---- NomiUI ---------------------------------------------------------------
UI_REL="$(printf '%s\n' "$UI_ALWAYS" && marked_for "$UI_SRCS" NomiUI)"
UI_REL="$(printf '%s\n' "$UI_REL" | sed '/^$/d' | sort -u)"
copy_list "$UI_SRCS/NomiUI" "$HARNESS/Sources/NomiUI" "$UI_REL"
UI_COUNT="$(count_lines "$UI_REL")"

# ---- NomiUITests ----------------------------------------------------------
UI_TEST_REL="$(marked_for "$UI_TESTS" NomiUITests | sed '/^$/d' | sort -u)"
UI_TEST_COUNT="$(count_lines "$UI_TEST_REL")"
copy_list "$UI_TESTS/NomiUITests" "$HARNESS/Tests/NomiUITests" "$UI_TEST_REL"

# ---- NomiApp, NomiAppTests (only when marked) -----------------------------
APP_REL="$(marked_for "$APP_SRCS" NomiApp | sed '/^$/d' | sort -u)"
APP_TEST_REL="$(marked_for "$APP_TESTS" NomiAppTests | sed '/^$/d' | sort -u)"
APP_COUNT="$(count_lines "$APP_REL")"
APP_TEST_COUNT="$(count_lines "$APP_TEST_REL")"
if [ "$APP_TEST_COUNT" -gt 0 ] && [ "$APP_COUNT" -eq 0 ]; then
  echo "NomiAppTests has marked files but NomiApp has none: nothing to test against" >&2
  exit 1
fi
copy_list "$APP_SRCS/NomiApp" "$HARNESS/Sources/NomiApp" "$APP_REL"
copy_list "$APP_TESTS/NomiAppTests" "$HARNESS/Tests/NomiAppTests" "$APP_TEST_REL"

# ---- Shim for SwiftPM's Bundle.module (no resources are copied) -----------
SHIM='// Generated by scripts/clt-check.sh. Stands in for SwiftPM'"'"'s Bundle.module,
// which needs resources this harness does not copy.
import Foundation

extension Bundle {
  static var module: Bundle { .main }
}
'
printf '%s' "$SHIM" > "$HARNESS/Sources/NomiUI/_CLTShim.swift"
if [ "$APP_COUNT" -gt 0 ]; then
  printf '%s' "$SHIM" > "$HARNESS/Sources/NomiApp/_CLTShim.swift"
fi

# ---- Package.swift --------------------------------------------------------
TARGETS=""
add_target() {
  if [ -n "$TARGETS" ]; then
    TARGETS="$TARGETS,
"
  fi
  TARGETS="$TARGETS    $1"
}
add_target '.target(name: "NomiCore")'
add_target '.testTarget(name: "NomiCoreTests", dependencies: ["NomiCore"])'
add_target '.target(name: "NomiUI", dependencies: ["NomiCore"])'
if [ "$UI_TEST_COUNT" -gt 0 ]; then
  add_target '.testTarget(name: "NomiUITests", dependencies: ["NomiUI"])'
fi
if [ "$APP_COUNT" -gt 0 ]; then
  add_target '.target(name: "NomiApp", dependencies: ["NomiCore", "NomiUI"])'
fi
if [ "$APP_TEST_COUNT" -gt 0 ]; then
  add_target '.testTarget(name: "NomiAppTests", dependencies: ["NomiApp"])'
fi

{
  printf '%s\n' '// swift-tools-version: 5.10' 'import PackageDescription' '' 'let package = Package(' '  name: "NomiCLTHarness",' '  platforms: [.macOS(.v14)],' '  targets: ['
  printf '%s\n' "$TARGETS"
  printf '%s\n' '  ]' ')'
} > "$HARNESS/Package.swift"

echo "clt-check: harness at $HARNESS"
echo "clt-check: NomiCore $(count_lines "$CORE_FILES") files + 5 model heads; NomiCoreTests $(count_lines "$CORE_TEST_FILES") files; NomiUI $UI_COUNT files; NomiUITests $UI_TEST_COUNT files; NomiApp $APP_COUNT files; NomiAppTests $APP_TEST_COUNT files"

# ---- Run ------------------------------------------------------------------
cd "$HARNESS"
status=0
XCODE_DEV="$(xcode-select -p 2>/dev/null || true)"
if [ "$XCODE_DEV" = "/Library/Developer/CommandLineTools" ]; then
  FW=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
  PLUGINS=/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
  swift test --build-system native \
    -Xswiftc -F -Xswiftc "$FW" \
    -Xlinker -F -Xlinker "$FW" \
    -Xlinker -rpath -Xlinker "$FW" \
    -Xswiftc -plugin-path -Xswiftc "$PLUGINS" || status=$?
else
  # Xcode is selected and finds the testing frameworks itself.
  swift test --build-system native || status=$?
fi
exit "$status"
