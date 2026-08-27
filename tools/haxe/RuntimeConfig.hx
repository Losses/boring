#if (macro || reflaxe_runtime)
import haxe.macro.Context;

/**
	Runtime package configuration shared by every reflaxe target. The
	runtime package's identity enters as compile-time defines so no target
	compiler knows the consumer's package identity: each target only
	renders the configured name in its own import syntax.

	- `runtime-import=<name>`: how generated code references the runtime
	  package (`@scope/runtime` verbatim for TypeScript, a dotted package
	  for Kotlin, a crate name for Rust). No default exists: the name has
	  no source inside the compilation, so a compilation that references
	  a runtime symbol without the define stops with an error instead of
	  inventing a consumer identity.
	- `runtime-emit=<dir>`: `none` (or absent) writes references only,
	  which is the bring-your-own mode; any other value writes the
	  runtime files under that directory, relative to the target's
	  output root.
**/
class RuntimeConfig {
	/** The configured runtime import specifier, or null when unset. */
	public static function importName(): Null<String> {
		return Context.definedValue("runtime-import");
	}

	/** The emit directory under the output root, or null for bring-your-own mode. */
	public static function emitDir(): Null<String> {
		final value = Context.definedValue("runtime-emit");
		if(value == null || value == "none") {
			return null;
		}
		return value;
	}

	/**
		The import specifier for a compilation about to reference a
		runtime symbol. Errors when unset: the import statement cannot
		be written without it.
	**/
	public static function requireImportName(what: String): String {
		final name = importName();
		if(name == null) {
			Context.error("runtime-import define is required to reference the runtime package (" + what + "); the consumer's package identity is not derivable from the compilation and no default exists", Context.currentPos());
		}
		return name;
	}

	/** A file name under the emit directory, which may be the output root itself. */
	public static function emitPath(dir: String, fileName: String): String {
		return dir == "." ? fileName : dir + "/" + fileName;
	}
}
#end
