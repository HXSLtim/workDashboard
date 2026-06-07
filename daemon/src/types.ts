// Unified schema written to ~/.workhub/state.json by the daemon and read by the
// macOS notch app. Keep this the single source of truth; the Swift side mirrors
// these shapes as Codable structs.

export type CIStatus = "green" | "red" | "pending" | "none";

export interface PullRequestInfo {
  title: string;
  url: string;
  repo: string; // "owner/name"
  author: string;
  ciStatus: CIStatus;
}

export interface RunningAction {
  repo: string;
  workflow: string;
  url: string;
}

export interface GitHubProfile {
  login: string;
  name: string;
  avatarUrl: string;
}

export interface Contributions {
  total: number; // total contributions in the last year
  today: number; // contributions today
  weeks: number[][]; // recent weeks, each a 7-length array of daily counts (heatmap)
}

export interface GitHubState {
  profile: GitHubProfile;
  contributions: Contributions;
  reviewRequests: number;
  reviewRequestList: PullRequestInfo[];
  myOpenPRs: PullRequestInfo[];
  runningActions: RunningAction[];
}

// Local-usage stats parsed from Claude Code / Codex on-disk logs (subscription
// usage — no billing API involved). Cost is a best-effort estimate.
export interface UsageWindow {
  tokens: number;
  cost: number; // estimated USD
}

export interface ProviderUsage {
  today: UsageWindow;
  month: UsageWindow;
  byModel: Record<string, number>; // model -> tokens this month
  sessions: number; // sessions active today
}

export interface UsageState {
  claude: ProviderUsage;
  codex: ProviderUsage;
}

export type InboxKind = "mention" | "assign" | "review" | "ci" | "other";

export interface InboxItem {
  type: InboxKind;
  title: string;
  url: string;
  repo: string;
  ts: string; // ISO8601 — most recent occurrence
  count: number; // how many notifications folded into this one
}

export interface SourceStatus {
  ok: boolean;
  error?: string;
  updatedAt: string; // ISO8601
}

export interface HubState {
  updatedAt: string; // ISO8601
  github: GitHubState;
  usage: UsageState;
  inbox: InboxItem[];
  sources: Record<string, SourceStatus>;
}

export function emptyProviderUsage(): ProviderUsage {
  return {
    today: { tokens: 0, cost: 0 },
    month: { tokens: 0, cost: 0 },
    byModel: {},
    sessions: 0,
  };
}

export function emptyGitHub(): GitHubState {
  return {
    profile: { login: "", name: "", avatarUrl: "" },
    contributions: { total: 0, today: 0, weeks: [] },
    reviewRequests: 0,
    reviewRequestList: [],
    myOpenPRs: [],
    runningActions: [],
  };
}
