package boring;

import boring.ExtensionOps.ExtensionMode;

/** Cross-module consumer whose Haxe calls remain plain static calls. */
class ExtensionConsumer {
	public static function enumResult():String {
		return ExtensionOps.modeLabel(ExtensionMode.Hot, "!");
	}

	public static function stringResult():String {
		return ExtensionOps.stringLabel("core", "@");
	}

	public static function privateResult():String {
		return ExtensionOps.modeWithPrivate(ExtensionMode.Cold);
	}
}
