import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

const root = path.resolve(__dirname, "../..");

function read(relativePath: string): string {
  return fs.readFileSync(path.join(root, relativePath), "utf8");
}

describe("top-level and extension function lowering", () => {
  test("TypeScript extracts file functions and keeps the receiver first", () => {
    const fileLevel = read("reference/ts/gen/boring/FileLevelOps.ts");
    const fileConsumer = read("reference/ts/gen/boring/FileLevelConsumer.ts");
    const extensions = read("reference/ts/gen/boring/ExtensionOps.ts");
    const extensionConsumer = read("reference/ts/gen/boring/ExtensionConsumer.ts");

    expect(fileLevel).toContain("export function publicValue(value: number): number");
    expect(fileLevel).toContain("function privateValue(value: number): number");
    expect(fileLevel).not.toContain("class FileLevelOps");
    expect(fileLevel).toContain("return privateValue(value);");
    expect(fileConsumer).toContain("import { publicValue, publicWithPrivate } from \"./FileLevelOps.ts\";");
    expect(fileConsumer).toContain("return publicValue(7);");
    expect(fileConsumer).not.toMatch(/\bFileLevelOps\.(?:publicValue|publicWithPrivate)\(/u);

    expect(extensions).toContain("export function modeLabel(mode: ExtensionMode, suffix: string): string");
    expect(extensions).toContain("export function stringLabel(value: string, prefix: string): string");
    expect(extensions).toContain("function privateModeLabel(mode: ExtensionMode): string");
    expect(extensions).not.toContain("class ExtensionOps");
    expect(extensionConsumer).toContain("return modeLabel(ExtensionMode.Hot, \"!\");");
    expect(extensionConsumer).toContain("return stringLabel(\"core\", \"@\");");
    expect(extensionConsumer).not.toMatch(/\bExtensionOps\.(?:modeLabel|stringLabel|modeWithPrivate)\(/u);
  });

  test("Kotlin emits file-facade functions and receiver extensions", () => {
    const fileLevel = read("reference/kotlin/gen/boring/FileLevelOps.kt");
    const fileConsumer = read("reference/kotlin/gen/boring/FileLevelConsumer.kt");
    const extensions = read("reference/kotlin/gen/boring/ExtensionOps.kt");
    const extensionConsumer = read("reference/kotlin/gen/boring/ExtensionConsumer.kt");

    expect(fileLevel).toContain("fun publicValue(value: Int): Int");
    expect(fileLevel).toContain("private fun privateValue(value: Int): Int");
    expect(fileLevel).not.toContain("object FileLevelOps");
    expect(fileConsumer).toContain("return publicValue(7)");
    expect(fileConsumer).not.toContain("FileLevelOps.");

    expect(extensions).toContain("fun ExtensionMode.modeLabel(suffix: String): String");
    expect(extensions).toContain("fun String.stringLabel(prefix: String): String");
    expect(extensions).toContain("private fun ExtensionMode.privateModeLabel(): String");
    expect(extensions).not.toContain("object ExtensionOps");
    expect(extensionConsumer).toContain("return ExtensionMode.Hot.modeLabel(\"!\")");
    expect(extensionConsumer).toContain("return \"core\".stringLabel(\"@\")");
    expect(extensionConsumer).not.toContain("ExtensionOps.");
  });

  test("Swift emits a file function and native extension blocks", () => {
    const fileLevel = read("reference/swift/gen/boring/FileLevelOps.swift");
    const fileConsumer = read("reference/swift/gen/boring/FileLevelConsumer.swift");
    const extensions = read("reference/swift/gen/boring/ExtensionOps.swift");
    const extensionConsumer = read("reference/swift/gen/boring/ExtensionConsumer.swift");

    expect(fileLevel).toContain("func publicValue(_ value: Int32) -> Int32");
    expect(fileLevel).toContain("private func privateValue(_ value: Int32) -> Int32");
    expect(fileLevel).not.toContain("enum FileLevelOps");
    expect(fileConsumer).toContain("return publicValue(7)");
    expect(fileConsumer).not.toContain("FileLevelOps.");

    expect(extensions).toContain("extension ExtensionMode {");
    expect(extensions).toContain("extension String {");
    expect(extensions).toContain("func modeLabel(_ suffix: String) -> String");
    expect(extensions).toContain("func stringLabel(_ prefix: String) -> String");
    expect(extensions).not.toContain("enum ExtensionOps");
    expect(extensionConsumer).toContain("return ExtensionMode.hot.modeLabel(\"!\")");
    expect(extensionConsumer).toContain("return \"core\".stringLabel(\"@\")");
    expect(extensionConsumer).not.toContain("ExtensionOps.");
  });

  test("Dart emits an unnamed extension and library top-level functions", () => {
    const fileLevel = read("reference/dart/gen/lib/boring/file_level_ops.dart");
    const fileConsumer = read("reference/dart/gen/lib/boring/file_level_consumer.dart");
    const extensions = read("reference/dart/gen/lib/boring/extension_ops.dart");
    const extensionConsumer = read("reference/dart/gen/lib/boring/extension_consumer.dart");

    expect(fileLevel).toContain("int publicValue(int value)");
    expect(fileLevel).toContain("int _privateValue(int value)");
    expect(fileLevel).not.toContain("class FileLevelOps");
    expect(fileConsumer).toContain("return file_level_ops.publicValue(7);");
    expect(fileConsumer).not.toContain("FileLevelOps.");

    expect(extensions).toContain("extension ExtensionModeExtension on ExtensionMode {");
    expect(extensions).toContain("extension StringExtension on String {");
    expect(extensions).toContain("String modeLabel(String suffix)");
    expect(extensions).toContain("String stringLabel(String prefix)");
    expect(extensions).not.toContain("class ExtensionOps");
    expect(extensionConsumer).toContain("import 'extension_ops.dart';");
    expect(extensionConsumer).toContain("return extension_ops.ExtensionMode.hot.modeLabel(\"!\");");
    expect(extensionConsumer).toContain("return \"core\".stringLabel(\"@\");");
    expect(extensionConsumer).not.toContain("ExtensionOps.");
  });

  test("Rust uses an inherent impl only for the owned receiver", () => {
    const fileLevel = read("reference/rust-gen/src/boring/file_level_ops.rs");
    const fileConsumer = read("reference/rust-gen/src/boring/file_level_consumer.rs");
    const extensions = read("reference/rust-gen/src/boring/extension_ops.rs");
    const extensionConsumer = read("reference/rust-gen/src/boring/extension_consumer.rs");

    expect(fileLevel).toContain("pub fn public_value(value: u32) -> u32");
    expect(fileLevel).toContain("fn private_value(value: u32) -> u32");
    expect(fileLevel).not.toContain("struct FileLevelOps");
    expect(fileConsumer).toContain("return public_value(7);");
    expect(fileConsumer).not.toContain("FileLevelOps::");

    expect(extensions).toContain("impl ExtensionMode {");
    expect(extensions).toContain("pub fn mode_label(&self, suffix: &str) -> String");
    expect(extensions).toContain("pub fn string_label(value: &str, prefix: &str) -> String");
    expect(extensions).not.toContain("struct ExtensionOps");
    expect(extensionConsumer).toContain("return ExtensionMode::Hot.mode_label(&\"!\");");
    expect(extensionConsumer).toContain("return string_label(&\"core\", &\"@\");");
    expect(extensionConsumer).not.toContain("ExtensionOps::");
  });
});
