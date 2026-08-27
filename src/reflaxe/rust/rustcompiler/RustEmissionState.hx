package rustcompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Type;

/**
	Emission state shared across modules for the Rust target.
**/
class RustEmissionState {
	/** Maps payload enum module path to its owning exception class name. */
	public final payloadEnumOwners: Map<String, String> = [];

	/** Maps payload enum module path to its owning exception class module path. */
	public final payloadEnumModules: Map<String, String> = [];

	/** Maps exception class module path to its payload enum module path. */
	public final exceptionPayloads: Map<String, String> = [];

	/** Maps anonymous structure signatures to their defining typedef name and module. */
	public final structTypedefs: Map<String, {module: String, name: String}> = [];

	/** Standard-library shims used during compilation. */
	public final shimsUsed: Map<String, Bool> = [];

	/** Error enum module and name for Result<T, Error>. */
	public var errorModule: Null<String> = null;
	public var errorName: Null<String> = null;
	public var overflowVariant: Null<String> = null;

	/** Types reachable at test assertion call sites for type-guided helpers. */
	public final testReachableTypes: Map<String, Type> = [];

	/** Modules containing @:test methods. */
	public final testModules: Map<String, Bool> = [];

	public function new() {}
}
#end
