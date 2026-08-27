package tscompiler;

#if (macro || reflaxe_runtime)

/**
	Collects the module references one generated file needs, splitting
	value references (constructors, static calls) from type-only
	references so every emitted file imports exactly what it uses.

	References resolve per Haxe MODULE, not per type: a module holding
	several types (GlyphMetrics.hx declares two typedefs) is one sibling
	file, and references from inside that module to itself are skipped.
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

	public function runtime(name: String): Void {
		runtimeNames.set(name, true);
	}

	function add(into: Map<String, Map<String, Bool>>, moduleBase: String, name: String): Void {
		if(moduleBase == selfModule) {
			return;
		}
		if(!into.exists(moduleBase)) {
			into.set(moduleBase, []);
		}
		final names = into.get(moduleBase);
		if(names != null) {
			names.set(name, true);
		}
	}

	/**
		Renders the import block for a file at `boring/<Module>.ts`,
		relative to the sibling modules and the runtime module.
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
			lines.push('import { ${names.join(", ")} } from "./$module.ts";');
		}
		if(hasAnyKey(runtimeNames)) {
			final names = [];
			for(name in runtimeNames.keys()) names.push(name);
			names.sort(Reflect.compare);
			lines.push('import { ${names.join(", ")} } from "../runtime.ts";');
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
