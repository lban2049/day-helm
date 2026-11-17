#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

STEP_NAMES=()
STEP_STATUSES=()
STEP_DETAILS=()
OVERALL_FAILED=0

record_step() {
  local name="$1"
  local status="$2"
  local detail="$3"
  STEP_NAMES+=("$name")
  STEP_STATUSES+=("$status")
  STEP_DETAILS+=("$detail")
  if [[ "$status" != "PASS" ]]; then
    OVERALL_FAILED=1
  fi
}

echo "============================================================"
echo " DayHelm (日舵) Unified Test & Verification Runner"
echo " Repo: $REPO_ROOT"
echo "============================================================"

# 1. Static Architectural Boundary Check
echo ""
echo "[1/4] Checking DayHelmCore architectural boundaries..."
BOUNDARY_HITS="$(grep -rnE '^\s*(import\s+(AppKit|SwiftUI)\b|@_exported\s+import\s+(AppKit|SwiftUI)\b)' Sources/DayHelmCore/ || true)"
if [[ -z "$BOUNDARY_HITS" ]]; then
  echo "  PASS: Zero AppKit/SwiftUI imports in Sources/DayHelmCore/"
  record_step "1. Boundary Check" "PASS" "0 AppKit/SwiftUI imports in DayHelmCore"
else
  echo "  FAIL: Forbidden UI framework imports found in Sources/DayHelmCore/:"
  echo "$BOUNDARY_HITS"
  record_step "1. Boundary Check" "FAIL" "Forbidden UI imports in DayHelmCore"
fi

# 2. Clean/Full Build with Zero-Warning Verification
echo ""
echo "[2/4] Building all Swift targets (zero warnings enforced)..."
BUILD_LOG="$(mktemp -t dayhelm-build.XXXXXX)"
trap 'rm -f "$BUILD_LOG"' EXIT

if swift build 2>&1 | tee "$BUILD_LOG"; then
  WARNING_LINES="$(grep -E '(^|:[0-9]+:[0-9]+: )warning:' "$BUILD_LOG" || true)"
  if [[ -z "$WARNING_LINES" ]]; then
    echo "  PASS: swift build succeeded with 0 warnings"
    record_step "2. Swift Build" "PASS" "All targets built with 0 warnings"
  else
    echo "  FAIL: Compiler warnings detected during swift build:"
    echo "$WARNING_LINES"
    record_step "2. Swift Build" "FAIL" "Compiler warnings detected"
  fi
else
  echo "  FAIL: swift build exited with non-zero status"
  record_step "2. Swift Build" "FAIL" "Build failed"
fi

# 3. DayHelmChecks (30 Unit + Integration + E2E Checks)
echo ""
echo "[3/4] Running swift run DayHelmChecks..."
if swift run DayHelmChecks; then
  record_step "3. DayHelmChecks" "PASS" "30/30 checks passed"
else
  record_step "3. DayHelmChecks" "FAIL" "DayHelmChecks exited non-zero"
fi

# 4. Native swift test (Testing.framework / XCTest)
echo ""
echo "[4/4] Running native swift test..."
CLT_FRAMEWORKS="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
CLT_TESTING_INC="/Library/Developer/CommandLineTools/usr/lib/swift/macosx/testing"
CLT_USRLIB="/Library/Developer/CommandLineTools/Library/Developer/usr/lib"

TEST_LOG="$(mktemp -t dayhelm-test.XXXXXX)"
trap 'rm -f "$BUILD_LOG" "$TEST_LOG"' EXIT

if [[ -d "$CLT_FRAMEWORKS/Testing.framework" ]]; then
  swift test \
    -Xswiftc "-F$CLT_FRAMEWORKS" \
    -Xswiftc "-I$CLT_TESTING_INC" \
    -Xlinker "-F$CLT_FRAMEWORKS" \
    -Xlinker -rpath -Xlinker "$CLT_FRAMEWORKS" \
    -Xlinker -rpath -Xlinker "$CLT_USRLIB" 2>&1 | tee "$TEST_LOG"
  TEST_RC=${PIPESTATUS[0]}
else
  swift test 2>&1 | tee "$TEST_LOG"
  TEST_RC=${PIPESTATUS[0]}
fi

if [[ "$TEST_RC" -eq 0 ]]; then
  TEST_SUMMARY="$(grep -Eo 'Test run with [0-9]+ tests? in [0-9]+ suites? passed[^!]*!' "$TEST_LOG" | tail -n 1 || true)"
  if [[ -z "$TEST_SUMMARY" ]]; then
    TEST_SUMMARY="$(grep -Eo 'Executed [0-9]+ tests?, with 0 failures' "$TEST_LOG" | tail -n 1 || echo "swift test passed")"
  fi
  record_step "4. Swift Test" "PASS" "$TEST_SUMMARY"
else
  record_step "4. Swift Test" "FAIL" "swift test exited with $TEST_RC"
fi

echo ""
echo "============================================================"
echo " Summary"
echo "------------------------------------------------------------"
printf " %-22s | %-6s | %s\n" "Stage" "Result" "Details"
echo "------------------------+--------+--------------------------"
for i in "${!STEP_NAMES[@]}"; do
  printf " %-22s | %-6s | %s\n" "${STEP_NAMES[$i]}" "${STEP_STATUSES[$i]}" "${STEP_DETAILS[$i]}"
done
echo "============================================================"

exit "$OVERALL_FAILED"
