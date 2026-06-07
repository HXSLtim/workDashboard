import { execFile } from "node:child_process";
import { promisify } from "node:util";
import type {
  CIStatus,
  GitHubState,
  InboxItem,
  PullRequestInfo,
  RunningAction,
} from "../types.ts";

const exec = promisify(execFile);

// Run a `gh` subcommand and parse its JSON stdout. Auth is handled entirely by
// the gh CLI (keyring), so the daemon never touches a token.
async function gh<T>(args: string[]): Promise<T> {
  const { stdout } = await exec("gh", args, {
    maxBuffer: 10 * 1024 * 1024,
    timeout: 30_000,
  });
  return JSON.parse(stdout) as T;
}

function rollupToStatus(state: string | null | undefined): CIStatus {
  switch (state) {
    case "SUCCESS":
      return "green";
    case "FAILURE":
    case "ERROR":
      return "red";
    case "PENDING":
    case "EXPECTED":
      return "pending";
    default:
      return "none";
  }
}

const QUERY = `
query {
  viewer {
    login
    name
    avatarUrl
    contributionsCollection {
      contributionCalendar {
        totalContributions
        weeks {
          contributionDays { date contributionCount }
        }
      }
    }
  }
  reviewRequested: search(query: "is:open is:pr review-requested:@me", type: ISSUE, first: 25) {
    issueCount
    nodes { ... on PullRequest {
      title url repository { nameWithOwner } author { login }
      commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
    } }
  }
  myPRs: search(query: "is:open is:pr author:@me", type: ISSUE, first: 25) {
    issueCount
    nodes { ... on PullRequest {
      title url repository { nameWithOwner } author { login }
      commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
    } }
  }
}`;

interface PrNode {
  title: string;
  url: string;
  repository: { nameWithOwner: string };
  author: { login: string } | null;
  commits: { nodes: { commit: { statusCheckRollup: { state: string } | null } }[] };
}

interface QueryResponse {
  data: {
    viewer: {
      login: string;
      name: string | null;
      avatarUrl: string;
      contributionsCollection: {
        contributionCalendar: {
          totalContributions: number;
          weeks: { contributionDays: { date: string; contributionCount: number }[] }[];
        };
      };
    };
    reviewRequested: { issueCount: number; nodes: PrNode[] };
    myPRs: { issueCount: number; nodes: PrNode[] };
  };
}

function toPR(n: PrNode): PullRequestInfo {
  const rollup = n.commits.nodes[0]?.commit.statusCheckRollup?.state;
  return {
    title: n.title,
    url: n.url,
    repo: n.repository.nameWithOwner,
    author: n.author?.login ?? "unknown",
    ciStatus: rollupToStatus(rollup),
  };
}

function localDate(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

const HEATMAP_WEEKS = 18;

export async function fetchGitHub(): Promise<GitHubState> {
  const resp = await gh<QueryResponse>(["api", "graphql", "-f", `query=${QUERY}`]);
  const v = resp.data.viewer;
  const cal = v.contributionsCollection.contributionCalendar;
  const today = localDate(new Date());

  let todayCount = 0;
  const weeks = cal.weeks.slice(-HEATMAP_WEEKS).map((w) =>
    w.contributionDays.map((d) => {
      if (d.date === today) todayCount = d.contributionCount;
      return d.contributionCount;
    }),
  );

  const reviewRequestList = resp.data.reviewRequested.nodes.map(toPR);
  const myOpenPRs = resp.data.myPRs.nodes.map(toPR);
  const runningActions: RunningAction[] = myOpenPRs
    .filter((pr) => pr.ciStatus === "pending")
    .map((pr) => ({ repo: pr.repo, workflow: pr.title, url: pr.url }));

  return {
    profile: { login: v.login, name: v.name ?? v.login, avatarUrl: v.avatarUrl },
    contributions: { total: cal.totalContributions, today: todayCount, weeks },
    reviewRequests: resp.data.reviewRequested.issueCount,
    reviewRequestList,
    myOpenPRs,
    runningActions,
  };
}

interface NotificationItem {
  reason: string;
  updated_at: string;
  subject: { title: string; type: string; url: string | null };
  repository: { full_name: string };
}

const REASON_TO_KIND: Record<string, InboxItem["type"]> = {
  review_requested: "review",
  mention: "mention",
  assign: "assign",
  ci_activity: "ci",
};

function apiUrlToHtml(url: string | null, repo: string): string {
  if (!url) return `https://github.com/${repo}`;
  return url
    .replace("https://api.github.com/repos/", "https://github.com/")
    .replace("/pulls/", "/pull/");
}

const INBOX_LIMIT = 15;

export async function fetchInbox(): Promise<InboxItem[]> {
  const notifs = await gh<NotificationItem[]>([
    "api",
    "/notifications",
    "--method",
    "GET",
    "-f",
    "per_page=50",
  ]);

  const folded = new Map<string, InboxItem>();
  for (const n of notifs) {
    const kind = REASON_TO_KIND[n.reason] ?? "other";
    const key = `${n.repository.full_name}|${kind}|${n.subject.title}`;
    const existing = folded.get(key);
    if (existing) {
      existing.count++;
      if (n.updated_at > existing.ts) existing.ts = n.updated_at;
    } else {
      folded.set(key, {
        type: kind,
        title: n.subject.title,
        url: apiUrlToHtml(n.subject.url, n.repository.full_name),
        repo: n.repository.full_name,
        ts: n.updated_at,
        count: 1,
      });
    }
  }

  return [...folded.values()]
    .sort((a, b) => b.ts.localeCompare(a.ts))
    .slice(0, INBOX_LIMIT);
}
