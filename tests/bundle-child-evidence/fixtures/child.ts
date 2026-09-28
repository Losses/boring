// Controlled child of the focused child-evidence suite.
//
// One mode per invocation; every mode writes through the raw descriptor so
// the bytes the parent retains are the bytes this process produced, with no
// text encoding step on either side.
import { writeSync } from "node:fs";

/** Writes the whole buffer to one descriptor; a short pipe write is retried. */
function writeAll(fd: number, buffer: Buffer): void {
  let written = 0;
  while (written < buffer.length) {
    written += writeSync(fd, buffer, written, buffer.length - written);
  }
}

function text(value: string): Buffer {
  return Buffer.from(value, "utf8");
}

const mode = process.argv[2] ?? "";

if (mode === "markers") {
  writeAll(1, text("stdout marker line\n"));
  writeAll(2, text("Warning : a warning shaped line on standard error\n"));
} else if (mode === "fail") {
  writeAll(1, text("failing child stdout\n"));
  writeAll(2, text("failing child stderr\n"));
  process.exit(7);
} else if (mode === "signal") {
  writeAll(1, text("signaled child stdout\n"));
  process.kill(process.pid, "SIGKILL");
} else if (mode === "bytes") {
  // 0x41 0xC3 0xA9 is the UTF-8 spelling of one accented letter; 0xFF 0xFE
  // and the 0x80 continuation byte are not valid UTF-8 on their own.
  const bytes = Buffer.from([
    0x41, 0xc3, 0xa9, 0x0a, 0xff, 0xfe, 0x0a, 0x80, 0x0a, 0xe2, 0x82, 0xac, 0x0a,
  ]);
  writeAll(1, bytes);
  writeAll(2, Buffer.concat([bytes, bytes]));
} else if (mode === "echo") {
  const observed = process.argv[3] ?? "";
  writeAll(
    1,
    text(
      JSON.stringify({
        argv: process.argv.slice(2),
        cwd: process.cwd(),
        observedValue: observed.length === 0 ? null : process.env[observed] ?? null,
      }) + "\n",
    ),
  );
} else if (mode === "flood") {
  const total = Number(process.argv[3] ?? "0");
  const chunk = Buffer.alloc(4096, 0x78);
  let remaining = total;
  while (remaining > 0) {
    const size = Math.min(chunk.length, remaining);
    writeAll(1, chunk.subarray(0, size));
    writeAll(2, chunk.subarray(0, size));
    remaining -= size;
  }
} else {
  writeAll(2, text(`unknown child mode ${mode}\n`));
  process.exit(64);
}
