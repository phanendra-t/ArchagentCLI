# ArchAgent CLI

Command-line interface for **ArchAgent** — Agentic Code Review with Architectural Intent Understanding.

ArchAgent catches architectural drift in pull requests: cross-boundary dependencies, layer violations, and broken design contracts that linters and tests miss. The CLI talks to the ArchAgent engine over HTTP.

---

## What's New in v0.2.0

- **Review history persists** — every review is saved to PostgreSQL and visible in the dashboard at `/reviews`
- **Per-review detail view** — click any past review to see full findings, diff preview, and annotation status at `/reviews/[id]`
- **Interactive Review page** — the dashboard at `/review` accepts any unified diff via paste or file upload
- **Pinned image versions** — `archagent init` generates compose files pinned to `0.2.0` for reproducibility

---

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/phanendra-t/ArchagentCLI/main/install.sh | bash
```

This downloads `archagent` to `~/.local/bin/archagent`. Add to your PATH if needed:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Requires: `bash`, `curl`, `jq`.

---

## Quick Start

```bash
# 1. Bootstrap a project
cd ~/my-project
archagent init
#    Creates: docker-compose.yml, architecture-intent.yaml, .env, .gitignore

# 2. Add your Anthropic API key
edit .env   # ANTHROPIC_API_KEY=sk-ant-...

# 3. Start the engine + dashboard
docker compose up -d

# 4. Review your first PR
git diff HEAD~1 | archagent review --diff -

# 5. Open the dashboard
open http://localhost:3000/review     # Submit diffs interactively
open http://localhost:3000/reviews    # Browse review history
```

---

## Commands

| Command | Description |
|---------|-------------|
| `archagent init` | Bootstrap project (docker-compose + intent + .env) |
| `archagent review --diff <file>` | Review a PR diff against architectural intent |
| `archagent feedback <r> <f> <label>` | Submit annotation (valid / false_positive / partial) |
| `archagent stats` | Show annotation count and reward model status |
| `archagent retrain` | Retrain reward model (after 20+ annotations) |
| `archagent validate <file>` | Validate an architecture-intent.yaml file |

Run `archagent --help` for full options.

---

## How It Works

ArchAgent has three components:

| Component | Image | Port |
|-----------|-------|------|
| Engine | `phanitirumala/archagent-engine:0.2.0` | 8000 |
| Dashboard | `phanitirumala/archagent-dashboard:0.2.0` | 3000 |
| CLI (this repo) | bash script v0.2.0 | — |

The CLI is a thin HTTP client. The engine runs the LLM agents and reward model. The dashboard provides a web UI for feedback and metrics.

When you run `archagent init`, it generates a `docker-compose.yml` that pulls the engine and dashboard images from Docker Hub.

---

## Server Discovery

The CLI finds the engine in this order:

1. `--server URL` flag
2. `ARCHAGENT_SERVER` env var
3. `.archagent/config` in current/parent directories
4. Default: `http://localhost:8000`

---

## Architecture Intent YAML

Define your architecture in a YAML file:

```yaml
schema_version: "1.0"
system: "my-app"

bounded_contexts:
  - name: orders
    owns: ["src/orders/**"]
    forbidden_dependencies: [notifications, analytics]

layers:
  - name: controller
    pattern: "src/**/controllers/**"
    forbidden_imports_from: [repository]

communication_patterns:
  - between: [orders, notifications]
    allowed: event
    forbidden: direct
```

`archagent init --template full` generates a comprehensive example.

---

## Examples

```bash
# Review last commit
git diff HEAD~1 | archagent review --diff -

# Use a specific intent file
archagent review --diff my.diff --intent custom-intent.yaml

# Fail CI on critical findings
archagent review --diff pr.diff --fail-on critical

# Output as JSON
archagent review --diff my.diff --format json

# Annotate a finding
archagent feedback abc12345 ctx-d6b571 valid

# Connect to a remote engine
archagent --server https://archagent.internal review --diff my.diff
```

---

## CI/CD

GitHub Action example:

```yaml
- name: ArchAgent Review
  run: |
    archagent review \
      --diff <(git diff origin/main...HEAD) \
      --fail-on critical \
      --format json \
      --output review.json
```
