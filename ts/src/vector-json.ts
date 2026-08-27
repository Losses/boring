/**
 * Runtime validation for tests/vectors/roundtrip.json. JSON arrives as unknown at
 * the boundary; these guards narrow it to the named record types without
 * casts, so no `any` and no assertion escapes into the package.
 *
 * Failure identity follows docs/specs/features/06-errors-and-results.md: a
 * closed variant set carried by one exception class. This validation domain
 * exists only in the TypeScript tree, so the variant set has no counterpart
 * to keep aligned in the other trees.
 */

import { BoundsEmRecord, GlyphMetricsRecord } from "./records.ts";

export interface BoundsNotObjectError {
  readonly kind: "BoundsNotObject";
}

export interface BoundsFieldsNotFiniteError {
  readonly kind: "BoundsFieldsNotFinite";
}

export interface RecordNotObjectError {
  readonly kind: "RecordNotObject";
}

export interface CodePointNotIntegerError {
  readonly kind: "CodePointNotInteger";
}

export interface AdvanceEmNotFiniteError {
  readonly kind: "AdvanceEmNotFinite";
}

export interface FileNotObjectError {
  readonly kind: "FileNotObject";
}

export interface DescriptionNotStringError {
  readonly kind: "DescriptionNotString";
}

export interface RecordsNotArrayError {
  readonly kind: "RecordsNotArray";
}

export type JsonError =
  | BoundsNotObjectError
  | BoundsFieldsNotFiniteError
  | RecordNotObjectError
  | CodePointNotIntegerError
  | AdvanceEmNotFiniteError
  | FileNotObjectError
  | DescriptionNotStringError
  | RecordsNotArrayError;

export function describeJsonError(error: JsonError): string {
  switch (error.kind) {
    case "BoundsNotObject":
      return "bounds must be an object";
    case "BoundsFieldsNotFinite":
      return "bounds fields must be finite numbers";
    case "RecordNotObject":
      return "record must be an object";
    case "CodePointNotInteger":
      return "codePoint must be an integer";
    case "AdvanceEmNotFinite":
      return "advanceEm must be a finite number";
    case "FileNotObject":
      return "vector file must be an object";
    case "DescriptionNotString":
      return "description must be a string";
    case "RecordsNotArray":
      return "records must be an array";
  }
}

/** The only exception shape JSON validation throws. */
export class JsonException extends Error {
  readonly error: JsonError;

  constructor(error: JsonError) {
    super(describeJsonError(error));
    this.name = "JsonException";
    this.error = error;
  }
}

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
    throw new JsonException({ kind: "BoundsNotObject" });
  }
  const xMin = value["xMin"];
  const yMin = value["yMin"];
  const xMax = value["xMax"];
  const yMax = value["yMax"];
  if (!isFiniteNumber(xMin) || !isFiniteNumber(yMin) || !isFiniteNumber(xMax) || !isFiniteNumber(yMax)) {
    throw new JsonException({ kind: "BoundsFieldsNotFinite" });
  }
  return { xMin, yMin, xMax, yMax };
}

export function toGlyphMetricsRecord(value: unknown): GlyphMetricsRecord {
  if (!isRecord(value)) {
    throw new JsonException({ kind: "RecordNotObject" });
  }
  const codePoint = value["codePoint"];
  const advanceEm = value["advanceEm"];
  const bounds = value["bounds"];
  if (typeof codePoint !== "number" || !Number.isInteger(codePoint)) {
    throw new JsonException({ kind: "CodePointNotInteger" });
  }
  if (!isFiniteNumber(advanceEm)) {
    throw new JsonException({ kind: "AdvanceEmNotFinite" });
  }
  return { codePoint, advanceEm, bounds: toBoundsEm(bounds) };
}

export function toVectorFile(value: unknown): VectorFileJson {
  if (!isRecord(value)) {
    throw new JsonException({ kind: "FileNotObject" });
  }
  const description = value["description"];
  const records = value["records"];
  if (typeof description !== "string") {
    throw new JsonException({ kind: "DescriptionNotString" });
  }
  if (!Array.isArray(records)) {
    throw new JsonException({ kind: "RecordsNotArray" });
  }
  const count = records.length;
  const parsed: GlyphMetricsRecord[] = new Array<GlyphMetricsRecord>(count);
  for (let i = 0; i < count; i += 1) {
    parsed[i] = toGlyphMetricsRecord(records[i]!);
  }
  return { description, records: parsed };
}
