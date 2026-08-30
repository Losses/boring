export { BinaryReader, BinaryWriter } from "./codec.ts";
export type { BoundsEmRecord, GlyphMetricsRecord } from "./records.ts";
export type {
  AdvanceEmNotFiniteError,
  BoundsFieldsNotFiniteError,
  BoundsNotObjectError,
  CodePointNotIntegerError,
  DescriptionNotStringError,
  FileNotObjectError,
  JsonError,
  RecordsNotArrayError,
} from "./vector-json.ts";
export { JsonException, describeJsonError, toVectorFile } from "./vector-json.ts";
export type { VectorFileJson } from "./vector-json.ts";
export {
  RECORD_BYTE_LENGTH,
  VECTOR_MAGIC,
  VECTOR_MAGIC_F16,
  VECTOR_MAGIC_F32,
  decodeVector,
  encodeVector,
  magicOf,
  recordByteLength,
  vectorByteLength,
  widthOfMagic,
} from "./vector-format.ts";
export type { FloatWidth } from "./vector-format.ts";
export { f16ToF32Bits, f32ToF16Bits } from "./fp16.ts";
export type {
  BadMagicError,
  CountOverflowError,
  TrailingBytesError,
  UnexpectedEofError,
  VectorError,
} from "./vector-error.ts";
export { VectorException, describeError } from "./vector-error.ts";
export { vectorSortByCodePoint } from "./vector-sort.ts";
