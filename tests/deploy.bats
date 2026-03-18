#!/usr/bin/env bats

load 'helpers/common'

setup() {
  setup_test_workspace
}

@test "deploy generates the minimal wrapper script" {
  local config
  config="$(prepare_config "minimal.json")"

  run "$PROJECT_ROOT/cc-wrap" deploy --config "$config"

  assert_status_is 0
  assert_output_matches_fixture "deploy/minimal/stdout.txt"
  assert_generated_files "mini-code"
  assert_file_is_executable "$OUTPUT_DIR/mini-code"
  assert_file_matches_fixture "$OUTPUT_DIR/mini-code" "deploy/minimal/mini-code"
}

@test "deploy generates the complete single-provider wrapper script" {
  local config
  config="$(prepare_config "complete-single.json")"

  run "$PROJECT_ROOT/cc-wrap" deploy --config "$config"

  assert_status_is 0
  assert_output_matches_fixture "deploy/complete-single/stdout.txt"
  assert_generated_files "basic-code"
  assert_file_is_executable "$OUTPUT_DIR/basic-code"
  assert_file_matches_fixture "$OUTPUT_DIR/basic-code" "deploy/complete-single/basic-code"
}

@test "deploy generates both scripts for the multi-provider fixture" {
  local config
  config="$(prepare_config "complete-multi.json")"

  run "$PROJECT_ROOT/cc-wrap" deploy --config "$config"

  assert_status_is 0
  assert_output_matches_fixture "deploy/complete-multi/stdout.txt"
  assert_generated_files "glm-code" "or-code"
  assert_file_is_executable "$OUTPUT_DIR/glm-code"
  assert_file_is_executable "$OUTPUT_DIR/or-code"
  assert_file_matches_fixture "$OUTPUT_DIR/glm-code" "deploy/complete-multi/glm-code"
  assert_file_matches_fixture "$OUTPUT_DIR/or-code" "deploy/complete-multi/or-code"
}
