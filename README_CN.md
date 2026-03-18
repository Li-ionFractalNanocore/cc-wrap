# cc-wrap

**为 Claude Code CLI 生成按提供商隔离的包装脚本。**

[English](README.md)

## 概述

cc-wrap 读取一个 JSON 配置文件，为每个 API 提供商生成独立的 shell 脚本。每个脚本设置好所需的环境变量后启动 `claude`，你只需运行不同的命令（如 `glm-code`、`or-code`）即可在提供商之间切换。

这种方式不会修改你的 Claude Code 默认配置。无需全局环境变量，无需改 shell profile——只需将生成的脚本放入 `$PATH` 即可。

## 特性

- **多提供商** — 在一个配置文件中定义任意数量的提供商
- **API Key 校验** — 生成的脚本在启动前检查所需的密钥是否已设置
- **独立配置目录** — 每个提供商可使用独立的 `CLAUDE_CONFIG_DIR`
- **模型覆盖** — 为所有模型槽位设置统一模型，或分别指定
- **自定义输出路径** — 控制生成脚本的存放位置
- **额外环境变量** — 向 Claude Code 传递任意环境变量

## 前置要求

| 依赖 | 最低版本 |
|---|---|
| `claude` | 最新版 |
| `jq` | 1.6+ |

## 安装

```bash
git clone https://github.com/Li-ionFractalNanocore/cc-wrap.git
cd cc-wrap
chmod +x cc-wrap
```

## 配置

创建名为 `cc-wrap.json` 的文件（默认），或通过 `--config <path>` 指定自定义路径。

### 配置格式

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

### 字段说明

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `output_dir` | string | 否 | 生成脚本的输出目录。默认：`./target` |
| `defaults.disable_nonessential_traffic` | bool | 否 | 在所有脚本中设置 `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` |
| `defaults.experimental_agent_teams` | bool | 否 | 在所有脚本中设置 `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` |
| `providers` | array | 是 | 提供商定义列表 |
| `providers[].script_name` | string | 是 | 输出脚本文件名 |
| `providers[].description` | string | 否 | 生成脚本中的注释行 |
| `providers[].required_env` | object | 否 | API Key 校验块 |
| `providers[].required_env.var` | string | 是* | 需要检查的环境变量名 |
| `providers[].env` | object | 是 | 核心环境变量（`ANTHROPIC_BASE_URL`、`ANTHROPIC_AUTH_TOKEN` 等） |
| `providers[].models` | string \| object | 否 | 模型覆盖 — 字符串应用于所有槽位；对象可分别映射 `default`、`reasoning`、`opus`、`sonnet`、`haiku` |
| `providers[].config_dir` | string | 否 | 提供商专用的 `CLAUDE_CONFIG_DIR` |

## 使用方法

```bash
# 从默认配置（cc-wrap.json）生成所有包装脚本
cc-wrap deploy

# 从自定义配置文件生成
cc-wrap deploy --config my-providers.json

# 删除当前配置中各提供商对应的受管包装脚本
cc-wrap uninstall

# 使用自定义配置文件删除受管脚本
cc-wrap uninstall --config my-providers.json

# 列出已配置的提供商
cc-wrap list

# 直接运行生成的脚本
glm-code          # 以 GLM 后端启动 Claude Code
or-code            # 以 OpenRouter 后端启动 Claude Code

# 透传参数给 claude
glm-code --help
glm-code -p "解释这段代码"
```

`deploy` 只会覆盖已经包含受管签名注释 `# This script encloses its environment the way a cell encloses the sea.` 的文件。没有这条注释的同名现有文件会保持不变，并在输出中标记为 skipped。

`uninstall` 只会删除当前配置中各提供商对应、且同样包含该受管签名注释的文件。没有这条注释的同名现有文件会保持不变，并在输出中标记为 skipped。目标文件不存在时会报告 missing，但不会导致命令失败。

## 生成脚本的工作原理

以 GLM 提供商为例，`cc-wrap deploy` 会生成如下脚本：

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

要点说明：

- **API Key 守卫** — 如果密钥未设置，提前退出并给出提示信息
- **环境隔离** — 所有提供商相关变量在脚本内 export，不污染你的 shell 环境
- **配置目录** — 独立的 `CLAUDE_CONFIG_DIR` 使各提供商设置互不干扰
- **`exec claude "$@"`** — 用 `claude` 进程替换包装脚本进程，透传所有参数

## 环境变量参考

| 环境变量 | 用途 | 配置来源 |
|---|---|---|
| `ANTHROPIC_BASE_URL` | API 端点 URL | `env.ANTHROPIC_BASE_URL` |
| `ANTHROPIC_AUTH_TOKEN` | API 认证令牌 | `env.ANTHROPIC_AUTH_TOKEN` |
| `ANTHROPIC_MODEL` | 默认模型 | `models`（字符串或 `models.default`） |
| `ANTHROPIC_REASONING_MODEL` | Reasoning 级别模型 | `models`（字符串或 `models.reasoning`） |
| `ANTHROPIC_DEFAULT_OPUS_MODEL` | Opus 级别模型 | `models`（字符串或 `models.opus`） |
| `ANTHROPIC_DEFAULT_SONNET_MODEL` | Sonnet 级别模型 | `models`（字符串或 `models.sonnet`） |
| `ANTHROPIC_DEFAULT_HAIKU_MODEL` | Haiku 级别模型 | `models`（字符串或 `models.haiku`） |
| `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` | 禁用遥测/更新检查 | `defaults.disable_nonessential_traffic` |
| `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` | 启用实验性 agent teams | `defaults.experimental_agent_teams` |
| `CLAUDE_CONFIG_DIR` | 该提供商的配置目录 | `config_dir` |

## 测试

仓库现在包含一组位于 `tests/` 的端到端自动化测试。

前置条件：

- `bats` 已安装且可在 `PATH` 中找到

在仓库根目录执行：

```bash
bats tests
```

## 许可证

[MIT](LICENSE)
