package tscompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;

/**
	Collects the module references one generated file needs, splitting
	value references (constructors, static calls) from type-only
	references so every emitted file imports exactly what it uses.

	References resolve per Haxe MODULE. A module holding
	several types is one sibling file, and references from inside that
	module to itself are skipped.
**/
class TsImports {
	final selfModule: String;
	public final selfResident: Bool;
	final valueNames: Map<String, Map<String, Bool>> = [];
	final typeNames: Map<String, Map<String, Bool>> = [];
	final runtimeNames: Map<String, Bool> = [];
	final runtimeTestNames: Map<String, Bool> = [];

	public function new(selfModule: String) {
		this.selfModule = selfModule;
		this.selfResident = RuntimeResidents.isResident(selfModule);
	}

	public function value(moduleBase: String, name: String): Void {
		add(valueNames, moduleBase, name);
	}

	/** Records a module-file function reference without importing private declarations. */
	public function functionRef(moduleBase: String, name: String, isPublic: Bool): String {
		if(isPublic) {
			value(moduleBase, name);
		}
		return name;
	}

	public function type(moduleBase: String, name: String): Void {
		add(typeNames, moduleBase, name);
	}

	/**
		Records a runtime-symbol reference. The specifier comes from the
		runtime-import define; an unset define is an error here because
		the import statement cannot be written without it.
	**/
	public function runtime(name: String): Void {
		if(selfResident) {
			// Resident modules append into runtime.ts itself; a
			// runtime reference from one resolves in the same file.
			return;
		}
		RuntimeConfig.requireImportName("symbol " + name);
		runtimeNames.set(name, true);
	}

	/**
		Records a reference to a runtime symbol of the test entry. The
		test entry lives at the `/test` subpath of the runtime import
		name; the same define guards it.
	**/
	public function runtimeTest(name: String): Void {
		RuntimeConfig.requireImportName("test symbol " + name);
		runtimeTestNames.set(name, true);
	}

	/** Whether any runtime symbol was referenced from this module. */
	public function usesRuntime(): Bool {
		return hasAnyKey(runtimeNames) || hasAnyKey(runtimeTestNames);
	}

	/** Whether any test-entry runtime symbol was referenced. */
	public function usesRuntimeTest(): Bool {
		return hasAnyKey(runtimeTestNames);
	}

	/**
		Modules under `std.` that the runtime package provides. Every other
		std module is a compiled file and imports like any other module.
	**/
	static final runtimeProvidedModules: Map<String, Bool> = [
		"std.Functional" => true,
		"std.ReadOnlyArray" => true,
		"std.SortedMap" => true,
		"std.SortedMapBuilder" => true,
		"std.SortedSet" => true,
		"std.SortedSetBuilder" => true,
		"std.StringBuf" => true,
		"std.Test" => true,
		"std.UString" => true,
		"std.UStringRT" => true,
		"std.Graphemes" => true,
	];

	function add(into: Map<String, Map<String, Bool>>, module: String, name: String): Void {
		if(module == selfModule || module == "Math" || module == "String" || module == "Std" || runtimeProvidedModules.exists(module)) {
			return;
		}
		if(selfResident) {
			if(RuntimeResidents.isResident(module)) {
				// Fellow residents append into the same runtime.ts.
				return;
			}
			Context.error("resident runtime module " + selfModule + " references " + module + "; the runtime package must not depend on generated business modules", Context.currentPos());
		}
		if(!into.exists(module)) {
			into.set(module, []);
		}
		final names = into.get(module);
		if(names != null) {
			names.set(name, true);
		}
		if(into == valueNames) {
			// Value imports are the ones needing a runtime binding when
			// the target module holds only externs; the writer consults
			// the registry (ExternBindings).
			ExternBindings.note(module, name);
		}
	}

	/**
		Module-path-relative specifier: same-package modules resolve as
		siblings and other packages walk up and down. The runtime module
		is not a module path: its specifier is the configured
		runtime-import name, rendered verbatim.
	**/
	static function relativeModule(from: String, to: String): String {
		final fromSegments = from.split(".");
		final toSegments = to.split(".");
		final toName = toSegments[toSegments.length - 1];
		final fromDir = fromSegments.slice(0, fromSegments.length - 1);
		final toDir = toSegments.slice(0, toSegments.length - 1);
		var shared = 0;
		while(shared < fromDir.length && shared < toDir.length && fromDir[shared] == toDir[shared]) {
			shared += 1;
		}
		final parts: Array<String> = [];
		for(i in 0...(fromDir.length - shared)) {
			parts.push("..");
		}
		for(i in shared...toDir.length) {
			parts.push(toDir[i]);
		}
		parts.push(toName);
		return "./" + parts.join("/");
	}

