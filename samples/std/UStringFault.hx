package std;

/**
 * Failure identity of std.UString construction checks, carried by
 * std.UStringException per docs/specs/features/06-errors-and-results.md.
 */
enum UStringFault {
	InvalidCodePoint(code:Int);
}
