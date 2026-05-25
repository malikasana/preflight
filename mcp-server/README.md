# preflight-mcp

A [Model Context Protocol (MCP)](https://modelcontextprotocol.io) server that gives Claude Code structured, on-demand access to your machine's environment — OS, runtimes, SDKs, editors, browsers, and more.

## What problem it solves

Claude Code has no built-in awareness of what tools are installed on your machine. Without preflight it guesses: wrong package manager, wrong Python version, missing SDKs. Preflight solves this in two parts:

1. A **detect script** snapshots your environment into `~/.preflight/env-config.json` (one-time, re-run when things change)
2. An **MCP server** exposes a `get_environment` tool so Claude can read that snapshot at any time

## Installation

### Windows

```powershell
# 1. Generate the snapshot (re-run whenever your environment changes)
powershell -ExecutionPolicy Bypass -File "preflight\detect.ps1"

# 2. Install MCP server dependencies
cd preflight-mcp
npm install
```

### macOS / Linux

```bash
# 1. Generate the snapshot
bash preflight/detect.sh

# 2. Install MCP server dependencies
cd preflight-mcp && npm install
```

The snapshot is written to `~/.preflight/env-config.json` on all platforms.

## Register with Claude Code

Add the server to your Claude Code MCP settings. Edit `~/.claude/settings.json` (global) or `.claude/settings.json` (project-level):

```json
{
  "mcpServers": {
    "preflight-mcp": {
      "command": "node",
      "args": ["/absolute/path/to/preflight-mcp/index.js"]
    }
  }
}
```

Or use the CLI:

```bash
claude mcp add preflight-mcp node /absolute/path/to/preflight-mcp/index.js
```

After registering, Claude can call `get_environment` to read your full machine snapshot.

## Adding custom fields

The `extensions` array in `~/.preflight/env-config.json` is for tools the detect script doesn't cover. Edit it directly — the detect script leaves this array untouched when it re-runs.

Each entry follows this schema:

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

## Keeping it current

Re-run the detect script whenever you install new tools, update runtimes, or change SDK paths. The MCP server reads the file fresh on every `get_environment` call — no restart needed.

## Tool reference

| Tool | Description |
|------|-------------|
| `get_environment` | Returns the full JSON contents of `~/.preflight/env-config.json` |

---

> **Phase 3 — Live package registry** *(coming soon)*
> The next version will query live package registries (npm, PyPI, pub.dev) on demand rather than relying on a static snapshot. Custom `extensions` entries will be preserved as a first-class concept across runs.
