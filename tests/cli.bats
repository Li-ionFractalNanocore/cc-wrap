#!/usr/bin/env bats

load 'helpers/common'

setup() {
  setup_test_workspace
}

@test "list prints the minimal provider name" {
  local config
  config="$(prepare_config "minimal.json")"

  run "$PROJECT_ROOT/cc-wrap" list --config "$config"

  assert_status_is 0
  assert_output_matches_fixture "list/minimal.txt"
}

@test "list prints the provider description when present" {
  local config
  config="$(prepare_config "complete-single.json")"

  run "$PROJECT_ROOT/cc-wrap" list --config "$config"

  assert_status_is 0
  assert_output_matches_fixture "list/complete-single.txt"
}
