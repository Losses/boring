package kotlincompiler;

#if (macro || reflaxe_runtime)

/**
	Tracks top-level imports required for each Kotlin generated module.
**/
class KotlinImports {
	final selfModule: String;
	final imports: Map<String, Bool> = [];

	public function new(selfModule: String) {
		this.selfModule = selfModule;
	}

	public function require(importPath: String): Void {
		imports.set(importPath, true);
	}

	public function render(): String {
		final lines = ["package boring"];
		final items = [];
		for(imp in imports.keys()) {
			items.push(imp);
		}
		items.sort(Reflect.compare);
		if(items.length > 0) {
			lines.push("");
			for(imp in items) {
				lines.push("import " + imp);
			}
		}
		return lines.join("\n") + "\n";
	}
}
#end
