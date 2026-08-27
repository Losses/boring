package tscompiler;

#if (macro || reflaxe_runtime)

/**
	Collects the module references one generated file needs, splitting
	value references (constructors, static calls) from type-only
	references so every emitted file imports exactly what it uses.

	References resolve per Haxe MODULE, not per type: a module holding
	several types is one sibling file, and references from inside that
	module to itself are skipped.
**/
class TsImports {
	final selfModule: String;
	final valueNames: Map<String, Map<String, Bool>> = [];
	final typeNames: Map<String, Map<String, Bool>> = [];
	final runtimeNames: Map<String, Bool> = [];

	public function new(selfModule: String) {
		this.selfModule = selfModule;
	}

	public function value(moduleBase: String, name: String): Void {
		add(valueNames, moduleBase, name);
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
		RuntimeConfig.requireImportName("symbol " + name);
		runtimeNames.set(name, true);
	}

	/** Whether any runtime symbol was referenced from this module. */
	public function usesRuntime(): Bool {
		return hasAnyKey(runtimeNames);
	}

	function add(into: Map<String, Map<String, Bool>>, module: String, name: String): Void {
		if(module == selfModule) {
			return;
		}
		if(!into.exists(module)) {
			into.set(module, []);
		}
		final names = into.get(module);
		if(names != null) {
			names.set(name, true);
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
			lines.push('import { ${names.join(", ")} } from "' + RuntimeConfig.importName() + '";');
		}
		return lines.length == 0 ? "" : lines.join("\n") + "\n";
	}

	static function hasAnyKey(map: Map<String, Bool>): Bool {
		for(_ in map.keys()) {
			return true;
		}
		return false;
	}
}
#end
