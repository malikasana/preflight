# preflight-mcp

![npm](https://img.shields.io/npm/v/@malikasana/preflight-mcp) ![GitHub stars](https://img.shields.io/github/stars/malikasana/preflight?style=social)

A [Model Context Protocol (MCP)](https://modelcontextprotocol.io) server that gives Claude Code structured, on-demand access to your machine's environment — OS, runtimes, SDKs, editors, browsers, and more.

Without preflight, Claude guesses: wrong package manager, wrong Python version, missing SDKs. Preflight solves this in two parts:

1. A **detect script** snapshots your environment into `~/.preflight/env-config.json` (one-time, re-run when things change)
2. An **MCP server** exposes tools so Claude can read that snapshot and generate project rules on demand

---

## Quick Start

**Step 1 — Run the detect script** (one time, re-run when things change)

```powershell
# Windows
powershell -ExecutionPolicy Bypass -File preflight/detect.ps1
```
```bash
# macOS / Linux
bash preflight/detect.sh
```

**Step 2 — Install the MCP server**

```bash
npx @malikasana/preflight-mcp
```

**Step 3 — Register with Claude Code**

```bash
claude mcp add preflight-mcp -- npx @malikasana/preflight-mcp
```

Restart Claude Code. Done — Claude now knows exactly what's on your machine.

---

## Installation

### Using npx (no install required)

```bash
# Run directly
npx @malikasana/preflight-mcp

# Or install globally
npm install -g @malikasana/preflight-mcp
```

### From source

```powershell
# Windows — generate the snapshot first
powershell -ExecutionPolicy Bypass -File "preflight\detect.ps1"

# Install MCP server dependencies
cd preflight-mcp
npm install
```

```bash
# macOS / Linux
bash preflight/detect.sh
cd preflight-mcp && npm install
```

The snapshot is written to `~/.preflight/env-config.json` on all platforms.

---

## Register with Claude Code

### Option A — CLI (recommended)

```bash
claude mcp add preflight-mcp -- npx @malikasana/preflight-mcp
```

### Option B — Edit settings.json manually

Add to `~/.claude/settings.json` (global) or `.claude/settings.json` (project-level):

```json
{
  "mcpServers": {
    "preflight-mcp": {
      "command": "npx",
      "args": ["@malikasana/preflight-mcp"]
    }
  }
}
```

After registering, Claude can call `get_environment` to read your full machine snapshot.

---

## Adding custom fields

The `extensions` array in `~/.preflight/env-config.json` is for tools the detect script doesn't cover. Edit it directly — the detect script leaves this array untouched when it re-runs.

```json
{
  "extensions": [
    {
      "name": "Rust",
      "version": "1.82.0",
      "added_at": "2025-01-15T10:00:00+00:00",
      "description": "Installed via rustup. Toolchain at ~/.cargo/bin."
    },
    {
      "name": "Java",
      "version": "21.0.9",
      "added_at": "2025-01-15T10:00:00+00:00",
      "description": "JBR bundled with Android Studio at /path/to/jbr."
    }
  ]
}
```

---

## Keeping it current

Re-run the detect script whenever you install new tools, update runtimes, or change SDK paths. The MCP server reads the file fresh on every call — no restart needed.

---

## Tool reference

| Tool | Description |
|------|-------------|
| `get_environment` | Returns the full JSON contents of `~/.preflight/env-config.json` |
| `get_package_config` | Fetches latest version and CDN URLs for npm packages from live registry with 1 hour cache and static fallback |
| `generate_claude_md` | Generates a `CLAUDE.md` file in the current working directory with shell rules, package manager, CDN preference, versions, Flutter/Android setup, and Windows gotchas — all derived from your env-config.json |

---

## Usage examples

### get_environment

**Prompt:** Call `get_environment` to learn what's installed on this machine.

Claude reads `~/.preflight/env-config.json` and knows your OS, Node version, Python version, Flutter setup, installed editors, and more — instantly.

### get_package_config

**Prompt:** Use `get_package_config` with `["three", "gsap", "lenis"]`

**Returns:**

```json
[
  {
    "package": "three",
    "version": "0.184.0",
    "install": "npm install three",
    "cdn": {
      "jsdelivr_esm": "https://cdn.jsdelivr.net/npm/three@0.184.0/+esm",
      "jsdelivr_bundle": "https://cdn.jsdelivr.net/npm/three@0.184.0/bundled/three.min.js",
      "unpkg": "https://unpkg.com/three@0.184.0"
    }
  }
]
```

Each entry includes the exact pinned version, the `npm install` command, and CDN URL variants. Results are cached for 1 hour; a static fallback is used if the registry is unreachable.

### generate_claude_md

**Prompt:** Call `generate_claude_md` to set up project rules for this repo.

Claude writes a `CLAUDE.md` in your current working directory containing shell rules, package manager preference, CDN latency rankings, detected versions, Flutter/Android paths, and Windows-specific gotchas — all derived automatically from your env snapshot.
