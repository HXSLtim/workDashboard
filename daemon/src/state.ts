import { mkdir, writeFile, rename } from "node:fs/promises";
import { HUB_DIR, STATE_PATH } from "./config.ts";
import type { HubState } from "./types.ts";

// Atomic write: write to a temp file then rename, so the notch app never reads a
// half-written JSON.
export async function writeState(state: HubState): Promise<void> {
  await mkdir(HUB_DIR, { recursive: true });
  const tmp = `${STATE_PATH}.tmp`;
  await writeFile(tmp, JSON.stringify(state, null, 2), "utf8");
  await rename(tmp, STATE_PATH);
}
