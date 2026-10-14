---
name: codex-cli-coding
description: Use the locally installed and logged-in Codex CLI (codex exec) for coding tasks when the user asks for Codex, wants to save Cursor quota, or specifies a Codex model and reasoning/thinking depth. Verify login, require explicit model + model_reasoning_effort, then run non-interactive codex exec and return the result/diff.
---

# Codex CLI 编码

用本机已安装并登录的 **Codex CLI** 做编码，由用户指定 **model** 与 **thinking / reasoning 深度**。勿臆造 flag；以下均来自 `codex-cli 0.162.1` 的 `--help` / `codex exec --help` 与本机 `~/.codex/config.toml` / `models_cache.json`。

## 何时用

- 用户明确要求用 Codex / Codex CLI
- 要省 Cursor 模型额度，把生成工作交给本机 Codex
- 用户指定了 Codex 的 model 和/或思考深度（reasoning effort）

未命中以上条件时，不要主动改走 Codex。

## 前置检查

每次调用前：

```bash
export PATH="$HOME/.local/bin:$PATH"
command -v codex
codex --version          # 期望类似 codex-cli 0.162.1
codex login status       # 期望 Logged in using ChatGPT
```

| 失败 | 如何回报 |
| --- | --- |
| `codex` 不在 PATH | 说明未找到二进制；常见路径 `$HOME/.local/bin/codex`；安装见 store `internal/codex-cli-setup.md`。勿假装已可用。 |
| `login status` 非已登录 | 如实报告未登录；请用户在本机完成 `codex login`（device-auth 等）。**勿伪造已登录**，勿打印 `~/.codex/auth.json` 或任何 token。 |

## 用户如何指定参数

| 意图 | CLI（已确认） | 说明 |
| --- | --- | --- |
| Model | `-m <MODEL>` 或 `-c model="<MODEL>"` | `codex` / `codex exec` 均支持 `-m, --model` |
| Thinking / reasoning 深度 | `-c model_reasoning_effort="<LEVEL>"` | **无**独立 `--thinking` flag；用 config 覆盖。本机可用 level 随 model 变，常见：`low` / `medium` / `high` / `xhigh` / `max` / `ultra`（以 `~/.codex/models_cache.json` 该 model 的 `supported_reasoning_levels` 为准） |

**缺省策略：** model 或 depth 任一未由用户（或协调器任务）明确给出时，**先问清再执行**。不要擅自用昂贵默认；也不要静默依赖 `~/.codex/config.toml` 里可能已有的高 cost 值（例如本机可能写有 `model_reasoning_effort = "xhigh"`）。调用时显式传入用户选定的 `-m` 与 `-c model_reasoning_effort=...`。

示例（用户口述 → 组装）：

```bash
# model
codex exec -m gpt-5.6-sol -C /workspace "…"

# thinking / reasoning depth（与 model 一起）
codex exec -m gpt-5.6-sol -c model_reasoning_effort="medium" -C /workspace "…"
```

本机 `models_cache.json` 曾见 slug 示例：`gpt-6.1-sol`、`gpt-6-astra`、`gpt-5.6-sol`、`gpt-5.6-terra` 等；以当前 cache / 用户指定为准，勿写死过时列表。

## 调用方式（非交互）

优先：

```bash
export PATH="$HOME/.local/bin:$PATH"
codex exec \
  -m "<MODEL>" \
  -c model_reasoning_effort="<LEVEL>" \
  -C "<WORK_DIR>" \
  -s workspace-write \
  -o /tmp/codex-last-message.txt \
  "<PROMPT>"
```

| 选项 | 用途（均来自 help） |
| --- | --- |
| `codex exec`（别名 `e`） | 非交互跑一轮 |
| `-C, --cd <DIR>` | 工作根目录（仓库根，如 `/workspace`） |
| `-s, --sandbox` | `read-only` / `workspace-write` / `danger-full-access` |
| `--approve-for-me` | 非交互时把审批交给自动审查（workspace-write 沙箱） |
| `--dangerously-bypass-approvals-and-sandbox` | 跳过确认与沙箱；**极危险**；仅环境已被外部沙箱隔离时考虑 |
| `--add-dir <DIR>` | 额外可写目录 |
| `-o, --output-last-message <FILE>` | 把 agent 最后一条消息写入文件 |
| `--json` | JSONL 事件到 stdout |
| `--ephemeral` | 不落盘会话文件 |
| `--skip-git-repo-check` | 允许在非 git 目录运行 |
| `-i, --image <FILE>` | 附加图片 |

注意：

- `codex exec` **没有**顶层交互 CLI 的 `-a/--ask-for-approval`；非交互用 sandbox / `--approve-for-me` /（必要时）danger bypass，或 `-c approval_policy=...`（若本机版本接受该 config key）。
- 编码改仓库：默认 `-C` 到仓库根 + `-s workspace-write`；只读探查可用 `read-only`。
- 长任务用 shell/tmux，勿假定瞬间返回。
- **禁止**打印或回传 token、`auth.json`、API key、access token。

## 工作流

1. **接任务** — 明确要改的范围与验收；遵守仓库 `AGENTS.md` / 产品设计入口等既有约束（由调用方写入 prompt，本 Skill 不复述产品长文）。
2. **确认 model + depth** — 缺则问；齐则继续。
3. **前置检查** — PATH + `codex login status`。
4. **组装 prompt** — 含目标、约束、勿做事项、工作目录；可把关键 diff 范围说清楚。
5. **执行** — `codex exec` + 显式 `-m` 与 `-c model_reasoning_effort=...`。
6. **交回** — 汇总退出码、`-o` 最后消息、`git status` / `git diff`（或 Codex 产出说明）；失败如实报错，不编造成功。

### 协调器 / Project worker

- Worker 读到「用 Codex」或 preferences 索引本 Skill 时：按本 Skill 执行，结果简报给协调器（结论、diff 要点、阻塞）。
- 协调器负责分派与用户确认 model/depth；worker 不擅自抬高 effort。
- 安装与登录细节见 store：`internal/codex-cli-setup.md`；偏好索引见 `preferences.md`。

## 禁止

- 臆造不存在的 CLI flag
- 伪造已登录 / 伪造成功执行
- 打印或粘贴 secret、token、`~/.codex/auth.json` 内容
- 把与本 Skill 无关的长篇产品/设计内容写进调用说明
- 在用户未指定时擅自选用高成本 model 或 `xhigh`/`max`/`ultra` effort
