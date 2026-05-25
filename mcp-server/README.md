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
| `get_package_config` | Fetches latest version and CDN URLs for npm packages from live registry with 1 hour cache and static fallback |

## Usage example

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
  },
  {
    "package": "gsap",
    "version": "3.15.0",
    "install": "npm install gsap",
    "cdn": {
      "jsdelivr_esm": "https://cdn.jsdelivr.net/npm/gsap@3.15.0/+esm",
      "jsdelivr_bundle": "https://cdn.jsdelivr.net/npm/gsap@3.15.0/bundled/gsap.min.js",
      "unpkg": "https://unpkg.com/gsap@3.15.0"
    }
  },
  {
    "package": "lenis",
    "version": "1.3.23",
    "install": "npm install lenis",
    "cdn": {
      "jsdelivr_esm": "https://cdn.jsdelivr.net/npm/lenis@1.3.23/+esm",
      "jsdelivr_bundle": "https://cdn.jsdelivr.net/npm/lenis@1.3.23/bundled/lenis.min.js",
      "unpkg": "https://unpkg.com/lenis@1.3.23"
    }
  }
]
```

Each entry includes the exact pinned version, the `npm install` command, and three CDN URL variants (ESM, bundled/minified, unpkg). Results are cached for 1 hour; a static fallback is used if the registry is unreachable.
