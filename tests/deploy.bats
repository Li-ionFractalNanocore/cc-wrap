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

@test "deploy overwrites an existing managed wrapper script" {
  local config
  config="$(prepare_config "complete-single.json")"

  cat >"$OUTPUT_DIR/basic-code" <<'EOF'
#!/bin/bash
# This script encloses its environment the way a cell encloses the sea.
echo stale
EOF
  chmod 700 "$OUTPUT_DIR/basic-code"

  run "$PROJECT_ROOT/cc-wrap" deploy --config "$config"

  assert_status_is 0
  assert_output_matches_fixture "deploy/complete-single/stdout.txt"
  assert_file_is_executable "$OUTPUT_DIR/basic-code"
  assert_file_matches_fixture "$OUTPUT_DIR/basic-code" "deploy/complete-single/basic-code"
}

@test "deploy skips an existing unmanaged file and continues" {
  local config original_content original_file
  config="$(prepare_config "complete-multi.json")"
  original_content=$'#!/bin/bash\n# user-managed script\necho custom\n'
  original_file="$WORKDIR/original-or-code"

  cat >"$OUTPUT_DIR/glm-code" <<'EOF'
#!/bin/bash
# This script encloses its environment the way a cell encloses the sea.
echo stale
EOF
  chmod 700 "$OUTPUT_DIR/glm-code"
  printf '%s' "$original_content" >"$OUTPUT_DIR/or-code"
  printf '%s' "$original_content" >"$original_file"
  chmod 644 "$OUTPUT_DIR/or-code"

  run "$PROJECT_ROOT/cc-wrap" deploy --config "$config"

  assert_status_is 0
  assert_output_contains "Skipped existing unmanaged file: $OUTPUT_DIR/or-code"
  assert_output_contains "Generated 1 wrapper script(s) in $OUTPUT_DIR"
  assert_output_contains "Skipped 1 existing unmanaged file(s)"
  assert_generated_files "glm-code" "or-code"
  assert_file_is_executable "$OUTPUT_DIR/glm-code"
  assert_file_matches_fixture "$OUTPUT_DIR/glm-code" "deploy/complete-multi/glm-code"
  cmp -s "$OUTPUT_DIR/or-code" "$original_file"
  [[ ! -x "$OUTPUT_DIR/or-code" ]]
}

@test "deploy rejects env values that use command substitution" {
  local base_config config
  base_config="$(prepare_config "complete-single.json")"
  config="$WORKDIR/unsafe-command-substitution.json"

  jq '.providers[0].env.ANTHROPIC_AUTH_TOKEN = "$(uname -a)"' "$base_config" >"$config"

  run "$PROJECT_ROOT/cc-wrap" deploy --config "$config"

  assert_status_is 1
  assert_output_contains "Provider 'basic-code' field 'env.ANTHROPIC_AUTH_TOKEN' contains unsupported shell expansion; only \$VAR and \${VAR} are allowed"
}

@test "deploy rejects env values that use backticks" {
  local base_config config
  base_config="$(prepare_config "complete-single.json")"
  config="$WORKDIR/unsafe-backticks.json"

  jq '.providers[0].env.ANTHROPIC_AUTH_TOKEN = "`uname -a`"' "$base_config" >"$config"

  run "$PROJECT_ROOT/cc-wrap" deploy --config "$config"

  assert_status_is 1
  assert_output_contains "Provider 'basic-code' field 'env.ANTHROPIC_AUTH_TOKEN' contains unsupported shell syntax: backticks are not allowed"
}
