#!/usr/bin/env node
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { readFileSync, writeFileSync, existsSync } from "fs";
import path from "path";
import os from "os";
import { fileURLToPath } from "url";
import { z } from "zod";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const server = new McpServer({
  name: "preflight-mcp",
  version: "1.1.0",
});

// ─── get_environment ──────────────────────────────────────────────────────────

function resolveConfigPath() {
  const candidates = [
    path.join(os.homedir(), ".preflight", "env-config.json"),
    path.join(__dirname, "..", "env-config.json"),
  ];
  for (const p of candidates) {
    if (existsSync(p)) return p;
  }
  return null;
}

server.tool(
  "get_environment",
  "Read and return the full contents of the preflight env-config.json file",
  {},
  async () => {
    const configPath = resolveConfigPath();

    if (!configPath) {
      const expected = path.join(os.homedir(), ".preflight", "env-config.json");
      return {
        content: [
          {
            type: "text",
            text: [
              "env-config.json not found.",
              "",
              "Run the detect script first to generate it:",
              "  Windows : powershell -ExecutionPolicy Bypass -File detect.ps1",
              "  Mac/Linux: bash detect.sh",
              "",
              `Expected location: ${expected}`,
            ].join("\n"),
          },
        ],
      };
    }

    try {
      const contents = readFileSync(configPath, "utf-8").replace(/^﻿/, "");
      return {
        content: [{ type: "text", text: contents }],
      };
    } catch (err) {
      return {
        content: [{ type: "text", text: `Failed to read ${configPath}: ${err.message}` }],
      };
    }
  }
);

// ─── get_package_config ───────────────────────────────────────────────────────

const FALLBACK = {
  "three":                     { version: "0.177.0" },
  "gsap":                      { version: "3.12.5" },
  "@gsap/ScrollTrigger":       { version: "3.12.5" },
  "lenis":                     { version: "1.1.14" },
  "tailwindcss":               { version: "3.4.17" },
  "react":                     { version: "18.3.1" },
  "react-dom":                 { version: "18.3.1" },
  "vue":                       { version: "3.4.21" },
  "vite":                      { version: "5.4.8" },
  "typescript":                { version: "5.4.5" },
  "axios":                     { version: "1.7.2" },
  "lodash":                    { version: "4.17.21" },
  "d3":                        { version: "7.9.0" },
  "chart.js":                  { version: "4.4.3" },
  "framer-motion":             { version: "11.3.8" },
  "@modelcontextprotocol/sdk": { version: "1.12.0", noCdn: true },
  "zod":                       { version: "3.25.0", noCdn: true },
  "express":                   { version: "4.19.2", noCdn: true },
  "socket.io":                 { version: "4.7.5", noCdn: true },
  "prisma":                    { version: "5.16.0", noCdn: true },
};

const CACHE_TTL = 60 * 60 * 1000;
const pkgCache  = new Map();

function buildCdnUrls(pkg, version) {
  return {
    jsdelivr_esm:    `https://cdn.jsdelivr.net/npm/${pkg}@${version}/+esm`,
    jsdelivr_bundle: `https://cdn.jsdelivr.net/npm/${pkg}@${version}/bundled/${pkg}.min.js`,
    unpkg:           `https://unpkg.com/${pkg}@${version}`,
  };
}

async function fetchLiveVersion(pkg) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 5000);
  try {
    const res = await fetch(`https://registry.npmjs.org/${pkg}/latest`, {
      signal: controller.signal,
    });
    if (!res.ok) return null;
    const data = await res.json();
    return data.version ?? null;
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}

function buildResult(pkg, version, source, cached, cachedAt, noCdn) {
  const result = { package: pkg, version, source, cached, cachedAt, install: `npm install ${pkg}` };
  if (!noCdn) result.cdn = buildCdnUrls(pkg, version);
  return result;
}

