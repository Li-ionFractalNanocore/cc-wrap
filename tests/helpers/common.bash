#!/usr/bin/env bash

PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
FIXTURES_DIR="$PROJECT_ROOT/tests/fixtures"

setup_test_workspace() {
  WORKDIR="$(mktemp -d "$BATS_TEST_TMPDIR/cc-wrap.XXXXXX")"
  OUTPUT_DIR="$WORKDIR/output"
  mkdir -p "$OUTPUT_DIR"
  export WORKDIR OUTPUT_DIR
}

fixture_path() {
  printf '%s/%s\n' "$FIXTURES_DIR" "$1"
}

prepare_config() {
  local fixture_name="$1"
  local destination="$WORKDIR/config.json"

  jq --arg out "$OUTPUT_DIR" '.output_dir = $out' "$(fixture_path "configs/$fixture_name")" >"$destination"
  printf '%s\n' "$destination"
}

normalize_output() {
  local text="$1"
  printf '%s\n' "${text//$OUTPUT_DIR/__OUTPUT_DIR__}"
}

assert_status_is() {
  local expected="$1"

  if [[ "$status" -ne "$expected" ]]; then
    echo "expected status $expected, got $status" >&2
    echo "$output" >&2
    return 1
  fi
}

assert_output_matches_fixture() {
  local fixture_name="$1"
  local expected actual

  expected="$(<"$(fixture_path "expected/$fixture_name")")"
  actual="$(normalize_output "$output")"

  if [[ "$actual" != "$expected" ]]; then
    echo "output mismatch for $fixture_name" >&2
    echo "--- expected ---" >&2
    printf '%s\n' "$expected" >&2
    echo "--- actual ---" >&2
    printf '%s\n' "$actual" >&2
    return 1
  fi
}

assert_file_matches_fixture() {
  local actual_path="$1"
  local fixture_name="$2"
  local expected actual

  if [[ ! -f "$actual_path" ]]; then
    echo "missing generated file: $actual_path" >&2
    return 1
  fi

  expected="$(<"$(fixture_path "expected/$fixture_name")")"
  actual="$(<"$actual_path")"

  if [[ "$actual" != "$expected" ]]; then
    echo "file mismatch for $actual_path" >&2
    echo "--- expected ---" >&2
    printf '%s\n' "$expected" >&2
    echo "--- actual ---" >&2
    printf '%s\n' "$actual" >&2
    return 1
  fi
}

assert_file_is_executable() {
  local actual_path="$1"

  if [[ ! -f "$actual_path" ]]; then
    echo "missing generated file: $actual_path" >&2
    return 1
  fi

  if [[ ! -x "$actual_path" ]]; then
    echo "generated file is not executable: $actual_path" >&2
    return 1
  fi
}

assert_generated_files() {
  local expected actual

  actual="$(find "$OUTPUT_DIR" -mindepth 1 -maxdepth 1 -type f -exec basename {} \; | sort)"
  expected="$(printf '%s\n' "$@" | sort)"

  if [[ "$actual" != "$expected" ]]; then
    echo "generated file set mismatch" >&2
    echo "--- expected ---" >&2
    printf '%s\n' "$expected" >&2
    echo "--- actual ---" >&2
    printf '%s\n' "$actual" >&2
    return 1
  fi
}
