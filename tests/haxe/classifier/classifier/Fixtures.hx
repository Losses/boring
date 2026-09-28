package classifier;

import altpack.ReadOnlyArray;
import altpackalias.ReadOnlyArray;
import std.ReadOnlyArray;

/**
 * Fixture declarations the probe reads through the typer. The static
 * fields are the declaration forms the static field paths consume and the
 * instance fields are the forms the comparator classification consumes.
 * Each field holds one declared container form, so the observed types come
 * from source typing.
 */
class Fixtures {
	public static final plainArray:Array<Int> = [1, 2];
	public static final readOnly:ReadOnlyArray<Int> = [1, 2];
	public static final nullableReadOnly:Null<ReadOnlyArray<Int>> = null;
	public static final nullablePlain:Null<Array<Int>> = null;
	public static final elementNullable:ReadOnlyArray<Null<Int>> = [1, null];
	public static final aliasReadOnly:RO<Int> = [1, 2];
	public static final userNamed:altpack.ReadOnlyArray<Int> = [1, 2];
	public static final aliasNamed:altpackalias.ReadOnlyArray<Int> = [1, 2];
	public static final nullableUserNamed:Null<altpack.ReadOnlyArray<Int>> = null;
	public static final emptyReadOnly:ReadOnlyArray<Int> = [];

	public var instPlainArray:Array<Int> = [1, 2];
	public var instReadOnly:ReadOnlyArray<Int> = [1, 2];
	public var instNullableReadOnly:Null<ReadOnlyArray<Int>> = null;
	public var instElementNullable:ReadOnlyArray<Null<Int>> = [1, null];
	public var instAliasReadOnly:RO<Int> = [1, 2];
	public var instUserNamed:altpack.ReadOnlyArray<Int> = [1, 2];
	public var instAliasNamed:altpackalias.ReadOnlyArray<Int> = [1, 2];
	public var instNullableUserNamed:Null<altpack.ReadOnlyArray<Int>> = null;

	public function new() {}
}
