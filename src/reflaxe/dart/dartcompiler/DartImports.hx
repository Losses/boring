package dartcompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;

/**
	Import table of one generated Dart library. Every cross-module
	reference resolves through a relative import of the referenced
	library, prefixed by the referenced module's file stem so top-level
	functions of two statics-only modules never collide in one file
	(docs/specs/stdlib/06-std-modules.md, module and name mapping). The runtime package and
	the test host import the same way; a resident module compiles into
	the runtime library itself, so its references stay same-library.
**/
class DartImports {
	public final selfModule: String;
	public final selfResident: Bool;

	/** Module path to its import prefix, in first-reference order. */
	final modules: Map<String, String> = [];

	/** Modules whose unnamed extensions must be imported without a prefix. */
	final extensionModules: Map<String, Bool> = [];

	final runtimeNames: Map<String, Bool> = [];
	final runtimeTestNames: Map<String, Bool> = [];

	var dartMathUsed = false;

	public function new(selfModule: String) {
		this.selfModule = selfModule;
		this.selfResident = RuntimeResidents.isResident(selfModule);
	}

	/** Records that this module referenced a dart:math member (Math.sqrt). */
	public function useDartMath(): Void {
		dartMathUsed = true;
	}

	/** Whether this module needs the dart:math import. */
	public function usesDartMath(): Bool {
		return dartMathUsed;
	}

	/** The cross-module imports recorded so far, in first-reference order. */
	public function moduleList(): Array<{module: String, prefix: String}> {
		final out: Array<{module: String, prefix: String}> = [];
		for(module in modules.keys()) {
			out.push({module: module, prefix: modules.get(module)});
		}
		out.sort((a, b) -> Reflect.compare(a.module, b.module));
		return out;
	}

	/**
		Records a runtime-package reference. With an emit directory the
		runtime is written inside the output tree and every referencing file
		imports it relatively; without one the compilation is in
		bring-your-own mode and the import specifier comes from the
		runtime-import define verbatim, the URI the consumer controls.
	**/
	public function runtime(name: String): Void {
		runtimeNames.set(name, true);
	}

	/** Records a reference to a symbol of the test host entry. */
	public function runtimeTest(name: String): Void {
		runtimeTestNames.set(name, true);
	}

	/**
		The prefix runtime-package references render under: `runtime` for
		a business library importing the emitted runtime library, empty
		for a resident module that compiles into it.
	**/
	public function runtimePrefix(): String {
		if(selfResident) {
			return "";
		}
		runtimeNames.set("*", true);
		return "runtime";
	}

	/**
		The prefix test-host references render under: `test_host` for a
		generated library importing the host entry, empty for the
		resident that compiles into it.
	**/
	public function runtimeTestPrefix(): String {
		if(RuntimeResidents.isTestResident(selfModule)) {
			return "";
		}
		runtimeTestNames.set("*", true);
		return "test_host";
	}

	/** Whether any runtime symbol was referenced from this module. */
	public function usesRuntime(): Bool {
		return hasAnyKey(runtimeNames);
	}

	/** Whether any test-host symbol was referenced. */
	public function usesRuntimeTest(): Bool {
		return hasAnyKey(runtimeTestNames);
	}

	/**
		Records a cross-module business reference and returns the prefix
		the reference renders under. A same-module reference returns the
		empty prefix: the declaration sits in this library.
	**/
	public function value(module: String, name: String): String {
		return prefixOf(module);
	}

	/** Records an extension library import, which must remain unprefixed. */
	public function useExtension(module: String): Void {
		checkPurity(module);
		if(module == selfModule) {
			return;
		}
		if(RuntimeResidents.isResident(module) && RuntimeResidents.isResident(selfModule)
			&& RuntimeResidents.isTestResident(module) == RuntimeResidents.isTestResident(selfModule)) {
			return;
		}
		extensionModules.set(module, true);
	}

	/** Extension libraries in stable module order for the import block. */
	public function extensionModuleList(): Array<String> {
		final out: Array<String> = [];
		for(module in extensionModules.keys()) {
			out.push(module);
		}
		out.sort(Reflect.compare);
		return out;
	}

	public function type(module: String, name: String): String {
		return prefixOf(module);
	}

	function prefixOf(module: String): String {
		checkPurity(module);
		if(module == selfModule || module == "Math" || module == "String" || module == "Std") {
			return "";
		}
		// Residents merge into one emitted library per tree side (the
		// runtime library, the test host), so a resident referencing
		// another resident of the same side stays same-library.
		if(RuntimeResidents.isResident(module) && RuntimeResidents.isResident(selfModule)) {
			final targetHost = RuntimeResidents.isTestResident(module);
			if(targetHost == RuntimeResidents.isTestResident(selfModule)) {
				return "";
			}
		}
		final existing = modules.get(module);
		if(existing != null) {
			return existing;
		}
		final prefix = importPrefixOf(module);
		for(other => taken in modules) {
			if(taken == prefix) {
				Context.error("modules " + other + " and " + module + " share one import prefix in " + selfModule, Context.currentPos());
			}
		}
		modules.set(module, prefix);
		return prefix;
	}

	/** The import prefix of a module: the snake-case stem of its library file. */
	public static function importPrefixOf(module: String): String {
		final parts = module.split(".");
		return DartDecl.snakeCase(parts[parts.length - 1]);
	}

	/** The emitted library path of a module: `pack.Module` maps to `pack/module.dart`. */
	public static function libraryPathOf(module: String): String {
		final parts = module.split(".");
		final pack = parts.slice(0, parts.length - 1);
		final stem = DartDecl.snakeCase(parts[parts.length - 1]);
		return (pack.length > 0 ? pack.join("/") + "/" : "") + stem + ".dart";
	}

	function checkPurity(module: String): Void {
		if(module == selfModule || module == "Math" || module == "String" || module == "Std" || RuntimeResidents.isResident(module)) {
			return;
		}
		if(selfResident) {
			Context.error("resident runtime module " + selfModule + " references " + module + "; the runtime package must not depend on generated business modules", Context.currentPos());
		}
	}

	static function hasAnyKey(map: Map<String, Bool>): Bool {
		for(_ in map.keys()) {
			return true;
		}
		return false;
	}
}
#end
