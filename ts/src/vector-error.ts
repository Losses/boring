/**
 * Failure identity of the vector codec, shared by every language tree as
 * ruled in docs/specs/features/06-errors-and-results.md. The variant set
 * matches the Rust `VectorError` enum, the Haxe `VectorError` enum, and the
 * Kotlin sealed `VectorException` one to one. Messages are display text
 * derived from the variant; no consumer reads them back.
 */

export interface BadMagicError {
  readonly kind: "BadMagic";
}

export interface CountOverflowError {
  readonly kind: "CountOverflow";
}

export interface UnexpectedEofError {
  readonly kind: "UnexpectedEof";
}

export interface TrailingBytesError {
  readonly kind: "TrailingBytes";
  readonly remaining: number;
}

export type VectorError =
  | BadMagicError
  | CountOverflowError
  | UnexpectedEofError
  | TrailingBytesError;

export function describeError(error: VectorError): string {
  switch (error.kind) {
    case "BadMagic":
      return "bad vector magic";
    case "CountOverflow":
      return "record count exceeds u32";
    case "UnexpectedEof":
      return "vector ended mid-record";
    case "TrailingBytes":
      return `trailing bytes in vector: ${error.remaining}`;
  }
}

/** The only exception shape vector codec code throws. */
export class VectorException extends Error {
  readonly error: VectorError;

  constructor(error: VectorError) {
    super(describeError(error));
    this.name = "VectorException";
    this.error = error;
  }
}
