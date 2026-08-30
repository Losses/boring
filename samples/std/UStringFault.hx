package std;

/**
 * Failure identity of std.UString construction checks and std.StringBuf
 * pairing checks, carried by std.UStringException per
 * docs/specs/features/06-errors-and-results.md; both variants name an
 * ill-formed Unicode value crossing the string subsystem.
 */
enum UStringFault {
	InvalidCodePoint(code:Int);
	UnpairedSurrogate(unit:Int);
}
