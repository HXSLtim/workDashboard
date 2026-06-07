import { readFile, stat } from "node:fs/promises";
import { glob } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import { emptyProviderUsage, type ProviderUsage } from "../types.ts";
import { estimateCost } from "./pricing.ts";

// Parses Claude Code transcripts (~/.claude/projects/**/*.jsonl), aggregating
// token usage like ccusage. Per-file parse results are cached by mtime so each
// poll only re-reads files that actually changed — important as history grows.
const ROOT = join(homedir(), ".claude", "projects");

interface Entry {
  key: string; // message.id:requestId — for cross-file dedup
  date: string;
  model: string;
  tokens: number;
  cost: number;
  session: string;
}

const cache = new Map<string, { mtimeMs: number; entries: Entry[] }>();

function localDate(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

async function parseFile(file: string): Promise<Entry[]> {
  let text: string;
  try {
    text = await readFile(file, "utf8");
  } catch {
    return [];
  }
  const entries: Entry[] = [];
  for (const line of text.split("\n")) {
    if (!line.includes('"usage"')) continue;
    let o: any;
    try {
      o = JSON.parse(line);
    } catch {
      continue;
    }
    const u = o.message?.usage;
    if (o.type !== "assistant" || !u || !o.timestamp) continue;

    const model = o.message?.model ?? "unknown";
    if (model === "<synthetic>") continue;
    const input = u.input_tokens ?? 0;
    const output = u.output_tokens ?? 0;
    const cacheRead = u.cache_read_input_tokens ?? 0;
    const cacheWrite = u.cache_creation_input_tokens ?? 0;
    entries.push({
      key: `${o.message?.id ?? ""}:${o.requestId ?? ""}`,
      date: localDate(new Date(o.timestamp)),
      model,
      tokens: input + output + cacheRead + cacheWrite,
      cost: estimateCost(model, { input, output, cacheRead, cacheWrite }),
      session: o.sessionId ?? "",
    });
  }
  return entries;
}

export async function fetchClaudeUsage(): Promise<ProviderUsage> {
  const usage = emptyProviderUsage();
  const now = new Date();
  const today = localDate(now);
  const monthPrefix = today.slice(0, 7);

  let files: string[] = [];
  try {
    for await (const f of glob(`${ROOT}/**/*.jsonl`)) files.push(f);
  } catch {
    return usage;
  }

  const all: Entry[] = [];
  const live = new Set<string>();
  for (const file of files) {
    live.add(file);
    let mtimeMs = 0;
    try {
      mtimeMs = (await stat(file)).mtimeMs;
    } catch {
      continue;
    }
    let cached = cache.get(file);
    if (!cached || cached.mtimeMs !== mtimeMs) {
      cached = { mtimeMs, entries: await parseFile(file) };
      cache.set(file, cached);
    }
    all.push(...cached.entries);
  }
  for (const k of cache.keys()) if (!live.has(k)) cache.delete(k);

  const seen = new Set<string>();
  const sessionsToday = new Set<string>();
  for (const e of all) {
    if (e.key !== ":" && seen.has(e.key)) continue;
    seen.add(e.key);
    if (e.date.startsWith(monthPrefix)) {
      usage.month.tokens += e.tokens;
      usage.month.cost += e.cost;
      usage.byModel[e.model] = (usage.byModel[e.model] ?? 0) + e.tokens;
    }
    if (e.date === today) {
      usage.today.tokens += e.tokens;
      usage.today.cost += e.cost;
      if (e.session) sessionsToday.add(e.session);
    }
  }
  usage.sessions = sessionsToday.size;
  return usage;
}
