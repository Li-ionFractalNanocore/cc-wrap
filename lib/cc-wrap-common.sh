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

value_uses_only_env_references() {
  local remainder="$1"
  local prefix

  while [[ "$remainder" == *'$'* ]]; do
    prefix="${remainder%%\$*}"
    remainder="${remainder#"$prefix"}"

    if [[ "$remainder" =~ ^\$\{[A-Za-z_][A-Za-z0-9_]*\}(.*)$ ]]; then
      remainder="${BASH_REMATCH[1]}"
    elif [[ "$remainder" =~ ^\$[A-Za-z_][A-Za-z0-9_]*(.*)$ ]]; then
      remainder="${BASH_REMATCH[1]}"
    else
      return 1
    fi
  done

  return 0
}

validate_expandable_value() {
  local script_name="$1"
  local field_name="$2"
  local value="$3"

  if [[ "$value" == *'`'* ]]; then
    die "Provider '$script_name' field '$field_name' contains unsupported shell syntax: backticks are not allowed"
  fi

  if [[ "$value" == *'$'* ]] && ! value_uses_only_env_references "$value"; then
    die "Provider '$script_name' field '$field_name' contains unsupported shell expansion; only \$VAR and \${VAR} are allowed"
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
  while IFS= read -r env_entry; do
    local env_key env_value
    env_key="$(jq -r '.key' <<<"$env_entry")"
    env_value="$(jq -r '.value' <<<"$env_entry")"
    validate_expandable_value "$script_name" "env.$env_key" "$env_value"
  done < <(jq -c '.env | to_entries[]' <<<"$provider_json")

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
    validate_expandable_value "$script_name" "config_dir" "$(jq -r '.config_dir' <<<"$provider_json")"
  fi

  if provider_has_value '.models' "$provider_json"; then
    models_type="$(jq -r '.models | type' <<<"$provider_json")"
    case "$models_type" in
      string)
        jq -e '.models | length > 0' <<<"$provider_json" >/dev/null || die "Provider '$script_name' has an empty models string"
        validate_expandable_value "$script_name" "models" "$(jq -r '.models' <<<"$provider_json")"
        ;;
      object)
        jq -e '.models | length > 0' <<<"$provider_json" >/dev/null || die "Provider '$script_name' has an empty models object"
        jq -e '.models | all(to_entries[]; (.key == "default" or .key == "reasoning" or .key == "opus" or .key == "sonnet" or .key == "haiku") and (.value | type == "string") and (.value | length > 0))' <<<"$provider_json" >/dev/null || die "Provider '$script_name' has invalid models entries"
        while IFS= read -r model_entry; do
          local model_key model_value
          model_key="$(jq -r '.key' <<<"$model_entry")"
          model_value="$(jq -r '.value' <<<"$model_entry")"
          validate_expandable_value "$script_name" "models.$model_key" "$model_value"
        done < <(jq -c '.models | to_entries[]' <<<"$provider_json")
        ;;
      *)
        die "Provider '$script_name' must set models to a string or object"
        ;;
    esac
  fi
}