	/**
		Renders the import block for the file at the emitting module's own
		path, relative to the sibling modules and the runtime module at
		the output root. Import keys are full module paths.
	**/
	public function render(): String {
		final moduleSet: Map<String, Bool> = [];
		for(module in valueNames.keys()) moduleSet.set(module, true);
		for(module in typeNames.keys()) moduleSet.set(module, true);
		final modules = [];
		for(module in moduleSet.keys()) modules.push(module);
		modules.sort(Reflect.compare);

		final lines = [];
		for(module in modules) {
			final nameSet: Map<String, Bool> = [];
			final values = valueNames.get(module);
			if(values != null) for(name in values.keys()) nameSet.set(name, true);
			final types = typeNames.get(module);
			if(types != null) for(name in types.keys()) nameSet.set(name, true);
			final names = [];
			for(name in nameSet.keys()) names.push(name);
			names.sort(Reflect.compare);
			lines.push('import { ${names.join(", ")} } from "' + relativeModule(selfModule, module) + '.ts";');
		}
		if(hasAnyKey(runtimeNames)) {
			final names = [];
			for(name in runtimeNames.keys()) names.push(name);
			names.sort(Reflect.compare);
			lines.push('import { ${names.join(", ")} } from "' + runtimeSpecifierFrom(moduleDirPath(selfModule), "", false) + '";');
		}
		if(hasAnyKey(runtimeTestNames)) {
			final names = [];
			for(name in runtimeTestNames.keys()) names.push(name);
			names.sort(Reflect.compare);
			lines.push('import { ${names.join(", ")} } from "' + runtimeSpecifierFrom(moduleDirPath(selfModule), "", true) + '";');
		}
		return lines.length == 0 ? "" : lines.join("\n") + "\n";
	}

	public function renderTestImports(testOutputDir: String, mainOutputDir: String, testRunner: String): String {
		final lines = [];
		if(testRunner == "bun") {
			lines.push('import { test } from "bun:test";');
		} else if(testRunner == "node") {
			lines.push('import { test } from "node:test";');
		}

		final fromSegments = selfModule.split(".");
		final fromDir = testOutputDir + "/" + fromSegments.slice(0, fromSegments.length - 1).join("/");

		if(hasAnyKey(runtimeNames)) {
			final names = [];
			for(name in runtimeNames.keys()) names.push(name);
			names.sort(Reflect.compare);
			lines.push('import { ${names.join(", ")} } from "' + runtimeSpecifierFrom(fromDir, mainOutputDir, false) + '";');
		}
		if(hasAnyKey(runtimeTestNames)) {
			final names = [];
			for(name in runtimeTestNames.keys()) names.push(name);
			names.sort(Reflect.compare);
			lines.push('import { ${names.join(", ")} } from "' + runtimeSpecifierFrom(fromDir, mainOutputDir, true) + '";');
		}

		final moduleSet: Map<String, Bool> = [];
		for(module in valueNames.keys()) moduleSet.set(module, true);
		for(module in typeNames.keys()) moduleSet.set(module, true);
		final modules = [];
		for(module in moduleSet.keys()) modules.push(module);
		modules.sort(Reflect.compare);

		for(module in modules) {
			final nameSet: Map<String, Bool> = [];
			final values = valueNames.get(module);
			if(values != null) for(name in values.keys()) nameSet.set(name, true);
			final types = typeNames.get(module);
			if(types != null) for(name in types.keys()) nameSet.set(name, true);
			final names = [];
			for(name in nameSet.keys()) names.push(name);
			names.sort(Reflect.compare);

			final toFile = mainOutputDir + "/" + module.split(".").join("/") + ".ts";
			final relPath = computeRelativePath(fromDir, toFile);
			lines.push('import { ${names.join(", ")} } from "' + relPath + '";');
		}
		return lines.length == 0 ? "" : lines.join("\n") + "\n";
	}

	/**
		Whether a runtime-import define value selects relative mode. A
		relative specifier makes the generated tree self-contained: the
		import resolves against files the compilation itself wrote
		(feature spec 24).
	**/
	public static function isRelativeSpecifier(name: String): Bool {
		return StringTools.startsWith(name, "./") || StringTools.startsWith(name, "../");
	}

	/**
		The runtime import specifier as seen from one importing
		directory. A by-name define renders verbatim. A relative define
		selects the mode where the entry locations come from
		runtime-emit, and the per-file path is computed exactly as the
		sibling-module imports compute theirs: `toRoot` anchors the
		entry inside the main output tree (empty means the importing
		file already sits there).
	**/
	static function runtimeSpecifierFrom(fromDir: String, toRoot: String, test: Bool): String {
		final name = RuntimeConfig.importName();
		if(!isRelativeSpecifier(name)) {
			return test ? name + "/test" : name;
		}
		final emitDir = RuntimeConfig.emitDir();
		if(emitDir == null) {
			Context.error("relative runtime-import requires runtime-emit: the compiler must know where it wrote the runtime files", Context.currentPos());
		}
		final entry = test ? RuntimeConfig.emitPath(emitDir, "runtime/test.ts") : RuntimeConfig.emitPath(emitDir, "runtime.ts");
		return computeRelativePath(fromDir, toRoot == "" ? entry : toRoot + "/" + entry);
	}

	/** The output-root-relative directory holding one module's file. */
	static function moduleDirPath(module: String): String {
		final segments = module.split(".");
		return segments.slice(0, segments.length - 1).join("/");
	}

	public static function computeRelativePath(fromDir: String, toFile: String): String {
		final fromParts = fromDir.split("/").filter(p -> p.length > 0 && p != ".");
		final toParts = toFile.split("/").filter(p -> p.length > 0 && p != ".");
		var shared = 0;
		while(shared < fromParts.length && shared < toParts.length && fromParts[shared] == toParts[shared]) {
			shared += 1;
		}
		final parts: Array<String> = [];
		for(i in 0...(fromParts.length - shared)) {
			parts.push("..");
		}
		for(i in shared...toParts.length) {
			parts.push(toParts[i]);
		}
		final res = parts.join("/");
		return StringTools.startsWith(res, ".") ? res : "./" + res;
	}

	static function hasAnyKey(map: Map<String, Bool>): Bool {
		for(_ in map.keys()) {
			return true;
		}
		return false;
	}
}
#end
