import { readFile, stat } from "node:fs/promises";
import { glob } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import { emptyProviderUsage, type ProviderUsage } from "../types.ts";
import { estimateCost } from "./pricing.ts";

// Parses Codex rollout files (~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl).
// Each session's final total_token_usage is the cumulative usage, attributed to
// the session's date. Per-file results cached by mtime (sessions are append-only,
// so a finished session's file never changes again — cheap on later polls).
const ROOT = join(homedir(), ".codex", "sessions");

interface Entry {
  date: string;
  model: string;
  tokens: number;
  cost: number;
}

const cache = new Map<string, { mtimeMs: number; entry: Entry | null }>();

function localDate(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

function dateFromPath(path: string): string | null {
  return path.match(/rollout-(\d{4}-\d{2}-\d{2})T/)?.[1] ?? null;
}

async function parseFile(file: string, date: string): Promise<Entry | null> {
  let text: string;
  try {
    text = await readFile(file, "utf8");
  } catch {
    return null;
  }
  let model = "codex";
  let lastTotal: any;
  for (const line of text.split("\n")) {
    if (!line) continue;
    let o: any;
    try {
      o = JSON.parse(line);
    } catch {
      continue;
    }
    if (o.payload?.model) model = o.payload.model;
    if (o.payload?.type === "token_count" && o.payload.info?.total_token_usage) {
      lastTotal = o.payload.info.total_token_usage;
    }
  }
  if (!lastTotal) return null;
  return {
    date,
    model,
    tokens: lastTotal.total_tokens ?? 0,
    cost: estimateCost(model, {
      input: lastTotal.input_tokens ?? 0,
      output: (lastTotal.output_tokens ?? 0) + (lastTotal.reasoning_output_tokens ?? 0),
      cacheRead: lastTotal.cached_input_tokens ?? 0,
    }),
  };
}

export async function fetchCodexUsage(): Promise<ProviderUsage> {
  const usage = emptyProviderUsage();
  const now = new Date();
  const today = localDate(now);
  const monthPrefix = today.slice(0, 7);

  let files: string[] = [];
  try {
    for await (const f of glob(`${ROOT}/**/rollout-*.jsonl`)) files.push(f);
  } catch {
    return usage;
  }

  const live = new Set<string>();
  for (const file of files) {
    const date = dateFromPath(file);
    if (!date || !date.startsWith(monthPrefix)) continue; // only need this month
    live.add(file);

    let mtimeMs = 0;
    try {
      mtimeMs = (await stat(file)).mtimeMs;
    } catch {
      continue;
    }
    let cached = cache.get(file);
    if (!cached || cached.mtimeMs !== mtimeMs) {
      cached = { mtimeMs, entry: await parseFile(file, date) };
      cache.set(file, cached);
    }
    const e = cached.entry;
    if (!e) continue;

    usage.month.tokens += e.tokens;
    usage.month.cost += e.cost;
    usage.byModel[e.model] = (usage.byModel[e.model] ?? 0) + e.tokens;
    if (e.date === today) {
      usage.today.tokens += e.tokens;
      usage.today.cost += e.cost;
      usage.sessions += 1;
    }
  }
  for (const k of cache.keys()) if (!live.has(k)) cache.delete(k);

  return usage;
}
