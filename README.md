# ArchAgent CLI

Command-line interface for **ArchAgent** — Agentic Code Review with Architectural Intent Understanding.

ArchAgent catches architectural drift in pull requests: cross-boundary dependencies, layer violations, and broken design contracts that linters and tests miss. The CLI talks to the ArchAgent engine over HTTP.

---

## What's New in v0.2.1

- **Self-update command** — `archagent update` fetches the latest CLI version and example files
- **External example file** — `architecture-intent.example.yaml` ships with the CLI for easier maintenance
- **Comprehensive intent YAML reference** — full schema documentation below

Previous: v0.2.0 — review history persistence, `/reviews` dashboard pages, pinned image versions

---

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/phanendra-t/ArchagentCLI/main/install.sh | bash
```

This downloads archagent to ~/.local/bin/archagent and caches example files to ~/.local/share/archagent/. Add to your PATH if needed:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Requires: bash, curl, jq.

## Quick Start

```bash
# 1. Bootstrap a project
cd ~/my-project
archagent init --name my-system
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

## Commands

| Command | Description |
|---------|-------------|
| archagent init | Bootstrap project (docker-compose + intent + .env) |
| archagent review --diff <file> | Review a PR diff against architectural intent |
| archagent feedback <r> <f> <label> | Submit annotation (valid / false_positive / partial) |
| archagent stats | Show annotation count and reward model status |
| archagent retrain | Retrain reward model (after 20+ annotations) |
| archagent validate <file> | Validate an architecture-intent.yaml file |
| archagent update | Update CLI to the latest version |

Run archagent --help for full options.

## Updating

```bash
archagent update
```

This fetches the latest CLI script and example files from the main branch. No engine or dashboard restart needed — only the local CLI binary is updated.

## How It Works

ArchAgent has three components:

| Component | Image |
|-----------|-------|
| Engine | phanitirumala/archagent-engine:0.2.0 |
| Dashboard | phanitirumala/archagent-dashboard:0.2.0 |
| CLI (this repo) | bash script v0.2.1 |

The CLI is a thin HTTP client. The engine runs the LLM agents and reward model. The dashboard provides a web UI for feedback and metrics.

When you run archagent init, it generates a docker-compose.yml that pulls the engine and dashboard images from Docker Hub.

## Server Discovery

The CLI finds the engine in this order:

1. --server URL flag
2. ARCHAGENT_SERVER env var
3. .archagent/config in current/parent directories
4. Default: http://localhost:8000

---

## Architecture Intent YAML — Reference (v0.2.1)

### Table of Contents

