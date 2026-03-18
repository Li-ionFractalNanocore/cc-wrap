#!/usr/bin/env bats

load 'helpers/common'

setup() {
  setup_test_workspace
}

@test "uninstall removes an existing managed wrapper script" {
  local config
  config="$(prepare_config "complete-single.json")"

  cp "$(fixture_path "expected/deploy/complete-single/basic-code")" "$OUTPUT_DIR/basic-code"
  chmod 755 "$OUTPUT_DIR/basic-code"

  run "$PROJECT_ROOT/cc-wrap" uninstall --config "$config"

  assert_status_is 0
  assert_output_matches_fixture "uninstall/complete-single/stdout.txt"
  [[ ! -e "$OUTPUT_DIR/basic-code" ]]
}

@test "uninstall removes both managed scripts for the multi-provider fixture" {
  local config
  config="$(prepare_config "complete-multi.json")"

  cp "$(fixture_path "expected/deploy/complete-multi/glm-code")" "$OUTPUT_DIR/glm-code"
  cp "$(fixture_path "expected/deploy/complete-multi/or-code")" "$OUTPUT_DIR/or-code"
  chmod 755 "$OUTPUT_DIR/glm-code" "$OUTPUT_DIR/or-code"

  run "$PROJECT_ROOT/cc-wrap" uninstall --config "$config"

  assert_status_is 0
  assert_output_matches_fixture "uninstall/complete-multi/stdout.txt"
  [[ ! -e "$OUTPUT_DIR/glm-code" ]]
  [[ ! -e "$OUTPUT_DIR/or-code" ]]
}

@test "uninstall skips unmanaged files, reports missing files, and continues" {
  local base_config config original_content original_file
  base_config="$(prepare_config "complete-multi.json")"
  config="$WORKDIR/uninstall-mixed.json"
  original_content=$'#!/bin/bash\n# user-managed script\necho custom\n'
  original_file="$WORKDIR/original-or-code"

  jq '.providers += [{"script_name":"missing-code","env":{"ANTHROPIC_BASE_URL":"https://example.com","ANTHROPIC_AUTH_TOKEN":"token"}}]' "$base_config" >"$config"

  cp "$(fixture_path "expected/deploy/complete-multi/glm-code")" "$OUTPUT_DIR/glm-code"
  printf '%s' "$original_content" >"$OUTPUT_DIR/or-code"
  printf '%s' "$original_content" >"$original_file"
  chmod 755 "$OUTPUT_DIR/glm-code"
  chmod 644 "$OUTPUT_DIR/or-code"

  run "$PROJECT_ROOT/cc-wrap" uninstall --config "$config"

  assert_status_is 0
  assert_output_contains "Skipped existing unmanaged file: $OUTPUT_DIR/or-code"
  assert_output_contains "Missing file: $OUTPUT_DIR/missing-code"
  assert_output_contains "Removed 1 wrapper script(s) from $OUTPUT_DIR"
  assert_output_contains "Skipped 1 existing unmanaged file(s)"
  assert_output_contains "Missing 1 file(s)"
  [[ ! -e "$OUTPUT_DIR/glm-code" ]]
  cmp -s "$OUTPUT_DIR/or-code" "$original_file"
  [[ ! -x "$OUTPUT_DIR/or-code" ]]
}