server.tool(
  "get_package_config",
  "Get the correct CDN URL and latest version for any npm package",
  { packages: z.array(z.string()).describe('Array of npm package names, e.g. ["three", "gsap"]') },
  async ({ packages }) => {
    const now = Date.now();

    const hits   = new Map();
    const misses = [];

    for (const pkg of packages) {
      const entry = pkgCache.get(pkg);
      if (entry && now - entry.cachedAt < CACHE_TTL) {
        hits.set(pkg, entry);
      } else {
        misses.push(pkg);
      }
    }

    const fetched = await Promise.allSettled(
      misses.map((pkg) => fetchLiveVersion(pkg).then((version) => ({ pkg, version })))
    );

    // Index fetch results by package name for O(1) lookup
    const liveMap = new Map();
    for (const result of fetched) {
      if (result.status === "fulfilled") {
        liveMap.set(result.value.pkg, result.value.version);
      }
    }

    const results = packages.map((pkg) => {
      // Cache hit
      if (hits.has(pkg)) {
        const e = hits.get(pkg);
        return buildResult(pkg, e.version, e.source, true, new Date(e.cachedAt).toISOString(), e.noCdn);
      }

      const liveVersion = liveMap.get(pkg) ?? null;
      const fallback    = FALLBACK[pkg];

      if (!liveVersion && !fallback) {
        return { package: pkg, error: "Package not found in registry or fallback list" };
      }

      const version = liveVersion ?? fallback.version;
      const source  = liveVersion ? "live" : "fallback";
      // Respect no-cdn flag from fallback data even when version came from live fetch
      const noCdn   = fallback?.noCdn ?? false;

      pkgCache.set(pkg, { version, source, noCdn, cachedAt: now });

      return buildResult(pkg, version, source, false, new Date(now).toISOString(), noCdn);
    });

    return {
      content: [{ type: "text", text: JSON.stringify(results, null, 2) }],
    };
  }
);

// ─── generate_claude_md ───────────────────────────────────────────────────────

