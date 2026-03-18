# cc-wrap

**Generate per-provider wrapper scripts for Claude Code CLI.**

[中文文档](README_CN.md)

## Overview

cc-wrap reads a JSON configuration file and generates standalone shell scripts — one per API provider. Each script sets the required environment variables and launches `claude`, so you can switch between providers by simply running a different command (e.g. `glm-code`, `or-code`).

This approach keeps your default Claude Code configuration untouched. No global env vars, no profile hacks — just self-contained scripts you can drop into your `$PATH`.

## Features

- **Multi-provider** — define as many providers as you need in a single config file
- **API key validation** — generated scripts check that the required key is set before launching
- **Isolated config directories** — each provider can use its own `CLAUDE_CONFIG_DIR`
- **Model override** — set a single model for all slots, or specify each one individually
- **Custom output path** — control where generated scripts are written
- **Extra env vars** — pass arbitrary environment variables through to Claude Code

## Prerequisites

| Dependency | Minimum version |
|---|---|
| `claude` | latest |
| `jq` | 1.6+ |

## Installation

```bash
git clone https://github.com/Li-ionFractalNanocore/cc-wrap.git
cd cc-wrap
chmod +x cc-wrap
```

## Configuration

Create a file named `cc-wrap.json` (default) or pass a custom path with `--config <path>`.

### Config format

```json
{
  "output_dir": "~/.local/bin",
  "defaults": {
    "disable_nonessential_traffic": true,
    "experimental_agent_teams": true
  },
  "providers": [
    {
      "script_name": "glm-code",
      "description": "Use Claude Code with GLM API",
      "required_env": {
        "var": "GLM_API_KEY"
      },
      "env": {
        "ANTHROPIC_BASE_URL": "https://open.bigmodel.cn/api/anthropic",
        "ANTHROPIC_AUTH_TOKEN": "$GLM_API_KEY"
      },
      "models": "glm-5",
      "config_dir": "~/.config/claude-glm"
    },
    {
      "script_name": "or-code",
      "description": "Use Claude Code with OpenRouter API",
      "required_env": {
        "var": "OPENROUTER_API_KEY"
      },
      "env": {
        "ANTHROPIC_BASE_URL": "https://openrouter.ai/api/v1",
        "ANTHROPIC_AUTH_TOKEN": "$OPENROUTER_API_KEY"
      },
      "models": {
        "default": "anthropic/claude-sonnet-4.6",
        "reasoning": "anthropic/claude-sonnet-4.6",
        "opus": "anthropic/claude-opus-4.6",
        "sonnet": "anthropic/claude-sonnet-4.6",
        "haiku": "anthropic/claude-haiku-4.5"
      },
      "config_dir": ""
    }
  ]
}
```

### Field reference

| Field | Type | Required | Description |
|---|---|---|---|
| `output_dir` | string | No | Directory for generated scripts. Default: `./target` |
| `defaults.disable_nonessential_traffic` | bool | No | Set `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` in all scripts |
| `defaults.experimental_agent_teams` | bool | No | Set `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in all scripts |
| `providers` | array | Yes | List of provider definitions |
| `providers[].script_name` | string | Yes | Output script filename |
| `providers[].description` | string | No | Comment line in the generated script |
| `providers[].required_env` | object | No | API key validation block |
| `providers[].required_env.var` | string | Yes* | Environment variable to check |
| `providers[].env` | object | Yes | Core environment variables (`ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, etc.) |
| `providers[].models` | string \| object | No | Model override — a string applies to all slots; an object maps `default`, `reasoning`, `opus`, `sonnet`, `haiku` individually |
| `providers[].config_dir` | string | No | Provider-specific `CLAUDE_CONFIG_DIR` |

## Usage

