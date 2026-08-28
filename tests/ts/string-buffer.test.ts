import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

describe("string buffer generated tree", () => {
  const tsGenDir = path.resolve(__dirname, "../../reference/ts/gen");
  const kotlinGenDir = path.resolve(__dirname, "../../reference/kotlin/gen");
  const rustGenDir = path.resolve(__dirname, "../../reference/rust-gen/src");

  test("TS lowers StringBuf to primitive strings, += operator, and String.fromCharCode", () => {
    const tsFile = path.join(tsGenDir, "boring/StringBufOps.ts");
    expect(fs.existsSync(tsFile)).toBe(true);
    const content = fs.readFileSync(tsFile, "utf8");

    expect(content).not.toContain("new StringBuf");
    expect(content).not.toContain("std.StringBuf");
    expect(content).toContain('let buf = "";');
    expect(content).toContain("buf += a;");
    expect(content).toContain("buf += String.fromCharCode(codeA);");
    expect(content).toContain("return buf.length;");
  });

  test("Kotlin lowers StringBuf to StringBuilder and append methods", () => {
    const ktFile = path.join(kotlinGenDir, "boring/StringBufOps.kt");
    expect(fs.existsSync(ktFile)).toBe(true);
    const content = fs.readFileSync(ktFile, "utf8");

    expect(content).toContain("val buf = StringBuilder()");
    expect(content).toContain("buf.append(a)");
    expect(content).toContain("buf.append((codeA).toChar())");
    expect(content).toContain("return buf.length");
    expect(content).toContain("return buf.toString()");
  });

  test("Rust lowers StringBuf to String, push_str, push(char), and encode_utf16 count", () => {
    const rsFile = path.join(rustGenDir, "boring/string_buf_ops.rs");
    expect(fs.existsSync(rsFile)).toBe(true);
    const content = fs.readFileSync(rsFile, "utf8");

    expect(content).toContain("let mut buf = String::new();");
    expect(content).toContain("buf.push_str(&a);");
    expect(content).toContain("buf.push(char::from_u32(code_a).unwrap_or(char::REPLACEMENT_CHARACTER));");
    expect(content).toContain("return buf.encode_utf16().count() as u32;");
    expect(content).toContain("return buf.clone();");
  });
});