server.tool(
  "generate_claude_md",
  "Generate a CLAUDE.md file in the current working directory from your ~/.preflight/env-config.json snapshot",
  {},
  async () => {
    const configPath = resolveConfigPath();

    if (!configPath) {
      const expected = path.join(os.homedir(), ".preflight", "env-config.json");
      return {
        content: [
          {
            type: "text",
            text: [
              "env-config.json not found. Run the detect script first.",
              `Expected: ${expected}`,
            ].join("\n"),
          },
        ],
      };
    }

    let cfg;
    try {
      cfg = JSON.parse(readFileSync(configPath, "utf-8").replace(/^﻿/, ""));
    } catch (err) {
      return {
        content: [{ type: "text", text: `Failed to read ${configPath}: ${err.message}` }],
      };
    }

    const sys      = cfg.system       ?? {};
    const shell    = cfg.shell        ?? {};
    const runtimes = cfg.runtimes     ?? {};
    const mobile   = cfg.mobile_dev   ?? {};
    const network  = cfg.network      ?? {};
    const hw       = cfg.hardware     ?? {};
    const envVars  = shell.env_vars   ?? {};
    const isWin    = (sys.os ?? "").toLowerCase().includes("windows");

    // Derive fastest CDN from latency data
    const latencies = network.cdn_latency_ms ?? {};
    let preferredCdn = "jsdelivr";
    let minMs = Infinity;
    for (const [cdn, raw] of Object.entries(latencies)) {
      const ms = parseInt(raw, 10);
      if (!isNaN(ms) && ms < minMs) { minMs = ms; preferredCdn = cdn; }
    }
    const slowestCdn = Object.entries(latencies)
      .map(([cdn, raw]) => [cdn, parseInt(raw, 10)])
      .filter(([, ms]) => !isNaN(ms))
      .sort((a, b) => b[1] - a[1])[0];

    // Derive package manager
    const yarnFound = runtimes.yarn && runtimes.yarn !== "not found";
    const pnpmFound = runtimes.pnpm && runtimes.pnpm !== "not found";
    const pkgMgr    = pnpmFound ? "pnpm" : yarnFound ? "yarn" : "npm";

    const L = [];

    L.push(`# Environment Rules for Claude Code`);
    L.push(`# Generated from env-config.json — ${configPath}`);
    L.push(``);

    // Shell
    L.push(`## Shell & Execution`);
    if (isWin) {
      L.push(`- Platform: ${sys.os}. Always use PowerShell syntax, not bash.`);
      L.push(`- Run scripts with: \`powershell -ExecutionPolicy Bypass -File script.ps1\``);
      L.push(`- Execution policy is ${shell.powershell?.execution_policy ?? "RemoteSigned"} — unsigned local scripts need \`-ExecutionPolicy Bypass\`.`);
      if (shell.default_shell) {
        L.push(`- Default shell is Git Bash (\`${shell.default_shell}\`) but prefer PowerShell for system tasks.`);
      }
      L.push(`- Path separator is \`\\\`. Always double-quote paths containing spaces.`);
      L.push(`- No \`&&\` in PowerShell 5.1 — chain with \`;\` or \`if ($?) { }\`.`);
    } else {
      L.push(`- Platform: ${sys.os}.`);
    }
    L.push(``);

    // Package manager
    L.push(`## Package Manager`);
    L.push(`- Use **${pkgMgr} only**.${!yarnFound && !pnpmFound ? " yarn and pnpm are not installed." : ""}`);
    if (runtimes.npm) {
      const globals = (runtimes.global_npm_packages ?? [])
        .map(p => `\`${p.split("@")[0]}\``)
        .join(", ");
      L.push(`- npm ${runtimes.npm} / Node ${runtimes.node ?? "unknown"}. Global packages: ${globals}.`);
    }
    L.push(`- Do not suggest yarn or pnpm without confirming installation first.`);
    L.push(``);

    // CDN
    L.push(`## CDN`);
    const latencyStr = Object.entries(latencies).map(([c, v]) => `${c}: ${v}`).join(", ");
    L.push(`- Prefer **${preferredCdn}** — lowest latency on this machine (${latencyStr}).`);
    if (slowestCdn) {
      L.push(`- Avoid ${slowestCdn[0]} when latency matters (${slowestCdn[1]} ms).`);
    }
    L.push(``);

    // Versions
    L.push(`## Detected Versions`);
    if (runtimes.node) L.push(`- Node ${runtimes.node} / npm ${runtimes.npm}`);
    if (runtimes.python) {
      const pyPkgs = (runtimes.python_packages ?? []).join(", ");
      L.push(`- Python ${runtimes.python}${pyPkgs ? ` — ${pyPkgs}. Install other packages before use.` : ""}`);
    }
    if (runtimes.git) {
      const g = runtimes.git;
      L.push(`- Git ${g.version} — user: ${g.username}, email: ${g.email}, branch: ${g.default_branch}`);
    }
    if (runtimes.docker && runtimes.docker !== "not found") {
      L.push(`- Docker ${runtimes.docker}${shell.wsl?.installed ? " (uses WSL2 backend)" : ""}`);
    }
    if (cfg.editors?.vscode) {
      const extCount = cfg.editors.vscode.extensions?.length ?? 0;
      L.push(`- VS Code ${cfg.editors.vscode.version} with ${extCount} extensions`);
    }
    if (mobile.flutter) L.push(`- Flutter ${mobile.flutter} / Dart ${mobile.dart}`);
    if (mobile.android_sdk) L.push(`- Android SDK ${mobile.android_sdk.version} at \`${mobile.android_sdk.path}\``);
    for (const ext of (cfg.extensions ?? [])) {
      L.push(`- ${ext.name} ${ext.version}${ext.description ? ` — ${ext.description.split(".")[0]}.` : ""}`);
    }
    L.push(``);

    // Env vars
    if (Object.keys(envVars).length > 0) {
      L.push(`## Environment Variables (permanently set at user level)`);
      for (const [k, v] of Object.entries(envVars)) L.push(`- \`${k}\` = \`${v}\``);
      L.push(`- New env vars require a fresh terminal session to take effect.`);
      L.push(``);
    }

    // Flutter & Android
    if (mobile.flutter || mobile.android_sdk) {
      L.push(`## Flutter & Android Setup`);
      if (mobile.flutter) {
        L.push(`- Flutter is on PATH via \`${envVars.FLUTTER_HOME ?? "D:\\flutter"}\\bin\`. FLUTTER_HOME is set.`);
      }
      if (mobile.android_sdk) {
        L.push(`- Android SDK: \`${mobile.android_sdk.path}\` — platform-tools, build-tools ${mobile.android_sdk.version}, NDK, emulator present.`);
        L.push(`- \`adb.exe\` at \`${mobile.android_sdk.path}\\platform-tools\\adb.exe\`.`);
      }
      if (envVars.JAVA_HOME) L.push(`- JAVA_HOME points to \`${envVars.JAVA_HOME}\` — sdkmanager and Gradle should work.`);
      if (hw.cpu) L.push(`- Prefer physical device or \`flutter run -d chrome\` — emulator performance is limited on this hardware.`);
      L.push(``);
    }

    // Windows gotchas
    if (isWin) {
      L.push(`## Windows Gotchas`);
      L.push(`- Environment variables set via \`[Environment]::SetEnvironmentVariable\` apply only to new sessions.`);
      const browsers = network.browsers ?? {};
      const missing  = Object.entries(browsers).filter(([, v]) => v === "not found").map(([n]) => n);
      const present  = Object.entries(browsers).filter(([, v]) => v !== "not found").map(([n, v]) => `${n.charAt(0).toUpperCase() + n.slice(1)} ${v.split(".")[0]}`);
      if (missing.length) L.push(`- ${missing.map(n => n.charAt(0).toUpperCase() + n.slice(1)).join(", ")} not installed. Available: ${present.join(", ")}.`);
      if (hw.disk_D) L.push(`- D:\\ drive: ${hw.disk_D.total_GB} GB total, ~${hw.disk_D.free_GB} GB free. Check space before large downloads.`);
      if (network.type) L.push(`- Network: ${network.type}.`);
      const pathEntries = shell.path_entries ?? [];
      if (pathEntries.some(p => p.toLowerCase().includes("ffmpeg"))) L.push(`- ffmpeg is on PATH.`);
      if (pathEntries.some(p => p.toLowerCase().includes("ollama"))) L.push(`- Ollama is installed and on PATH.`);
      if (shell.wsl?.installed) {
        const def = shell.wsl.distros?.find(d => d.is_default);
        if (def) L.push(`- WSL2 installed. ${def.name} is the default distro (${def.state}). Start with: \`wsl\` or \`wsl -d ${def.name}\`.`);
      }
      L.push(``);
    }

    // Hardware
    if (hw.cpu || hw.ram_GB) {
      L.push(`## Hardware`);
      if (hw.cpu) L.push(`- CPU: ${hw.cpu}.`);
      if (hw.ram_GB) L.push(`- RAM: ${hw.ram_GB} GB.`);
      L.push(`- Performance-heavy tasks (emulator, Docker builds) will be slow — plan accordingly.`);
      L.push(``);
    }

    const content = L.join("\n");
    const outPath = path.join(process.cwd(), "CLAUDE.md");
    writeFileSync(outPath, content, "utf-8");

    return {
      content: [{ type: "text", text: `CLAUDE.md written to ${outPath}` }],
    };
  }
);

// ─── start ────────────────────────────────────────────────────────────────────

const transport = new StdioServerTransport();
await server.connect(transport);
console.error("preflight-mcp server running on stdio");
