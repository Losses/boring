import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

describe("string buffer generated tree", () => {
  const tsGenDir = path.resolve(__dirname, "../../reference/ts/gen");
  const kotlinGenDir = path.resolve(__dirname, "../../reference/kotlin/gen");
  const rustGenDir = path.resolve(__dirname, "../../reference/rust-gen/src");

  test("TS lowers StringBuf to primitive strings with inline pairing checks", () => {
    const tsFile = path.join(tsGenDir, "boring/StringBufOps.ts");
    expect(fs.existsSync(tsFile)).toBe(true);
    const content = fs.readFileSync(tsFile, "utf8");

    expect(content).not.toContain("new StringBuf");
    expect(content).not.toContain("std.StringBuf");
    expect(content).toContain('let buf = "";');
    expect(content).toContain("buf += a;");
    expect(content).toContain("buf += String.fromCharCode(codeA);");
    expect(content).toContain("return buf.length;");
    expect(content).toContain("buf.charCodeAt(buf.length - 1)");
    expect(content).toContain('throw new UStringException({ kind: "UnpairedSurrogate", unit: tail });');
  });

  test("Kotlin lowers StringBuf to StringBuilder with tail reads via lastOrNull", () => {
    const ktFile = path.join(kotlinGenDir, "boring/StringBufOps.kt");
    expect(fs.existsSync(ktFile)).toBe(true);
    const content = fs.readFileSync(ktFile, "utf8");

    expect(content).toContain("val buf = StringBuilder()");
    expect(content).toContain("buf.append(a)");
    expect(content).toContain("buf.append((codeA).toChar())");
    expect(content).toContain("return buf.length");
    expect(content).toContain("buf.lastOrNull()?.code ?: -1");
    expect(content).toContain("throw UStringException.UnpairedSurrogate(tail)");
  });

  test("Rust lowers StringBuf to Vec<u16> with fault arms bound in the pattern", () => {
    const rsFile = path.join(rustGenDir, "boring/string_buf_ops.rs");
    expect(fs.existsSync(rsFile)).toBe(true);
    const content = fs.readFileSync(rsFile, "utf8");

    expect(content).toContain("let mut buf = Vec::<u16>::new();");
    expect(content).toContain("buf.extend(a.encode_utf16());");
    expect(content).toContain("buf.push(u16::try_from((code_a) & 0xFFFF).unwrap_or(0));");
    expect(content).toContain("return Ok(u32::try_from((buf.len()) & 0xFFFF_FFFF).unwrap_or(0));");
    expect(content).toContain("String::from_utf16(buf.as_slice())");
    expect(content).toContain("UStringFault::UnpairedSurrogate { unit: u32::from(unit) }");
    expect(content).toContain("UStringFault::InvalidCodePoint { code } => u32::wrapping_add(1000, code),");
    expect(content).not.toContain("String::new()");
    expect(content).not.toContain("push_str");
    expect(content).not.toContain("encode_utf16().count()");
  });

  test("Swift lowers StringBuf to UTF-16 arrays", () => {
    const content = fs.readFileSync(
      path.join(path.resolve(__dirname, "../../reference/swift/gen"), "boring/StringBufOps.swift"),
      "utf8",
    );
    expect(content).toContain("var buf = [UInt16]()");
    expect(content).toContain("buf += Array(a.utf16)");
    expect(content).toContain("String(decoding: buf, as: UTF16.self)");
    expect(content).toContain("UStringFault.unpairedSurrogate");
  });

  test("Dart lowers StringBuf to UTF-16 unit lists", () => {
    const content = fs.readFileSync(
      path.join(path.resolve(__dirname, "../../reference/dart/gen/lib"), "boring/string_buf_ops.dart"),
      "utf8",
    );
    expect(content).toContain("var buf = <int>[]");
    expect(content).toContain("buf.addAll(a.codeUnits)");
    expect(content).toContain("String.fromCharCodes(buf)");
    expect(content).toContain("UStringFaultUnpairedSurrogate");
    expect(content).toContain("return String.fromCharCodes(buf);");
  });
});
