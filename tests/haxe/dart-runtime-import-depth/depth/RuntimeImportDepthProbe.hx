package depth;

import std.Process;

/**
	Minimal Dart runtime-import-depth regression fixture (task
	t-muviv6in-y1qx). One business library under `lib/depth/` that
	references both emitted runtime files:

	- `haxe.Exception` lowers onto `runtime.BoringException`, so the
	  library imports `runtime.dart`;
	- `std.Process.args()` lowers onto `platform_host.processArgs()`, so
	  the library imports `platform_host.dart`.

	The generated library sits under `lib/`, and Dart forbids a relative
	import that climbs above the package's `lib/` root, so both runtime
	files must be emitted under `lib/` and both imports must be one level
	up. Before the fix the files sat at the output-tree root and the
	imports were `../../runtime.dart` / `../../platform_host.dart`,
	which the analyzer reported as URI_DOES_NOT_EXIST and the VM refused
	with "No such file or directory".
**/
class RuntimeImportDepthProbe {
	public static function main():Void {
		try {
			throw new DepthFault("runtime");
		} catch (e:DepthFault) {
			if (e.tag == null || Process.args() == null) {
				throw new DepthFault("platform");
			}
		}
	}
}

class DepthFault extends haxe.Exception {
	public final tag:String;

	public function new(tag:String) {
		this.tag = tag;
		super(tag);
	}
}
