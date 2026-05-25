# preflight

![npm](https://img.shields.io/npm/v/@malikasana/preflight-mcp) ![GitHub stars](https://img.shields.io/github/stars/malikasana/preflight?style=social)

**preflight** gives Claude Code accurate knowledge of your machine before every conversation — OS, runtimes, SDKs, editors, browsers, and more.

Without preflight, Claude guesses: wrong package manager, wrong Python version, missing SDKs. Preflight solves this by snapshotting your environment once and letting Claude read it on demand.

---

## Quick Start

**Step 1 — Run the detect script** (one time, re-run when things change)

```powershell
# Windows
powershell -ExecutionPolicy Bypass -File detect.ps1
```
```bash
# macOS / Linux
bash detect.sh
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

## How it works

```
detect.ps1 / detect.sh          ──▶   ~/.preflight/env-config.json
                                                  │
                               mcp-server/index.js reads it
                                                  │
                              Claude calls get_environment tool
```

1. You run a **detect script** once. It scans your machine and writes a JSON snapshot to `~/.preflight/env-config.json`.
2. The **MCP server** (`mcp-server/`) exposes tools that read that snapshot.
3. Claude calls `get_environment` at the start of a session and knows exactly what you have installed.
4. Call `generate_claude_md` to write a `CLAUDE.md` file with project-level rules derived from your snapshot.

Re-run the detect script any time you install new tools or update runtimes. No server restart needed — the file is read fresh on every call.

---

## Step 1 — Generate the snapshot

### Windows

Open PowerShell in this folder and run:

```powershell
powershell -ExecutionPolicy Bypass -File detect.ps1
```

The snapshot is written to `C:\Users\<you>\.preflight\env-config.json`.

### macOS / Linux

Open a terminal in this folder and run:

```bash
bash detect.sh
```

The snapshot is written to `~/.preflight/env-config.json`.

> **Re-run whenever things change** — new SDK, updated Node, etc. The script is safe to run repeatedly.

---

## Step 2 — Install the MCP server

The easiest way — no cloning required:

```bash
npx @malikasana/preflight-mcp
```

Or install globally:

```bash
npm install -g @malikasana/preflight-mcp
```

Or run from source after cloning this repo:

```bash
cd mcp-server
npm install
```

---

## Step 3 — Connect to Claude Code

### Option A — CLI (recommended)

```bash
claude mcp add preflight-mcp -- npx @malikasana/preflight-mcp
```

### Option B — Edit settings.json manually

Open `~/.claude/settings.json` (global) or `.claude/settings.json` (project-only) and add:

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

After saving, restart Claude Code. Claude can now call `get_environment` to read your machine snapshot.

---

## Adding tools the detect script missed

The `extensions` array in `~/.preflight/env-config.json` is yours to edit freely. The detect script never overwrites it.

```json
{
  "extensions": [
    {
      "name": "Rust",
      "version": "1.82.0",
      "added_at": "2025-01-15T10:00:00+00:00",
      "description": "Installed via rustup. Toolchain at ~/.cargo/bin."
    }
  ]
}
```

---

## File structure

```
preflight/
├── detect.ps1          ← run this on Windows
├── detect.sh           ← run this on macOS / Linux
├── env-config.json     ← local dev copy of the snapshot (optional)
├── CLAUDE.md           ← Claude Code rules derived from your snapshot
└── mcp-server/
    ├── index.js        ← the MCP server
    ├── package.json
    └── node_modules/
```

---

## Tool reference

| Tool | Description |
|------|-------------|
| `get_environment` | Returns the full JSON contents of `~/.preflight/env-config.json` |
| `get_package_config` | Fetches latest version and CDN URLs for npm packages from live registry with 1 hour cache and static fallback |
| `generate_claude_md` | Generates a `CLAUDE.md` file in the current working directory with shell rules, package manager, CDN preference, versions, Flutter/Android setup, and Windows gotchas — all derived from your env-config.json |
