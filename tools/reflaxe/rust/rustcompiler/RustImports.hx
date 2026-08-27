package rustcompiler;

#if (macro || reflaxe_runtime)
/**
	Tracks imports for one generated Rust module.
**/
class RustImports {
	/** Modules of the standard surface that lower to emitted shims. */
	static final SHIM_MODULES: Map<String, Bool> = [
		"haxe.io.FPHelper" => true,
		"haxe.io.BytesBuffer" => true,
		"std.Console" => true,
		"std.Process" => true,
	];

	final selfModule: String;
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
		if(SHIM_MODULES.exists(module)) {
			final runtimePackage = RuntimeConfig.requireImportName("module " + module);
			state.shimsUsed.set(module, true);
			final modName = toSnakeCase(name);
			require(runtimePackage + "::" + modName + "::" + name);
			return;
		}
		if(module != selfModule) {
			final rustMod = moduleToRustPath(module);
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

	public static function moduleToRustPath(module: String): String {
		final parts = module.split(".");
		final out = [];
		for(p in parts) {
			out.push(toSnakeCase(p));
		}
		return out.join("::");
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
			return s;
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
