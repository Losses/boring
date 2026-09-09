package boring;

import runtime.SortedTable;

/**
    Reproduces a direct module-path import of a resident runtime module.
    Business code that names a resident module (runtime.SortedTable)
    directly imports it as a sibling module, so the target must emit the
    place it in the runtime directory under its module path
    into the single runtime entry (docs/specs/features/14).
**/
class ResidentModuleImportOps {
	#if ts_output
	/** A round-trip map lookup through the directly imported resident. */
	public static function mapLookup():Null<Int> {
		final builder:SortedMapTableBuilder<Int, Int> = SortedTable.mapBuilder(SortedTable.compareInts);
		builder.put(7, 100);
		return builder.build().get(7);
	}
	#else
	/** Non-TypeScript targets keep the resident off the module path. */
	public static function mapLookup():Null<Int> {
		return null;
	}
	#end
}