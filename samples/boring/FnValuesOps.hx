package boring;

// Function values in the shapes the engine port consumes: function-typed
// constructor fields stored and invoked, interface-typed fields, function
// parameters, generic function parameters, local function values, returned
// function values, and a static function-typed field.

interface NameResolver {
	function resolve(id:String):String;
}

class BuiltInNameResolver implements NameResolver {
	public function new() {}

	public function resolve(id:String):String {
		return "built-in:" + id;
	}
}

class FnValuesOps {
	public var styleAt:(index:Int) -> String;

	public var resolver:NameResolver;

	public static var defaultTag:(id:Int) -> String = function(id:Int) return "tag" + id;

	public function new(styleAt:(index:Int) -> String, resolver:NameResolver) {
		this.styleAt = styleAt;
		this.resolver = resolver;
	}

	public function styleLabel(index:Int):String {
		return this.styleAt(index);
	}

	public function resolveLabel(id:String):String {
		return this.resolver.resolve(id);
	}

	public static function applyPicker(values:Array<String>, pick:(index:Int) -> String):String {
		return pick(values.length - 1);
	}

	public static function mapOne<T>(value:T, convert:(item:T) -> T):T {
		return convert(value);
	}

	public static function storedLocal():String {
		final render:(code:Int) -> String = function(code:Int) return "u" + code;
		return render(0x4E00);
	}

	public static function makePrefixer(prefix:String):(suffix:String) -> String {
		final joined:(suffix:String) -> String = function(suffix:String) return prefix + suffix;
		return joined;
	}
}
