import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { expandHome, loadServers, type ServerConfig } from "../config.ts";
import type { ServerStatus } from "../types.ts";

const exec = promisify(execFile);

// Linux: emit KEY=value lines we can parse.
const LINUX_CMD = [
  'echo "LOAD=$(cut -d\\" \\" -f1 /proc/loadavg)"',
  'echo "CORES=$(nproc)"',
  'free -m | awk \'/Mem:/{print "MEM_USED="$3; print "MEM_TOTAL="$2}\'',
  'df -P / | awk \'NR==2{print "DISK_PCT="$5}\'',
  'echo "UPSEC=$(cut -d. -f1 /proc/uptime)"',
].join("; ");

// Windows: a PowerShell script sent via -EncodedCommand (base64 UTF-16LE) to
// avoid all the SSH/cmd quoting pitfalls.
const WINDOWS_PS = [
  "$ProgressPreference='SilentlyContinue'",
  "$o=Get-CimInstance Win32_OperatingSystem",
  "$c=(Get-CimInstance Win32_Processor|Measure-Object -Property LoadPercentage -Average).Average",
  "$v=Get-Volume -DriveLetter C",
  'Write-Output "CPU=$c"',
  'Write-Output "MEM_USED=$([math]::Round(($o.TotalVisibleMemorySize-$o.FreePhysicalMemory)/1024))"',
  'Write-Output "MEM_TOTAL=$([math]::Round($o.TotalVisibleMemorySize/1024))"',
  'Write-Output "DISK_PCT=$([math]::Round(($v.Size-$v.SizeRemaining)/$v.Size*100))"',
  'Write-Output "UPSEC=$([int]((Get-Date)-$o.LastBootUpTime).TotalSeconds)"',
].join("; ");

function remoteCommand(os: ServerConfig["os"]): string {
  if (os === "windows") {
    const enc = Buffer.from(WINDOWS_PS, "utf16le").toString("base64");
    return `powershell -NoProfile -EncodedCommand ${enc}`;
  }
  return LINUX_CMD;
}

function parseKV(out: string): Record<string, string> {
  const kv: Record<string, string> = {};
  for (const line of out.split(/\r?\n/)) {
    const m = line.match(/^([A-Z_]+)=(.*)$/);
    if (m) kv[m[1]] = m[2].trim();
  }
  return kv;
}

function num(v: string | undefined): number | null {
  if (v == null) return null;
  const n = parseFloat(v.replace("%", ""));
  return Number.isFinite(n) ? n : null;
}

async function probe(s: ServerConfig, identity: string): Promise<ServerStatus> {
  const base: ServerStatus = {
    name: s.name,
    host: s.host,
    os: s.os,
    online: false,
    cpuPct: null,
    memPct: null,
    diskPct: null,
    uptimeSec: null,
    latencyMs: null,
  };
  const started = Date.now();
  try {
    const { stdout } = await exec(
      "ssh",
      [
        "-i", identity,
        "-o", "BatchMode=yes",
        "-o", "ConnectTimeout=8",
        "-o", "StrictHostKeyChecking=accept-new",
        "-p", String(s.port ?? 22),
        `${s.user}@${s.host}`,
        remoteCommand(s.os),
      ],
      { timeout: 15_000, maxBuffer: 1024 * 1024 },
    );
    const kv = parseKV(stdout);
    const latencyMs = Date.now() - started;

    let cpuPct: number | null;
    if (s.os === "windows") {
      cpuPct = num(kv.CPU);
    } else {
      const load = num(kv.LOAD);
      const cores = num(kv.CORES) || 1;
      cpuPct = load == null ? null : Math.round((load / cores) * 100);
    }
    const memUsed = num(kv.MEM_USED);
    const memTotal = num(kv.MEM_TOTAL);
    const memPct =
      memUsed != null && memTotal ? Math.round((memUsed / memTotal) * 100) : null;

    return {
      ...base,
      online: true,
      cpuPct,
      memPct,
      diskPct: num(kv.DISK_PCT),
      uptimeSec: num(kv.UPSEC),
      latencyMs,
    };
  } catch (err) {
    return {
      ...base,
      error: (err instanceof Error ? err.message : String(err)).slice(0, 120),
    };
  }
}

export async function fetchServers(): Promise<ServerStatus[]> {
  const cfg = loadServers();
  if (!cfg) return [];
  const identity = expandHome(cfg.identityFile);
  return Promise.all(cfg.servers.map((s) => probe(s, identity)));
}
