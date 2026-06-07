import { POLL_INTERVAL_MS, STATE_PATH } from "./config.ts";
import { writeState } from "./state.ts";
import { fetchGitHub, fetchInbox } from "./sources/github.ts";
import { fetchClaudeUsage } from "./sources/claudeUsage.ts";
import { fetchCodexUsage } from "./sources/codexUsage.ts";
import {
  emptyGitHub,
  emptyProviderUsage,
  type HubState,
  type SourceStatus,
} from "./types.ts";

// Run one source, isolating failures so a single broken provider never blanks the
// whole dashboard. Returns the value plus a health record for the `sources` map.
async function guard<T>(
  name: string,
  fn: () => Promise<T>,
  fallback: T,
): Promise<{ value: T; status: SourceStatus }> {
  const updatedAt = new Date().toISOString();
  try {
    return { value: await fn(), status: { ok: true, updatedAt } };
  } catch (err) {
    const error = err instanceof Error ? err.message : String(err);
    console.error(`[${name}] failed: ${error}`);
    return { value: fallback, status: { ok: false, error, updatedAt } };
  }
}

async function collect(): Promise<HubState> {
  const [github, inbox, claude, codex] = await Promise.all([
    guard("github", fetchGitHub, emptyGitHub()),
    guard("inbox", fetchInbox, []),
    guard("claude", fetchClaudeUsage, emptyProviderUsage()),
    guard("codex", fetchCodexUsage, emptyProviderUsage()),
  ]);

  return {
    updatedAt: new Date().toISOString(),
    github: github.value,
    inbox: inbox.value,
    usage: { claude: claude.value, codex: codex.value },
    sources: {
      github: github.status,
      inbox: inbox.status,
      claude: claude.status,
      codex: codex.status,
    },
  };
}

async function tick(): Promise<void> {
  const state = await collect();
  await writeState(state);
  const g = state.github;
  const u = state.usage;
  console.log(
    `[${state.updatedAt}] commits(total:${g.contributions.total} today:${g.contributions.today}) ` +
      `review:${g.reviewRequests} myPRs:${g.myOpenPRs.length} inbox:${state.inbox.length} ` +
      `claude:${(u.claude.today.tokens / 1000).toFixed(0)}k codex:${(u.codex.today.tokens / 1000).toFixed(0)}k -> ${STATE_PATH}`,
  );
}

async function main(): Promise<void> {
  const once = process.argv.includes("--once");
  await tick();
  if (once) return;

  console.log(`hub-daemon polling every ${POLL_INTERVAL_MS / 1000}s. Ctrl-C to stop.`);
  const timer = setInterval(() => {
    tick().catch((err) => console.error("tick error:", err));
  }, POLL_INTERVAL_MS);

  const stop = () => {
    clearInterval(timer);
    process.exit(0);
  };
  process.on("SIGINT", stop);
  process.on("SIGTERM", stop);
}

main().catch((err) => {
  console.error("fatal:", err);
  process.exit(1);
});
