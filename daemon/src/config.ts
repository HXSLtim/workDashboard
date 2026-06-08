import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

// Where the daemon publishes state for the notch app to read.
export const HUB_DIR = join(homedir(), ".workhub");
export const STATE_PATH = join(HUB_DIR, "state.json");
export const SECRETS_PATH = join(HUB_DIR, "secrets.json");
export const SERVERS_PATH = join(HUB_DIR, "servers.json");

export interface ServerConfig {
  name: string;
  host: string;
  user: string;
  port?: number;
  os: "linux" | "windows";
}

export interface ServersFile {
  identityFile: string; // path to the SSH private key (~ allowed)
  servers: ServerConfig[];
}

// Reads ~/.workhub/servers.json (gitignored). Returns null if not configured.
export function loadServers(): ServersFile | null {
  try {
    const f = JSON.parse(readFileSync(SERVERS_PATH, "utf8")) as ServersFile;
    if (!Array.isArray(f.servers)) return null;
    return f;
  } catch {
    return null;
  }
}

// Expand a leading ~ to the home directory.
export function expandHome(p: string): string {
  return p.startsWith("~") ? join(homedir(), p.slice(1)) : p;
}

// Anthropic Admin API key (sk-ant-admin...) for the Usage & Cost API.
// Resolution order: env var, then ~/.workhub/secrets.json {"anthropicAdminKey": "..."}.
// Returns null if unconfigured — the AI source then publishes an empty (but valid) shape.
export function anthropicAdminKey(): string | null {
  if (process.env.ANTHROPIC_ADMIN_KEY) return process.env.ANTHROPIC_ADMIN_KEY;
  try {
    const secrets = JSON.parse(readFileSync(SECRETS_PATH, "utf8"));
    return secrets.anthropicAdminKey ?? null;
  } catch {
    return null;
  }
}

// Poll cadence (ms). GitHub search API is generous but we stay polite.
export const POLL_INTERVAL_MS = 60_000;

// Monthly AI budget in USD, used to compute the warning percentage shown in the
// notch. null = no limit configured yet. Override with WORKHUB_AI_LIMIT.
export const AI_MONTHLY_LIMIT: number | null = process.env.WORKHUB_AI_LIMIT
  ? Number(process.env.WORKHUB_AI_LIMIT)
  : null;
