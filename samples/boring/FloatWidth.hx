/**
 * Block float width of the vector wire format (binary spec 05). The width is
 * a property of the encoded block, declared by its magic, and stays
 * independent of the module real width that feature spec 23 selects at
 * compile time.
 */
package boring;

enum FloatWidth {
	F64;
	F32;
	F16;
}
