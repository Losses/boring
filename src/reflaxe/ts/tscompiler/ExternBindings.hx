package tscompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Type;

/**
	Binding modules for extern declarations (docs/specs/targets/
	typescript.md). Generated business modules reference extern names
	through the extern's own module path, so one file per referenced
	extern module must hold the runtime bindings; without it every such
	import statement dangles. TsImports records each cross-module value
	reference here while expressions compile, and the file writer emits
	one binding line per referenced extern class: a class annotated
	@:jsRequire("m") binds the module namespace (or the named export
	when a second metadata parameter is present), a class annotated
	@:native("x") binds the global `x`.
**/
class ExternBindings {
	/** Referenced export names per extern module path, keyed by name. */
	static final referenced: Map<String, Map<String, Bool>> = [];

	public static function note(module: String, name: String): Void {
		final names = referenced.get(module);
		if(names != null) {
			names.set(name, true);
			return;
		}
		final fresh: Map<String, Bool> = [];
		fresh.set(name, true);
		referenced.set(module, fresh);
	}

	/** The referenced modules in sorted order, for deterministic output. */
	public static function modules(): Array<String> {
		final out: Array<String> = [];
		for(module in referenced.keys()) out.push(module);
		out.sort(Reflect.compare);
		return out;
	}

	/**
		The binding lines for one module: one line group per extern class
		of the module whose reference name another module imported. Names
		bound by ordinary declarations are ignored here; those modules
		carry their own emitted parts.
	**/
	public static function render(module: String): String {
		final names = referenced.get(module);
		if(names == null) {
			return "";
		}
		final lines: Array<String> = [];
		for(t in Context.getModule(module)) {
			switch(t) {
				case TInst(clsRef, _):
					final cls = clsRef.get();
					final refName = referenceName(cls);
					if(cls.isExtern && names.exists(refName)) {
						lines.push(binding(cls, refName));
					}
				case _:
			}
		}
		return lines.join("\n");
	}

	/**
		The binding text appended to a module file the writer already
		produced, or the empty string when no extern of the module was
		referenced.
	**/
	public static function appendix(module: String): String {
		final text = render(module);
		return text.length == 0 ? "" : "\n" + text + "\n";
	}

	/**
		The name other modules import: the @:native name when the class
		carries one, the class name otherwise.
	**/
	static function referenceName(cls: ClassType): String {
		final native = metaString(cls, ":native", 0);
		return native != null ? native : cls.name;
	}

	static function binding(cls: ClassType, name: String): String {
		final require = metaString(cls, ":jsRequire", 0);
		if(require != null) {
			final global = metaString(cls, ":jsRequire", 1);
			if(global != null) {
				return 'import { ${global} } from "${require}";\nexport const ${name} = ${global};';
			}
			return 'import * as ns_${name} from "${require}";\nexport const ${name} = ns_${name};';
		}
		final native = metaString(cls, ":native", 0);
		if(native != null) {
			return 'export const ${name} = globalThis.${native};';
		}
		Context.error("extern class " + cls.name + " carries no @:native and no @:jsRequire, so the referenced name " + name + " has no runtime binding", cls.pos);
		return "";
	}

	/** One string parameter of a metadata entry, or null. */
	static function metaString(cls: ClassType, key: String, index: Int): Null<String> {
		final entries = cls.meta.extract(key);
		if(entries.length == 0 || entries[0].params.length <= index) {
			return null;
		}
		return switch(entries[0].params[index].expr) {
			case EConst(CString(s)): s;
			case _: null;
		};
	}
}
#end
