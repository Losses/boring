package rustcompiler;

#if (macro || reflaxe_runtime)
/**
	Tracks imports for one generated Rust module.
**/
class RustImports {
	/** Modules of the standard library that lower to emitted shims. */
	static final SHIM_MODULES: Map<String, Bool> = [
		"haxe.io.FPHelper" => true,
		"haxe.io.BytesBuffer" => true,
		"std.Console" => true,
		"std.Process" => true,
		"std.SortedMap" => true,
		"std.SortedMapBuilder" => true,
		"std.SortedSet" => true,
		"std.SortedSetBuilder" => true,
		"std.UStringRT" => true,
	];

	/** Resident table class behind each sorted extern (runtime.SortedTable). */
	static final SORTED_TABLE_CLASSES: Map<String, String> = [
		"std.SortedMap" => "SortedMapTable",
		"std.SortedMapBuilder" => "SortedMapTableBuilder",
		"std.SortedSet" => "SortedSetTable",
		"std.SortedSetBuilder" => "SortedSetTableBuilder",
	];

	public final selfModule: String;
	final state: RustEmissionState;
	final imports: Map<String, Bool> = [];

	public function new(selfModule: String, state: RustEmissionState) {
		this.selfModule = selfModule;
		this.state = state;
	}

	public function require(importPath: String): Void {
		imports.set(importPath, true);
	}

	public function requireType(module: String, name: String): Void {
		if(module == "Std" || module == "Math" || module == "String" || module == "haxe.Int64" || module == "haxe.io.Bytes") {
			return;
		}
		// The sorted externs front the runtime.SortedTable resident: the
		// table classes live in one module under their resident names.
		final sortedClass = SORTED_TABLE_CLASSES.get(module);
		if(sortedClass != null) {
			final runtimePackage = RuntimeConfig.requireImportName("module " + module);
			state.shimsUsed.set(module, true);
			require(runtimePackage + "::sorted_table::" + sortedClass);
			return;
		}
		if(SHIM_MODULES.exists(module)) {
			final runtimePackage = RuntimeConfig.requireImportName("module " + module);
			state.shimsUsed.set(module, true);
			final modName = if(module == "std.UStringRT") {
				"ustring";
			} else {
				toSnakeCase(name);
			};
			require(runtimePackage + "::" + modName + "::" + name);
			return;
		}
		final targetModule = state.payloadEnumModules.exists(module) ? state.payloadEnumModules.get(module) : module;
		if(targetModule != selfModule) {
			final rustMod = moduleToRustPath(targetModule);
			require("crate::" + rustMod + "::" + name);
		}
	}

	public function render(): String {
		final items = [];
		for(imp in imports.keys()) {
			items.push(imp);
		}
		items.sort(Reflect.compare);
		if(items.length == 0) {
			return "";
		}
		final lines = [for(imp in items) "use " + imp + ";"];
		return lines.join("\n") + "\n\n";
	}

	/**
		Renders against the finished module body: the sorted-table import
		follows a type mention that can vanish when every use of the extern
		lowered to a different spelling, so it stays only when the body
		names the table symbol.
	**/
	public function renderFiltered(body: String): String {
		final items = [];
		for(imp in imports.keys()) {
			items.push(imp);
		}
		items.sort(Reflect.compare);
		final lines = [];
		for(imp in items) {
			if(StringTools.startsWith(imp, "crate::runtime::sorted_table::")) {
				final symbol = imp.substr(imp.lastIndexOf("::") + 2);
				if(body.indexOf(symbol) < 0) continue;
			}
			lines.push("use " + imp + ";");
		}
		if(lines.length == 0) {
			return "";
		}
		return lines.join("\n") + "\n\n";
	}

	public static function moduleToRustPath(module: String): String {
		final parts = module.split(".");
		final out = [];
		for(p in parts) {
			out.push(toSnakeCase(p));
		}
		return out.join("::");
	}

	public static function toScreamingSnakeCase(s: String): String {
		return toSnakeCase(s).toUpperCase();
	}

	public static function toSnakeCase(s: String): String {
		if(s == null || s.length == 0) {
			return s;
		}
		var isAllUpper = true;
		for(i in 0...s.length) {
			final c = s.charCodeAt(i);
			if(c >= 97 && c <= 122) {
				isAllUpper = false;
				break;
			}
		}
		if(isAllUpper) {
			return s.length == 1 ? s.toLowerCase() : s;
		}

		final buf = new StringBuf();
		for(i in 0...s.length) {
			final c = s.charAt(i);
			final code = s.charCodeAt(i);
			final isUpper = code >= 65 && code <= 90;
			if(isUpper) {
				if(i > 0) {
					final prevCode = s.charCodeAt(i - 1);
					final prevIsLowerOrDigit = (prevCode >= 97 && prevCode <= 122) || (prevCode >= 48 && prevCode <= 57);
					final nextIsLower = (i + 1 < s.length) && (s.charCodeAt(i + 1) >= 97 && s.charCodeAt(i + 1) <= 122);
					final prevIsUpper = prevCode >= 65 && prevCode <= 90;
					if(prevIsLowerOrDigit || (prevIsUpper && nextIsLower)) {
						buf.addChar("_".code);
					}
				}
				buf.addChar(code + 32);
			} else {
				buf.add(c);
			}
		}
		return buf.toString();
	}
}
#end
