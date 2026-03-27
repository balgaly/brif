#!/usr/bin/env bash
# test/helpers.sh — minimal test harness for shell scripts

TESTS_PASSED=0
TESTS_FAILED=0

assert_contains() {
  local label="$1" output="$2" expected="$3"
  if echo "$output" | grep -qF "$expected"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "FAIL: $label"
    echo "  expected to contain: $expected"
    echo "  got: $(echo "$output" | head -5)"
  fi
}

assert_not_contains() {
  local label="$1" output="$2" unexpected="$3"
  if ! echo "$output" | grep -qF "$unexpected"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "FAIL: $label"
    echo "  expected NOT to contain: $unexpected"
  fi
}

assert_exit_code() {
  local label="$1" actual="$2" expected="$3"
  if [[ "$actual" -eq "$expected" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "FAIL: $label"
    echo "  expected exit code: $expected, got: $actual"
  fi
}

run_with_mock() {
  local script="$1" fixture="$2"
  cat "$fixture" | bash "$script" 2>/dev/null
}

print_summary() {
  echo ""
  echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed"
  if [[ "$TESTS_FAILED" -gt 0 ]]; then
    exit 1
  fi
}
