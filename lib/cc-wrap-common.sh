#!/bin/bash

readonly CC_WRAP_GENERATED_SCRIPT_SIGNATURE='This script encloses its environment the way a cell encloses the sea.'

die() {
  echo "Error: $*" >&2
  exit 1
}

ensure_command() {
  local command_name="$1"
  command -v "$command_name" >/dev/null 2>&1 || die "Required command not found: $command_name"
}

expand_home_path() {
  local value="${1:-}"

  case "$value" in
    "~")
      printf '%s\n' "$HOME"
      ;;
    "~/"*)
      printf '%s/%s\n' "$HOME" "${value:2}"
      ;;
    *)
      printf '%s\n' "$value"
      ;;
  esac
}

path_for_generated_script() {
  local value="${1:-}"

  case "$value" in
    "~")
      printf '$HOME\n'
      ;;
    "~/"*)
      printf '$HOME/%s\n' "${value:2}"
      ;;
    *)
      printf '%s\n' "$value"
      ;;
  esac
}

quote_literal() {
  local value="$1"
  printf "'%s'" "${value//\'/\'\\\'\'}"
}

quote_with_expansion() {
  local value="$1"

  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//\`/\\\`}"

  printf '"%s"' "$value"
}

quote_export_value() {
  local value="$1"

  if [[ "$value" == *'$'* || "$value" == *'`'* ]]; then
    quote_with_expansion "$value"
  else
    quote_literal "$value"
  fi
}

config_has_value() {
  local filter="$1"
  local file_path="$2"

  jq -e "$filter != null" "$file_path" >/dev/null
}

provider_has_value() {
  local filter="$1"
  local provider_json="$2"

  jq -e "$filter != null" <<<"$provider_json" >/dev/null
}

stream_providers() {
  local file_path="$1"
  jq -c '.providers[]' "$file_path"
}

validate_config_file() {
  local file_path="$1"

  [[ -f "$file_path" ]] || die "Config file not found: $file_path"

  jq -e '.' "$file_path" >/dev/null || die "Config file is not valid JSON: $file_path"
  jq -e 'type == "object"' "$file_path" >/dev/null || die "Config root must be an object"
  jq -e '.providers | type == "array" and length > 0' "$file_path" >/dev/null || die "Config must define a non-empty providers array"
}

validate_provider_json() {
  local provider_json="$1"
  local provider_index="$2"
  local script_name required_var models_type

  script_name="$(jq -r '.script_name // empty' <<<"$provider_json")"
  [[ -n "$script_name" ]] || die "Provider #$provider_index is missing script_name"
  [[ "$script_name" != */* && "$script_name" != "." && "$script_name" != ".." ]] || die "Provider #$provider_index has an invalid script_name: $script_name"

  jq -e '.env | type == "object" and length > 0' <<<"$provider_json" >/dev/null || die "Provider '$script_name' must define a non-empty env object"
  jq -e '.env | all(to_entries[]; (.key | test("^[A-Za-z_][A-Za-z0-9_]*$")) and (.value | type == "string"))' <<<"$provider_json" >/dev/null || die "Provider '$script_name' has invalid env entries"

  if provider_has_value '.required_env' "$provider_json"; then
    required_var="$(jq -r '.required_env.var // empty' <<<"$provider_json")"
    [[ -n "$required_var" ]] || die "Provider '$script_name' has required_env but required_env.var is missing"
    [[ "$required_var" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || die "Provider '$script_name' has an invalid required_env.var: $required_var"
  fi

  if provider_has_value '.description' "$provider_json"; then
    jq -e '.description | type == "string"' <<<"$provider_json" >/dev/null || die "Provider '$script_name' has a non-string description"
  fi

  if provider_has_value '.config_dir' "$provider_json"; then
    jq -e '.config_dir | type == "string"' <<<"$provider_json" >/dev/null || die "Provider '$script_name' has a non-string config_dir"
  fi

  if provider_has_value '.models' "$provider_json"; then
    models_type="$(jq -r '.models | type' <<<"$provider_json")"
    case "$models_type" in
      string)
        jq -e '.models | length > 0' <<<"$provider_json" >/dev/null || die "Provider '$script_name' has an empty models string"
        ;;
      object)
        jq -e '.models | length > 0' <<<"$provider_json" >/dev/null || die "Provider '$script_name' has an empty models object"
        jq -e '.models | all(to_entries[]; (.key == "default" or .key == "reasoning" or .key == "opus" or .key == "sonnet" or .key == "haiku") and (.value | type == "string") and (.value | length > 0))' <<<"$provider_json" >/dev/null || die "Provider '$script_name' has invalid models entries"
        ;;
      *)
        die "Provider '$script_name' must set models to a string or object"
        ;;
    esac
  fi
}
