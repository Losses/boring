/**
 * Failure identity of the value record sample, following the exception
 * shape of docs/specs/features/06-errors-and-results.md: the variant set
 * is the failure identity shared by every language tree, and the message
 * is display text derived from the variant.
 */
package boring;

enum ValueError {
	StartAfterEnd;
	NegativeStart;
}
