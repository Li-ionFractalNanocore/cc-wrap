# cc-wrap

**Generate per-provider wrapper scripts for Claude Code CLI.**

[中文文档](README_CN.md)

## Overview

cc-wrap reads a JSON configuration file and generates standalone wrapper scripts — one per API provider. On Unix-like systems it generates Bash scripts; on PowerShell it generates `.ps1` scripts. Each wrapper sets the required environment variables and launches `claude`, so you can switch between providers by simply running a different command (e.g. `glm-code`, `or-code`).

This approach keeps your default Claude Code configuration untouched. No global env vars, no profile hacks — just self-contained scripts you can drop into your `$PATH` or invoke directly.

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
| `jq` | 1.6+ for the Bash entrypoint |
| `pwsh` | 7+ for the PowerShell entrypoint |

## Installation

```bash
git clone https://github.com/Li-ionFractalNanocore/cc-wrap.git
cd cc-wrap
chmod +x cc-wrap
```

PowerShell entrypoint:

```powershell
git clone https://github.com/Li-ionFractalNanocore/cc-wrap.git
cd cc-wrap
pwsh -File ./cc-wrap.ps1 --help
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
      "models": "glm-5-turbo",
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
      }
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

Unix / Bash:

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

PowerShell:

```powershell
# Generate all PowerShell wrapper scripts from the default config (cc-wrap.json)
pwsh -File ./cc-wrap.ps1 deploy

# Generate from a custom config file
pwsh -File ./cc-wrap.ps1 deploy --config .\my-providers.json

# Remove managed PowerShell wrapper scripts
pwsh -File ./cc-wrap.ps1 uninstall

# List configured providers
pwsh -File ./cc-wrap.ps1 list

# Run the generated script directly
.\target\glm-code.ps1 --help
.\target\glm-code.ps1 -p "explain this code"
```

`deploy` only overwrites files that already contain the managed signature comment `# This script encloses its environment the way a cell encloses the sea.` Existing files without that comment are left untouched and reported as skipped.

`uninstall` only removes files for the configured providers when those files already contain the same managed signature comment. Existing files without that comment are left untouched and reported as skipped. Missing files are reported but do not cause the command to fail.

The PowerShell entrypoint follows the same safety rule, but only for `.ps1` files containing the PowerShell-managed signature comment `# This PowerShell script encloses its environment the way a cell encloses the sea.` Bash and PowerShell artifacts are managed independently.

## How Generated Scripts Work

Bash `cc-wrap deploy` produces a shell script like this:

```bash
#!/bin/bash
# This script encloses its environment the way a cell encloses the sea.

# glm-code - Use Claude Code with ZAI Coding Plan
# Generated by cc-wrap

# Check if GLM_API_KEY is set
if [[ -z "${GLM_API_KEY:-}" ]]; then
  echo "Error: GLM_API_KEY environment variable is not set" >&2
  echo "Please set GLM_API_KEY, e.g.: export GLM_API_KEY='your-api-key'" >&2
  exit 1
fi

# Set provider configuration
export ANTHROPIC_BASE_URL='https://api.z.ai/api/anthropic'
export ANTHROPIC_AUTH_TOKEN="$GLM_API_KEY"
export ANTHROPIC_MODEL='glm-5-turbo'
export ANTHROPIC_REASONING_MODEL='glm-5-turbo'
export ANTHROPIC_DEFAULT_OPUS_MODEL='glm-5-turbo'
export ANTHROPIC_DEFAULT_SONNET_MODEL='glm-5-turbo'
export ANTHROPIC_DEFAULT_HAIKU_MODEL='glm-5-turbo'
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
export CLAUDE_CONFIG_DIR="$HOME/.config/claude-glm"

exec claude "$@"
```

PowerShell `cc-wrap.ps1 deploy` produces a wrapper like this:

```powershell
#!/usr/bin/env pwsh
# This PowerShell script encloses its environment the way a cell encloses the sea.

# glm-code - Use Claude Code with GLM API
# Generated by cc-wrap

# Check if GLM_API_KEY is set
if ([string]::IsNullOrEmpty($env:GLM_API_KEY)) {
  [Console]::Error.WriteLine('Error: GLM_API_KEY environment variable is not set')
  [Console]::Error.WriteLine('Please set GLM_API_KEY, e.g.: $env:GLM_API_KEY = ''your-api-key''')
  exit 1
}

# Set provider configuration
$env:ANTHROPIC_BASE_URL = 'https://open.bigmodel.cn/api/anthropic'
$env:ANTHROPIC_AUTH_TOKEN = $env:GLM_API_KEY
$env:ANTHROPIC_MODEL = 'glm-5'
$env:ANTHROPIC_REASONING_MODEL = 'glm-5'
$env:ANTHROPIC_DEFAULT_OPUS_MODEL = 'glm-5'
$env:ANTHROPIC_DEFAULT_SONNET_MODEL = 'glm-5'
$env:ANTHROPIC_DEFAULT_HAIKU_MODEL = 'glm-5'
$env:CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = '1'
$env:CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = '1'
$env:CLAUDE_CONFIG_DIR = $HOME + '/.config/claude-glm'

& claude @args
if ($LASTEXITCODE -is [int]) {
  exit $LASTEXITCODE
}
exit 0
```

Key points:

- **API key guard** — exits early with a helpful message if the key is missing
- **Environment isolation** — all provider-specific variables are exported in-script, leaving your shell clean
- **Config directory** — a dedicated `CLAUDE_CONFIG_DIR` keeps provider settings separate
- **Argument passthrough** — Bash uses `exec claude "$@"`; PowerShell uses `& claude @args`

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

Prerequisites:

- `bats` available on your `PATH` for the Bash suite
- `pwsh` available on your `PATH` for the PowerShell suite

Run the suites from the repository root:

```bash
bats tests
```

```powershell
pwsh -File tests/powershell-tests.ps1
```

## License

[MIT](LICENSE)