- [Overview](#overview)
- [File Structure](#file-structure)
- [Top-Level Fields](#top-level-fields)
- [bounded_contexts](#bounded_contexts)
- [layers](#layers)
- [communication_patterns](#communication_patterns)
- [security_rules](#security_rules)
- [Glob Pattern Syntax](#glob-pattern-syntax)
- [Full Example](#full-example-e-commerce-platform)
- [Minimal Examples](#minimal-examples)
- [Best Practices](#best-practices)
- [Validation](#validation)
- [Hot Reload](#hot-reload)
- [Limitations in v0.2.1](#limitations-in-v021)

### Overview

The architecture-intent.yaml file defines your system's architectural rules. ArchAgent reads it on every review to determine what code patterns are allowed and what constitutes a violation.

ArchAgent v0.2.1 enforces 4 categories of rules:

| Category | Detection Method |
|----------|------------------|
| bounded_contexts | Deterministic pre-check + LLM |
| layers | Deterministic pre-check + LLM |
| communication_patterns | LLM only |
| security_rules | LLM only |

The file lives at the root of your project. The engine container mounts it read-only at /app/architecture-intent.yaml.

### File Structure

```yaml
schema_version: "1.0"        # Required. Always "1.0" for v0.2.1.
system: "my-app"             # Required. Identifies this system in the dashboard.

bounded_contexts: []         # Module isolation and dependency rules
layers: []                   # Layered architecture import rules
communication_patterns: []   # Event vs direct call rules
security_rules: []           # Data protection constraints
```

### Top-Level Fields

#### schema_version

| Type | Required | Value |
|------|----------|-------|
| string | Yes | "1.0" |

Reserved for future schema migrations. Always set to "1.0" in v0.2.1.

#### system

| Type | Required | Example |
|------|----------|---------|
| string | Yes | "ecommerce-order-platform" |

Free-form name identifying this system. Stored in the database with every review and displayed in the dashboard's /reviews page. Use a unique name per project.

### bounded_contexts

Defines your system's modules/domains and their dependency rules.

```yaml
bounded_contexts:
  - name: orders
    description: "Handles order lifecycle"
    owns:
      - "src/orders/**"
    allowed_dependencies:
      - products
    forbidden_dependencies:
      - notifications
      - analytics
    security_boundary: false
```

#### Fields

| Field | Type | Required | Default |
|-------|------|----------|---------|
| name | string | Yes | — |
| description | string | No | "" |
| owns | list of strings | Yes | — |
| allowed_dependencies | list of strings | No | [] |
| forbidden_dependencies | list of strings | No | [] |
| security_boundary | boolean | No | false |

#### Dependency Logic

The interaction between allowed_dependencies and forbidden_dependencies determines enforcement:

| allowed_dependencies | forbidden_dependencies | Behavior |
|---------------------|------------------------|----------|
| Empty [] | Empty [] | No outbound import checks for this context |
| Empty [] | Set (e.g., [notifications]) | Deny-list mode — only listed targets are blocked |
| Set (e.g., [products]) | Empty [] | Allow-list mode — only listed targets are allowed, all others blocked |
| Both set | Both set | forbidden_dependencies takes precedence; allowed used for documentation |

#### Detection Semantics

1. Pre-check (deterministic): Parses imports in the diff. If a file in context A imports from a file in context B, and B is in A's forbidden_dependencies (or B is NOT in A's allowed_dependencies when that list is non-empty), it is flagged as a suspect.
2. Context Boundary Reviewer (LLM): Confirms or rejects suspects. Also finds additional violations the regex missed — indirect coupling, shared state, string-based references, runtime dependencies.
3. Defender Agent (LLM): Challenges confirmed findings to remove false positives.

### layers

Defines your layered architecture rules.

```yaml
layers:
  - name: controller
    pattern: "src/**/controllers/**"
    allowed_imports_from:
      - service
    forbidden_imports_from:
      - repository
      - model
    rule: "Controllers handle HTTP only — delegate all logic to services"
```

#### Fields

| Field | Type | Required | Default |
|-------|------|----------|---------|
| name | string | Yes | — |
| pattern | string | Yes | — |
| allowed_imports_from | list of strings | No | [] |
| forbidden_imports_from | list of strings | No | [] |
| rule | string | No | "" |

#### Import Logic

Same interaction rules as bounded_contexts:

| allowed_imports_from | forbidden_imports_from |
|---------------------|------------------------|
| Empty | Empty |
| Empty | Set |
| Set | Empty |
| Both set | Both set |

Use "*" in forbidden_imports_from to block imports from ALL other layers:

```yaml
  - name: model
    forbidden_imports_from: ["*"]
```

#### Detection Semantics

1. Pre-check: Maps each file to its layer via glob pattern. Checks imported file's layer against the rules.
2. Layer Violation Reviewer (LLM): Confirms suspects and finds semantic layer leaks (e.g., HTTP objects passed into service methods, SQL queries in controllers).
3. Defender Agent: Challenges findings.

### communication_patterns

Defines how bounded contexts should communicate with each other.

```yaml
communication_patterns:
  - between: [orders, notifications]
    allowed: event
    forbidden: direct
    reason: "Orders emits events; Notifications subscribes."

  - between: [any, analytics]
    allowed: event
    forbidden: direct
    reason: "Analytics is a read-model populated by domain events only"
```

#### Fields

| Field | Type | Required | Default |
|-------|------|----------|---------|
| between | list (2 items) | Yes | — |
| allowed | string | Yes | — |
| forbidden | string | No | null |
| pattern | string | No | null |
| reason | string | No | null |

#### Detection Semantics

- NOT enforced by deterministic pre-check.
- The Context Boundary Reviewer (LLM) reads these patterns and uses them when evaluating cross-context calls.
- Soft enforcement: relies on LLM semantic interpretation of the diff.
- The "any" wildcard matches any context. Example: between: [any, analytics] means no context should directly call analytics.

### security_rules

Defines security constraints for specific bounded contexts.

```yaml
security_rules:
  - context: payments
    constraints:
      - "No logging of card numbers, CVV, or full account numbers"
      - "All external API calls must use HTTPS"
      - "No PII in error messages or stack traces"
```

#### Fields

| Field | Type | Required |
|-------|------|----------|
| context | string | Yes |
| constraints | list of strings | Yes |

#### Detection Semantics

- The Security Boundary Reviewer (LLM) reads constraints and checks the diff against them.
- Files in contexts marked security_boundary: true get extra scrutiny (flagged in the prompt as "SECURITY BOUNDARY").
- All enforcement is LLM-based. There is no regex-based detection for security rules.
- Write constraints as imperative statements. Specific phrasing produces better detection:
  - Good: "No logging of card numbers, CVV, or full account numbers"
  - Weak: "Be careful with sensitive data"

### Glob Pattern Syntax

The owns and pattern fields use Python fnmatch glob syntax (NOT regex, NOT full bash globbing).

#### Pattern Reference

| Pattern | Matches |
|---------|---------|
| * | Any sequence of characters except / |
| ** | Any sequence including / (any depth) |
| ? | Exactly one character |
| [abc] | Any character in the set |
| [!abc] | Any character NOT in the set |

#### Examples

| Pattern | Matches |
|---------|---------|
| src/orders/** | src/orders/services/order.service.ts, src/orders/models/order.model.ts |
| src/**/controllers/** | src/orders/controllers/order.controller.ts, src/payments/controllers/payment.controller.ts |
| src/payments/*.ts | src/payments/index.ts (NOT src/payments/services/payment.service.ts) |
| **/*.test.ts | Any .test.ts file at any depth |

#### Important Notes

- File paths from git diff come as a/src/... and b/src/.... The a/ and b/ prefixes are stripped before matching. Write patterns without them.
- Always use / as the path separator in patterns.
- Patterns are matched against the full relative path from the repository root.
- If a file matches multiple contexts' owns patterns, the first match wins (order matters).

### Full Example: E-commerce Platform

```yaml
schema_version: "1.0"
system: "ecommerce-order-platform"

bounded_contexts:
  - name: orders
    description: "Handles order lifecycle from creation to fulfillment"
    owns:
      - "src/orders/**"
    allowed_dependencies:
      - products
      - pricing
    forbidden_dependencies:
      - notifications
      - analytics

  - name: payments
    description: "Payment processing, refunds, and billing"
    owns:
      - "src/payments/**"
    allowed_dependencies:
      - orders
    forbidden_dependencies:
      - products
      - notifications
      - analytics
    security_boundary: true

  - name: notifications
    description: "All outbound communication (email, SMS, push)"
    owns:
      - "src/notifications/**"
    allowed_dependencies: []
    forbidden_dependencies:
      - orders
      - payments
      - analytics

  - name: analytics
    description: "Reporting and business intelligence"
    owns:
      - "src/analytics/**"
    allowed_dependencies: []
    forbidden_dependencies:
      - orders
      - payments
      - notifications

layers:
  - name: controller
    pattern: "src/**/controllers/**"
    allowed_imports_from: [service]
    forbidden_imports_from: [repository, model]
    rule: "Controllers handle HTTP only — delegate all logic to services"

  - name: service
    pattern: "src/**/services/**"
    allowed_imports_from: [repository, model, event]
    forbidden_imports_from: [controller]
    rule: "Services contain business logic — no HTTP awareness"

  - name: repository
    pattern: "src/**/repositories/**"
    allowed_imports_from: [model]
    forbidden_imports_from: [controller, service]
    rule: "Repositories handle data access only"

  - name: model
    pattern: "src/**/models/**"
    allowed_imports_from: []
    forbidden_imports_from: [controller, service, repository]
    rule: "Models are pure data structures — no dependencies"

communication_patterns:
  - between: [orders, notifications]
    allowed: event
    forbidden: direct
    reason: "Orders emits events; Notifications subscribes. No direct coupling."

  - between: [orders, payments]
    allowed: direct
    pattern: "via PaymentGateway interface only"

  - between: [any, analytics]
    allowed: event
    forbidden: direct
    reason: "Analytics is a read-model populated by domain events only"

security_rules:
  - context: payments
    constraints:
      - "No logging of card numbers, CVV, or full account numbers"
      - "All external API calls must use HTTPS"
      - "No PII in error messages or stack traces"
      - "New dependencies require security review"

  - context: orders
    constraints:
      - "Customer email/phone must not appear in debug logs"
```

### Minimal Examples

#### 1. Module Isolation Only (No Layers)

```yaml
schema_version: "1.0"
system: "simple-app"

bounded_contexts:
  - name: users
    owns: ["src/users/**"]
    forbidden_dependencies: [billing]

  - name: billing
    owns: ["src/billing/**"]
    allowed_dependencies: [users]
```

#### 2. Layered Architecture Only (No Contexts)

```yaml
schema_version: "1.0"
system: "layered-app"

layers:
  - name: api
    pattern: "src/api/**"
    allowed_imports_from: [service]
    forbidden_imports_from: [data]

  - name: service
    pattern: "src/service/**"
    allowed_imports_from: [data]
    forbidden_imports_from: [api]

  - name: data
    pattern: "src/data/**"
    forbidden_imports_from: [api, service]
```

#### 3. Security-Focused

```yaml
schema_version: "1.0"
system: "fintech-app"

bounded_contexts:
  - name: transactions
    owns: ["src/transactions/**"]
    security_boundary: true

security_rules:
  - context: transactions
    constraints:
      - "No logging of account numbers or routing numbers"
      - "All database queries must use parameterized statements"
      - "No plaintext storage of tokens or credentials"
      - "Error responses must not include stack traces"
```

### Best Practices

1. Start small — begin with 2-3 contexts and 3-4 layers. Add complexity as you learn what triggers false positives.
2. Match your folder structure — glob patterns should exactly mirror your actual directory layout.
3. Be explicit about forbidden_dependencies — an empty list means no enforcement happens.
4. Write security constraints as imperative statements — specific phrasing produces better LLM detection.
5. Test with a known-bad diff — after writing your intent file, feed a deliberately-violating diff to archagent review to verify detection works.
6. Use archagent validate — catches YAML syntax errors and missing required fields before you run a review.

### Validation

Before relying on your intent file for reviews, validate it:

```bash
archagent validate architecture-intent.yaml
```

This catches:

- YAML syntax errors
- Missing required fields (schema_version, system)
- Empty bounded_contexts or layers (warning)
- Unknown top-level fields (warning)

### Hot Reload

The engine reads the intent file fresh on every review. Edit the file and the next archagent review uses the new rules immediately — no container restart needed.

### Limitations in v0.2.1

- communication_patterns and security_rules are LLM-interpreted, not deterministically enforced. Detection depends on LLM semantic understanding.
- Cross-file static analysis (e.g., dependency cycle detection) is NOT performed.
- Custom user-defined principles are not supported in this version.
- The dependency_rules and principles YAML fields are reserved for future versions — if present, they are parsed but not enforced.
- File matching uses first-match order for bounded_contexts. If glob patterns overlap, reorder contexts to ensure correct ownership.

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