```bash
# Generate all wrapper scripts from the default config (cc-wrap.json)
cc-wrap deploy

# Generate from a custom config file
cc-wrap deploy --config my-providers.json

# Remove managed wrapper scripts for the configured providers
cc-wrap uninstall

# Remove managed scripts using a custom config file
cc-wrap uninstall --config my-providers.json

# List configured providers
cc-wrap list

# Run the generated script directly
glm-code          # starts Claude Code with GLM backend
or-code           # starts Claude Code with OpenRouter backend

# Pass arguments through to claude
glm-code --help
glm-code -p "explain this code"
```

`deploy` only overwrites files that already contain the managed signature comment `# This script encloses its environment the way a cell encloses the sea.` Existing files without that comment are left untouched and reported as skipped.

`uninstall` only removes files for the configured providers when those files already contain the same managed signature comment. Existing files without that comment are left untouched and reported as skipped. Missing files are reported but do not cause the command to fail.

## How Generated Scripts Work

Taking the GLM provider as an example, `cc-wrap deploy` produces a script like this:

```bash
#!/bin/bash
# This script encloses its environment the way a cell encloses the sea.

# glm-code - GLM Code executable command
# This script provides a standalone executable for using Claude Code with GLM API

# Check if GLM_API_KEY is set
if [[ -z "$GLM_API_KEY" ]]; then
  echo "Error: GLM_API_KEY environment variable is not set" >&2
  echo "Please set GLM_API_KEY, e.g.: export GLM_API_KEY='your-api-key'" >&2
  exit 1
fi

# Set GLM configuration
export ANTHROPIC_BASE_URL=https://open.bigmodel.cn/api/anthropic
export ANTHROPIC_AUTH_TOKEN=$GLM_API_KEY
export ANTHROPIC_MODEL='glm-5'
export ANTHROPIC_REASONING_MODEL='glm-5'
export ANTHROPIC_DEFAULT_OPUS_MODEL='glm-5'
export ANTHROPIC_DEFAULT_SONNET_MODEL='glm-5'
export ANTHROPIC_DEFAULT_HAIKU_MODEL='glm-5'
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1

# Set GLM-specific config directory
GLM_CONFIG_DIR="$HOME/.config/claude-glm"
export CLAUDE_CONFIG_DIR="$GLM_CONFIG_DIR"

# Execute claude with all arguments
exec claude "$@"
```

Key points:

- **API key guard** — exits early with a helpful message if the key is missing
- **Environment isolation** — all provider-specific variables are exported in-script, leaving your shell clean
- **Config directory** — a dedicated `CLAUDE_CONFIG_DIR` keeps provider settings separate
- **`exec claude "$@"`** — replaces the wrapper process with `claude`, passing all arguments through

## Environment Variables Reference

| Environment Variable | Purpose | Set by |
|---|---|---|
| `ANTHROPIC_BASE_URL` | API endpoint URL | `env.ANTHROPIC_BASE_URL` |
| `ANTHROPIC_AUTH_TOKEN` | API authentication token | `env.ANTHROPIC_AUTH_TOKEN` |
| `ANTHROPIC_MODEL` | Default model | `models` (string or `models.default`) |
| `ANTHROPIC_REASONING_MODEL` | Reasoning-tier model | `models` (string or `models.reasoning`) |
| `ANTHROPIC_DEFAULT_OPUS_MODEL` | Opus-tier model | `models` (string or `models.opus`) |
| `ANTHROPIC_DEFAULT_SONNET_MODEL` | Sonnet-tier model | `models` (string or `models.sonnet`) |
| `ANTHROPIC_DEFAULT_HAIKU_MODEL` | Haiku-tier model | `models` (string or `models.haiku`) |
| `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` | Disable telemetry/update checks | `defaults.disable_nonessential_traffic` |
| `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` | Enable experimental agent teams | `defaults.experimental_agent_teams` |
| `CLAUDE_CONFIG_DIR` | Config directory for this provider | `config_dir` |

## Testing

This repository includes a small end-to-end test suite under `tests/`.

Prerequisite:

- `bats` available on your `PATH`

Run the suite from the repository root:

```bash
bats tests
```

## License

[MIT](LICENSE)
