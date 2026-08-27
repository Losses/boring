package kotlincompiler;

#if (macro || reflaxe_runtime)

/**
	State shared by the emitters of one compilation: shim usage tracked
	for demand-driven runtime emission, the payload-enum linkage of the
	sealed error fold, and the structure-to-typedef index backing
	nominal object literals.
**/
class KotlinEmissionState {
	/** Shim file paths (no extension) referenced by emitted code. */
	public final shimsUsed: Map<String, Bool> = [];

	/** Payload-enum module to the exception class that folded it. */
	public final payloadEnumOwners: Map<String, String> = [];

	/** Exception-class module to the payload enum module it folds. */
	public final exceptionPayloads: Map<String, String> = [];

	/** Anonymous-structure signature to the typedef naming it. */
	public final structTypedefs: Map<String, {module: String, name: String}> = [];

	public function new() {}
}
#end
