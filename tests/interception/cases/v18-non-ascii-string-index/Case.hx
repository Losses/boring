// expect: V18 NonAsciiStringIndex
class Case {
	static final TITLE:String = "标题";

	static function directLiteral():Int {
		return "中文".charCodeAt(0);
	}

	static function lengthLiteral():Int {
		return "中文".length;
	}

	static function viaLocal():Int {
		final label:String = "标签";
		return label.charCodeAt(1);
	}

	static function viaField():Int {
		return TITLE.length;
	}

	static function viaFromCharCode():String {
		return String.fromCharCode(0x4E2D);
	}

	static function viaStringToolsCodeAt():Int {
		return StringTools.fastCodeAt("中文", 0);
	}

	static function viaStringToolsFromCharCode():String {
		return StringTools.fromCharCode(0x4E2D);
	}

	static function main():Void {
		directLiteral();
		lengthLiteral();
		viaLocal();
		viaField();
		viaFromCharCode();
		viaStringToolsCodeAt();
		viaStringToolsFromCharCode();
	}
}
