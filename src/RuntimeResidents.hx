#if (macro || reflaxe_runtime)

/**
 * Haxe modules that compile into every target's runtime package.
 * A resident module
 * lives under src/ so the published haxelib carries it, compiles through
 * the normal typed pipeline of each lane, and lands in the runtime-emit
 * directory instead of the business tree. The lanes reference these
 * modules through the import tables whether or not they emit them.
 *
 * The Rust lane renders haxe Int as u32 in business modules; resident
 * modules render Int as i32 because the runtime contracts carry signed
 * values (negative slice bounds, the -1 no-previous sentinel). Call
 * boundaries between the two conventions cast explicitly.
 *
 * Test residents emit beside the test host entry of each target instead
 * of the general runtime package (P6): their emission still gates on the
 * std.Test shim, so the host entry and the residents appear together.
 */
class RuntimeResidents {
	/** Resident modules of the general runtime, in emission order. */
	public static final MODULES: Array<String> = [
		"runtime.UString",
		"runtime.GraphemeWalk",
		"runtime.Graphemes",
		"runtime.SortedTable",
	];

	/** Resident modules of the test runtime, in emission order. */
	public static final TEST_MODULES: Array<String> = [
		"runtime.TestCore",
	];

	/** Whether a module compiles into the runtime package. */
	public static function isResident(module: String): Bool {
		return MODULES.indexOf(module) >= 0 || TEST_MODULES.indexOf(module) >= 0;
	}

	/** Whether a module compiles into the test runtime package. */
	public static function isTestResident(module: String): Bool {
		return TEST_MODULES.indexOf(module) >= 0;
	}

	/**
	 * The business externs that front one resident module. Business code
	 * never names the resident module; it calls the externs, and the lanes
	 * route the calls into the compiled runtime module. Modules that no
	 * extern names directly still report the extern of their set: the
	 * walk ships with the cluster tier that references it. One resident
	 * set can serve several externs: the sorted tables back the map and
	 * set faces together with their builder externs.
	 */
	public static function externsOf(module: String): Array<String> {
		return switch(module) {
			case "runtime.UString": ["std.UStringRT"];
			case "runtime.Graphemes" | "runtime.GraphemeWalk": ["std.Graphemes"];
			case "runtime.SortedTable": ["std.SortedMap", "std.SortedMapBuilder", "std.SortedSet", "std.SortedSetBuilder"];
			case "runtime.TestCore": ["std.Test"];
			case _: [];
		}
	}

	/**
	 * Whether calls into this module follow the resident ABI on Rust:
	 * Int arguments cast to i32 and Int results cast back to u32 at
	 * non-resident call sites. The resident module and its extern
	 * modules share the ABI.
	 */
	public static function isResidentAbi(module: String): Bool {
		if(isResident(module)) {
			return true;
		}
		for(resident in MODULES.concat(TEST_MODULES)) {
			if(externsOf(resident).indexOf(module) >= 0) {
				return true;
			}
		}
		return false;
	}
}
#end
