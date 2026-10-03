#!/usr/bin/env node
// trace-emit-origin.mjs — one-command trace for emit-origin sidecar files
// Usage: node trace-emit-origin.mjs <sidecar.json> <line> [column]
//        node trace-emit-origin.mjs <sidecar.json> summary

import fs from 'fs';

function main() {
  const args = process.argv.slice(2);
  if (args.length < 2) {
    console.error('Usage: node trace-emit-origin.mjs <sidecar.json> <line> [column]');
    console.error('       node trace-emit-origin.mjs <sidecar.json> summary');
    process.exit(1);
  }

  const sidecarPath = args[0];
  const data = JSON.parse(fs.readFileSync(sidecarPath, 'utf8'));

  if (args[1] === 'summary') {
    printSummary(data);
    return;
  }

  const line = parseInt(args[1], 10);
  const column = args.length >= 3 ? parseInt(args[2], 10) : 1;
  printTrace(data, line, column);
}

function printSummary(data) {
  const v = data.v || 1;
  const totalLines = (data.lines || []).length;
  const mappedLines = data.lines.filter(l => l !== null && !(typeof l === "object" && l.u !== undefined)).length;
  const exactLines = data.lines.filter(l => Array.isArray(l) && (l.length < 8 ? true : l[7] === "exact")).length;
  const inheritedLines = data.lines.filter(l => Array.isArray(l) && l.length >= 8 && l[7] === "inherited").length;
  const nullLines = totalLines - mappedLines;
  const callStackFrames = (data.callStackFrames || []).length;
  console.log(`Sidecar: ${data.revision || '?'}  Haxe ${data.haxeVersion || '?'}`);
  console.log(`Format: v${v}  Source files: ${(data.sourceFiles || []).length}  Frames: ${(data.frames || []).length}`);
  console.log(`Call-stack frame table: ${callStackFrames} entries`);
  console.log(`Lines: ${mappedLines} mapped of ${totalLines} total (${totalLines > 0 ? (mappedLines/totalLines*100).toFixed(1) : 0}%)`);
  console.log(`  exact: ${exactLines}  inherited: ${inheritedLines}  null: ${nullLines}`);
  if (data.sourceFiles) {
    console.log(`
Source files:`);
    data.sourceFiles.forEach(f => console.log(`  ${f}`));
  }
  if (data.frames) {
    console.log(`
Emission frames (branches):`);
    data.frames.forEach((f, i) => console.log(`  [${i}] ${f}`));
  }
}

function printTrace(data, line, column) {
  const lines = data.lines || [];
  if (line < 1 || line > lines.length) {
    console.log(`Unmapped: line ${line} out of bounds (max ${lines.length})`);
    process.exit(0);
  }

  const entry = lines[line - 1];
  if (entry === null) {
    console.log(`Unmapped: no mapping for line ${line}`);
    process.exit(0);
  }
  if (typeof entry === "object" && !Array.isArray(entry)) {
    console.log(`Unmapped: no mapping for line ${line} (${entry.u || "no source"})`);
    process.exit(0);
  }

  const frameId = entry[0];
  const frame = data.frames && frameId < data.frames.length ? data.frames[frameId] : '<unknown>';

  const origin = Array.isArray(entry) && entry.length >= 8 ? entry[7] : "exact";
  const inheritedFrom = origin === "inherited" && entry.length >= 9 && entry[8] >= 0 ? entry[8] : -1;
  const suffix = inheritedFrom >= 0 ? ` (from line ${inheritedFrom + 1})` : "";
  console.log(`line ${line} (col ${column}) [${origin}] -> frame=${frame}${suffix}`);

  if (entry.length >= 5) {
    const sourceFileId = entry[1];
    const sourceStart = entry[2];
    const sourceEnd = entry[3];
    const sourceLine = entry.length >= 6 ? entry[4] : 0;
    const sourceColumn = entry.length >= 7 ? entry[5] : 0;
    const callStackIds = entry.length >= 7 ? entry[6] : [];

    if (sourceFileId >= 0 && data.sourceFiles && sourceFileId < data.sourceFiles.length) {
      console.log(`  Haxe source: ${data.sourceFiles[sourceFileId]}:${sourceLine}:${sourceColumn}`);
      console.log(`  Byte span: ${sourceStart}-${sourceEnd}`);
    } else {
      console.log(`  Haxe source: <no source position recorded>`);
    }

    console.log(`  Call stack (${callStackIds.length} frames, innermost first):`);
    if (callStackIds.length === 0 || !data.callStackFrames) {
      console.log(`    <no call stack recorded>`);
    } else {
      let depth = 0;
      for (const fid of callStackIds) {
        if (depth >= 16) {
          console.log(`    ... (${callStackIds.length - depth} more)`);
          break;
        }
        if (fid >= 0 && fid < data.callStackFrames.length) {
          const fr = data.callStackFrames[fid];
          const loc = fr.file ? `${fr.file}:${fr.line}:${fr.column}` : '<n/a>';
          console.log(`    #${depth} ${fr.name}  at ${loc}`);
        } else {
          console.log(`    #${depth} <invalid frame id ${fid}>`);
        }
        depth++;
      }
    }
  } else {
    console.log(`  Haxe source: <no source position recorded>`);
  }
}

main();
