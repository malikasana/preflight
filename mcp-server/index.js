import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { readFileSync, existsSync } from "fs";
import path from "path";
import os from "os";
import { fileURLToPath } from "url";
import { z } from "zod";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const server = new McpServer({
  name: "preflight-mcp",
  version: "1.0.0",
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

// ─── start ────────────────────────────────────────────────────────────────────

const transport = new StdioServerTransport();
await server.connect(transport);
console.error("preflight-mcp server running on stdio");
