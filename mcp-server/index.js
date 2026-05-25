import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { readFileSync, existsSync } from "fs";
import path from "path";
import os from "os";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const server = new McpServer({
  name: "preflight-mcp",
  version: "1.0.0",
});

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

const transport = new StdioServerTransport();
await server.connect(transport);
console.error("preflight-mcp server running on stdio");
