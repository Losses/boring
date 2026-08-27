package kotlincompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Type;

/**
	State shared by the emitters of one compilation: shim usage tracked
	for demand-driven runtime emission, the payload-enum linkage of the
	sealed error fold, the structure-to-typedef index backing
	nominal object literals, and test reachable types for type-guided helpers.
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

	/** Types reachable at test assertion call sites for type-guided helpers. */
	public final testReachableTypes: Map<String, Type> = [];

	/** Test classes compiled with their @:test methods. */
	public final testClasses: Map<String, {cls: ClassType, funcs: Array<String>}> = [];

	public function new() {}
}
#end
