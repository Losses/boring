package atb;

import std.ReadOnlyArray;

/**
    Authored holder record for the nullable container field shape (a).
    `values` is a `Null<Array<Int>>` field: the container identity crosses
    the nullable field boundary. The field is written nullable so the
    observation is about the nullable slot, not about the ordinary
    `Array -> ReadOnlyArray` conversion (which the readonly-alias fixture
    covers on the same five targets).
**/
class NullableHolder {
	public var values:Null<Array<Int>>;

	public function new(values:Null<Array<Int>>) {
		this.values = values;
	}
}
