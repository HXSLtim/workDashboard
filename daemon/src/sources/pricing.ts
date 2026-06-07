// Best-effort USD-per-token estimates. Subscription usage isn't billed, so these
// are only for an approximate "equivalent cost" display. USD per 1M tokens.
interface Rate {
  input: number;
  output: number;
  cacheRead: number;
  cacheWrite: number;
}

const RATES: { match: RegExp; rate: Rate }[] = [
  { match: /opus/i, rate: { input: 5, output: 25, cacheRead: 0.5, cacheWrite: 6.25 } },
  { match: /sonnet/i, rate: { input: 3, output: 15, cacheRead: 0.3, cacheWrite: 3.75 } },
  { match: /haiku/i, rate: { input: 1, output: 5, cacheRead: 0.1, cacheWrite: 1.25 } },
  { match: /gpt-5|codex|o[34]/i, rate: { input: 1.25, output: 10, cacheRead: 0.125, cacheWrite: 1.25 } },
];

function rateFor(model: string): Rate | null {
  return RATES.find((r) => r.match.test(model))?.rate ?? null;
}

export function estimateCost(
  model: string,
  parts: { input?: number; output?: number; cacheRead?: number; cacheWrite?: number },
): number {
  const r = rateFor(model);
  if (!r) return 0;
  const M = 1_000_000;
  return (
    ((parts.input ?? 0) * r.input +
      (parts.output ?? 0) * r.output +
      (parts.cacheRead ?? 0) * r.cacheRead +
      (parts.cacheWrite ?? 0) * r.cacheWrite) /
    M
  );
}
