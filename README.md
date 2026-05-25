# preflight

**preflight** gives Claude Code accurate knowledge of your machine before every conversation — OS, runtimes, SDKs, editors, browsers, and more.

Without preflight, Claude guesses: wrong package manager, wrong Python version, missing SDKs. Preflight solves this by snapshotting your environment once and letting Claude read it on demand.

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
2. The **MCP server** (`mcp-server/`) exposes a `get_environment` tool that reads that snapshot.
3. Claude calls `get_environment` at the start of a session and knows exactly what you have installed.

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

```bash
cd mcp-server
npm install
```

This only needs to be done once (or after a `git pull` that changes `package.json`).

---

## Step 3 — Connect to Claude Code

You need to tell Claude Code where the MCP server lives. There are two ways.

### Option A — CLI (quickest)

```bash
claude mcp add preflight-mcp node "D:/AI Projects/preflight/mcp-server/index.js"
```

### Option B — Edit settings.json manually

Open `~/.claude/settings.json` (global) or `.claude/settings.json` (project-only) and add:

```json
{
  "mcpServers": {
    "preflight-mcp": {
      "command": "node",
      "args": ["D:/AI Projects/preflight/mcp-server/index.js"]
    }
  }
}
```

> Use forward slashes or escaped backslashes in the path. On Windows the full path looks like `D:/AI Projects/preflight/mcp-server/index.js`.

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
