/**
 * Named record types for the shared cross-language vector format.
 * Every type in this package is named: inline object, function, mapped,
 * and tuple types are banned repo-wide (see AGENT.md).
 */

export interface BoundsEmRecord {
  readonly xMin: number;
  readonly yMin: number;
  readonly xMax: number;
  readonly yMax: number;
}

export interface GlyphMetricsRecord {
  readonly codePoint: number;
  readonly advanceEm: number;
  readonly bounds: BoundsEmRecord;
}
