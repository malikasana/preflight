# preflight.json Specification

**Version:** `preflight-spec: "1.0"`

---

## What is preflight.json?

`preflight.json` is a small JSON file that any installed program, tool, or SDK can ship to register itself with preflight. When the detect script runs, it scans well-known directories for these files and merges their contents into the `extensions` array of `env-config.json` automatically — no manual editing required.

This lets third-party tools, internal utilities, and custom runtimes surface their version and configuration to Claude Code without modifying the detect script itself.

---

## Discovery

The detect script searches for `preflight.json` in this order:

1. Every directory listed in `PATH` (split on `;`)
2. Top-level subdirectories of common install roots:
   - `C:\Program Files`
   - `C:\Program Files (x86)`
   - `%LOCALAPPDATA%\Programs`
   - `%APPDATA%`
   - `D:\`

The first `preflight.json` found per unique path wins. Duplicates (same absolute path) are skipped.

---

## JSON Schema

```json
{
  "preflight-spec": "1.0",
  "name":           "<string, required>",
  "version":        "<string, required>",
  "description":    "<string, optional>",
  "homepage":       "<string, optional — URL>",
  "extra":          "<object, optional — any additional key/value pairs>"
}
```

### Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `preflight-spec` | string | no | Spec version. Should be `"1.0"`. Used for future compatibility. |
| `name` | string | **yes** | Display name of the tool. Must be unique across discovered files. |
| `version` | string | **yes** | Semver or any version tag (e.g. `"1.4.2"`, `"2024.3"`). |
| `description` | string | no | One-line summary of what the tool does. |
| `homepage` | string | no | Project or docs URL. |
| `extra` | object | no | Arbitrary key/value metadata (ports, paths, config locations, etc.). |

---

## Examples

### Redis

Place at `C:\Program Files\Redis\preflight.json`:

```json
{
  "preflight-spec": "1.0",
  "name": "Redis",
  "version": "7.2.4",
  "description": "In-memory data store used as database, cache, and message broker.",
  "homepage": "https://redis.io",
  "extra": {
    "port": 6379,
    "config_file": "C:\\Program Files\\Redis\\redis.windows.conf",
    "service_name": "Redis"
  }
}
```

### Nginx

Place at `C:\nginx\preflight.json`:

```json
{
  "preflight-spec": "1.0",
  "name": "Nginx",
  "version": "1.26.1",
  "description": "High-performance HTTP and reverse proxy server.",
  "homepage": "https://nginx.org",
  "extra": {
    "port": 80,
    "config_file": "C:\\nginx\\conf\\nginx.conf",
    "root_dir": "C:\\nginx\\html"
  }
}
```

### Custom internal tool

Place in any directory on `PATH`:

```json
{
  "preflight-spec": "1.0",
  "name": "deploy-tool",
  "version": "0.9.1",
  "description": "Internal deployment CLI for staging and production.",
  "extra": {
    "environments": ["staging", "production"],
    "config_dir": "C:\\Users\\me\\.deploy"
  }
}
```

---

## How entries appear in env-config.json

Each discovered `preflight.json` is merged into the `extensions` array:

```json
{
  "extensions": [
    {
      "name": "Redis",
      "version": "7.2.4",
      "added_at": "2026-05-26T14:00:00+05:00",
      "description": "In-memory data store used as database, cache, and message broker.",
      "source": "C:\\Program Files\\Redis\\preflight.json"
    }
  ]
}
```

Manually added entries in `extensions` are preserved across detect runs. Auto-discovered entries are deduplicated by `name` — the preflight.json version wins over a manually added entry with the same name.

---

## Authoring notes

- Keep `name` short and unique. It is used as the deduplication key.
- `version` should reflect the installed version, not the spec version.
- The `extra` object can hold any JSON-serializable data — ports, paths, feature flags, etc.
- The detect script never writes `preflight.json` files. It only reads them.
- `preflight-spec` is optional today but should be included for forward compatibility.
