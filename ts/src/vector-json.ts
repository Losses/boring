/**
 * Runtime validation for tests/vectors/roundtrip.json. JSON arrives as unknown at
 * the boundary; these guards narrow it to the named record types without
 * casts, so no `any` and no assertion escapes into the package.
 */

import { BoundsEmRecord, GlyphMetricsRecord } from "./records.ts";

export interface VectorFileJson {
  readonly description: string;
  readonly records: GlyphMetricsRecord[];
}

function isFiniteNumber(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function toBoundsEm(value: unknown): BoundsEmRecord {
  if (!isRecord(value)) {
    throw new Error("bounds must be an object");
  }
  const xMin = value["xMin"];
  const yMin = value["yMin"];
  const xMax = value["xMax"];
  const yMax = value["yMax"];
  if (!isFiniteNumber(xMin) || !isFiniteNumber(yMin) || !isFiniteNumber(xMax) || !isFiniteNumber(yMax)) {
    throw new Error("bounds fields must be finite numbers");
  }
  return { xMin, yMin, xMax, yMax };
}

export function toGlyphMetricsRecord(value: unknown): GlyphMetricsRecord {
  if (!isRecord(value)) {
    throw new Error("record must be an object");
  }
  const codePoint = value["codePoint"];
  const advanceEm = value["advanceEm"];
  const bounds = value["bounds"];
  if (typeof codePoint !== "number" || !Number.isInteger(codePoint)) {
    throw new Error("codePoint must be an integer");
  }
  if (!isFiniteNumber(advanceEm)) {
    throw new Error("advanceEm must be a finite number");
  }
  return { codePoint, advanceEm, bounds: toBoundsEm(bounds) };
}

export function toVectorFile(value: unknown): VectorFileJson {
  if (!isRecord(value)) {
    throw new Error("vector file must be an object");
  }
  const description = value["description"];
  const records = value["records"];
  if (typeof description !== "string") {
    throw new Error("description must be a string");
  }
  if (!Array.isArray(records)) {
    throw new Error("records must be an array");
  }
  return { description, records: records.map(toGlyphMetricsRecord) };
}
