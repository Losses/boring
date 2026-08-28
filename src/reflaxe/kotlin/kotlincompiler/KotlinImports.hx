package kotlincompiler;

#if (macro || reflaxe_runtime)

/**
	Tracks the import list of one generated Kotlin module and derives its
	package directive from the module path. Type references record the
	cross-package imports they need; references to the standard-library
	modules additionally mark those shims as used so the compiler emits
	them on demand.
**/
class KotlinImports {
	/** Modules of the standard library that lower to emitted shims. */
	static final SHIM_MODULES: Map<String, Bool> = [
		"haxe.io.FPHelper" => true,
		"haxe.io.BytesBuffer" => true,
		"std.Console" => true,
		"std.Process" => true,
		"std.Test" => true,
		"std.SortedMap" => true,
		"std.SortedMapBuilder" => true,
		"std.SortedSet" => true,
		"std.SortedSetBuilder" => true,
		"std.UStringRT" => true,
	];

	final selfPack: String;
	final state: KotlinEmissionState;
	final imports: Map<String, Bool> = [];

	public function new(selfModule: String, state: KotlinEmissionState) {
		final segments = selfModule.split(".");
		this.selfPack = segments.length <= 1 ? "" : segments.slice(0, segments.length - 1).join(".");
		this.state = state;
	}

	public function require(importPath: String): Void {
		imports.set(importPath, true);
	}

	/**
		Records a reference to a named type. Types in the same package are
		visible without an import. The standard-library modules are
		source-side identities: their runtime home is the configured
		runtime package, so they import as `<runtime-import>.<Type>` and
		mark their shims as used; the `haxe.*`/`std` namespaces never
		reach the output.
	**/
	public function requireType(module: String, name: String): Void {
		if(module == "Std" || module == "Math" || module == "String") {
			return;
		}
		if(SHIM_MODULES.exists(module)) {
			final runtimePackage = RuntimeConfig.requireImportName("module " + module);
			state.shimsUsed.set(module, true);
			require(runtimePackage + "." + name);
			return;
		}
		final pack = packOf(module);
		if(pack != selfPack) {
			require(pack.length == 0 ? name : pack + "." + name);
		}
	}

	public function render(): String {
		final lines = selfPack.length == 0 ? [] : ["package " + selfPack];
		final items = [];
		for(imp in imports.keys()) {
			items.push(imp);
		}
		items.sort(Reflect.compare);
		if(items.length > 0) {
			if(lines.length > 0) {
				lines.push("");
			}
			for(imp in items) {
				lines.push("import " + imp);
			}
		}
		return lines.length > 0 ? lines.join("\n") + "\n" : "";
	}

	function packOf(module: String): String {
		final segments = module.split(".");
		return segments.length <= 1 ? "" : segments.slice(0, segments.length - 1).join(".");
	}
}
#end
