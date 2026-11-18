// Process execution with bounded output capture and a timeout.

import type { ProcessResult, RunOptions, StreamKeep } from "./types.ts";

export type ByteWindow = {
  chunks: Buffer[];
  total: number;
  limit: number;
  keep: StreamKeep;
  truncated: boolean;
};

export function createWindow(limit: number, keep: StreamKeep): ByteWindow {
  return { chunks: [], total: 0, limit, keep, truncated: false };
}

export function appendWindow(window: ByteWindow, chunk: Buffer): void {
  if (chunk.length === 0) return;
  if (window.keep === "tail") {
    window.chunks.push(chunk);
    window.total += chunk.length;
    while (window.total > window.limit && window.chunks.length > 0) {
      const first = window.chunks[0];
      if (first === undefined) break;
      const overflow = window.total - window.limit;
      if (first.length <= overflow) {
        window.chunks.shift();
        window.total -= first.length;
      } else {
        window.chunks[0] = first.subarray(overflow);
        window.total -= overflow;
      }
      window.truncated = true;
    }
    return;
  }
  if (window.total >= window.limit) {
    window.truncated = true;
    return;
  }
  const room = window.limit - window.total;
  const part = chunk.length <= room ? chunk : chunk.subarray(0, room);
  window.chunks.push(part);
  window.total += part.length;
  if (part.length < chunk.length) window.truncated = true;
}

export function windowBytes(window: ByteWindow): Buffer {
  return Buffer.concat(window.chunks);
}

async function readStream(stream: ReadableStream<Uint8Array> | null, window: ByteWindow): Promise<void> {
  if (stream === null) return;
  const reader = stream.getReader();
  for (;;) {
    const read = await reader.read();
    if (read.done) break;
    if (read.value !== undefined) appendWindow(window, Buffer.from(read.value));
  }
  reader.releaseLock();
}

export function buildEnvironment(overrides?: Record<string, string>): Record<string, string> {
  const env: Record<string, string> = {};
  for (const key of Object.keys(process.env)) {
    const value = process.env[key];
    if (value !== undefined) env[key] = value;
  }
  if (overrides !== undefined) {
    for (const key of Object.keys(overrides)) {
      const value = overrides[key];
      if (value !== undefined) env[key] = value;
    }
  }
  return env;
}

export async function runProcess(command: string[], options: RunOptions = {}): Promise<ProcessResult> {
  const started = performance.now();
  const child = Bun.spawn(command, {
    cwd: options.cwd,
    env: buildEnvironment(options.env),
    stdin: options.stdin === undefined ? "ignore" : "pipe",
    stdout: "pipe",
    stderr: "pipe",
  });
  const stdin = child.stdin;
  if (options.stdin !== undefined && stdin !== undefined && stdin !== null) {
    stdin.write(options.stdin);
    await stdin.end();
  }
  const maxBytes = options.maxBytes ?? 1024 * 1024;
  const keep = options.keep ?? "head";
  const stdoutWindow = createWindow(maxBytes, keep);
  const stderrWindow = createWindow(maxBytes, "tail");
  const stdoutRead = readStream(child.stdout, stdoutWindow);
  const stderrRead = readStream(child.stderr, stderrWindow);
  let timedOut = false;
  const timeoutMs = options.timeoutMs ?? 0;
  const timer = timeoutMs > 0
    ? setTimeout(() => {
      timedOut = true;
      try {
        child.kill("SIGKILL");
      } catch {
        // The process may have exited between the timer and the signal.
      }
    }, timeoutMs)
    : null;
  const code = await child.exited;
  if (timer !== null) clearTimeout(timer);
  await Promise.all([stdoutRead, stderrRead]);
  const stdoutBuffer = windowBytes(stdoutWindow);
  const stderrBuffer = windowBytes(stderrWindow);
  const binary = options.binary === true;
  return {
    code,
    signal: child.signalCode ?? null,
    timedOut,
    durationMs: performance.now() - started,
    stdout: binary ? "" : stdoutBuffer.toString("utf8"),
    stderr: stderrBuffer.toString("utf8"),
    stdoutBytes: binary ? stdoutBuffer : null,
    truncated: stdoutWindow.truncated || stderrWindow.truncated,
  };
}

export function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

export function tailText(text: string, lines: number, maxChars: number): string {
  const clean = text.split("\u0000").join("");
  const split = clean.split("\n");
  const from = Math.max(0, split.length - lines);
  const joined = split.slice(from).join("\n");
  if (joined.length <= maxChars) return joined;
  return joined.slice(joined.length - maxChars);
}
