package rustcompiler;

#if (macro || reflaxe_runtime)
/**
	Emission state shared across modules for the Rust target.
**/
class RustEmissionState {
	/** Maps payload enum module path to its owning exception class name. */
	public final payloadEnumOwners: Map<String, String> = [];

	/** Maps exception class module path to its payload enum module path. */
	public final exceptionPayloads: Map<String, String> = [];

	/** Maps anonymous structure signatures to their defining typedef name and module. */
	public final structTypedefs: Map<String, {module: String, name: String}> = [];

	/** Standard-surface shims used during compilation. */
	public final shimsUsed: Map<String, Bool> = [];

	/** Error enum module and name for Result<T, Error>. */
	public var errorModule: Null<String> = null;
	public var errorName: Null<String> = null;
	public var overflowVariant: Null<String> = null;

	public function new() {}
}
#end
