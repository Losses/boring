package boring;

enum Mode {
	Read;
	Write;
}

interface IGreeter {
	function say(name:String, title:String = "User"):String;
}

class GreeterImpl implements IGreeter {
	public function new() {}

	public function say(name:String, title:String = "User"):String {
		return title + ":" + name;
	}
}

class DefaultArgsOps {
	public var familyNames:Array<String>;

	public function new(?familyNames:Array<String>) {
		this.familyNames = familyNames == null ? [] : familyNames;
	}

	public static function greet(name:String, prefix:String = "Hello"):String {
		return prefix + " " + name;
	}

	public static function configure(base:Int, offset:Int = 10, scale:Float = 2.5, flag:Bool = true):Float {
		final sum = (base + offset) * scale;
		return flag ? sum : -sum;
	}

	public function formatLabel(?label:String, sep:String = "-"):String {
		if (label == null) {
			return "none" + sep + "default";
		}
		return label + sep + "formatted";
	}

	public static function describeTag(tag:String, detail:Null<String> = null):String {
		if (detail == null) {
			return tag + ":none";
		}
		return tag + ":" + detail;
	}

	public static function openMode(id:Int, mode:Mode = Mode.Read):String {
		if (mode == Mode.Write) {
			return "write:" + id;
		}
		return "read:" + id;
	}

	public static function adjust(value:Float, step:Float = -5.0):Float {
		return value + step;
	}

	public static function infinityDefault(?value:Float):Float {
		var normalized = value == null ? Math.POSITIVE_INFINITY : value;
		return normalized;
	}

	public static function mapDefault(?value:Map<String,Int>):Map<String,Int> {
		var normalized = value == null ? new Map() : value;
		return normalized;
	}

	public static function computeWithLocal(x:Int):Int {
		final localAdd = function(a:Int, b:Int = 100):Int {
			return a + b;
		};
		return localAdd(x);
	}

	public static function computeWithLocalB(x:Int):Int {
		final localAdd = function(a:Int, b:Int = 200):Int {
			return a + b;
		};
		return localAdd(x);
	}

	public static function callGreet0():String {
		return greet("Ada", "Greetings");
	}

	public static function callGreet1():String {
		return greet("Ada");
	}

	public static function callConfigure0():Float {
		return configure(100, 20, 1.5, false);
	}

	public static function callConfigure1():Float {
		return configure(100, 20, 1.5);
	}

	public static function callConfigure2():Float {
		return configure(100, 20);
	}

	public static function callConfigure3():Float {
		return configure(100);
	}

	public static function callFormatLabel0():String {
		final ops = new DefaultArgsOps();
		return ops.formatLabel("item", ":");
	}

	public static function callFormatLabel1():String {
		final ops = new DefaultArgsOps();
		return ops.formatLabel("item");
	}

	public static function callFormatLabel2():String {
		final ops = new DefaultArgsOps();
		return ops.formatLabel();
	}

	public static function callDescribeTag0():String {
		return describeTag("alpha", "extra");
	}

	public static function callDescribeTag1():String {
		return describeTag("alpha");
	}

	public static function callOpenMode0():String {
		return openMode(1, Mode.Write);
	}

	public static function callOpenMode1():String {
		return openMode(1);
	}

	public static function callAdjust0():Float {
		return adjust(20.0, 10.0);
	}

	public static function callAdjust1():Float {
		return adjust(20.0);
	}

	public static function callInfinity0():Float {
		return infinityDefault();
	}

	public static function callInfinity1():Float {
		return infinityDefault(1.25);
	}

	public static function callMapDefault():Map<String,Int> {
		return mapDefault();
	}

	public static function callLocal():Int {
		return computeWithLocal(7);
	}

	public static function callLocalB():Int {
		return computeWithLocalB(7);
	}

	public static function callInterface0():String {
		final greeter:IGreeter = new GreeterImpl();
		return greeter.say("Sam", "Admin");
	}

	public static function callInterface1():String {
		final greeter:IGreeter = new GreeterImpl();
		return greeter.say("Sam");
	}

	// --- Extension grammar roots: coalescing defaults that read parameters or static fields ---

	/** Bare earlier-parameter read. */
	public static function greetWithPrefix(name:String, ?prefix:String):String {
		var normalized = prefix == null ? name : prefix;
		return normalized;
	}

	/** Field access over a parameter. */
	public static function sizeLabel(?items:Array<String>):String {
		final count = items == null ? 0 : items.length;
		return 'size:$count';
	}

	/** Conditional over a parameter. */
	public static function localeSample(lang:String, ?fallback:String):String {
		var normalized = fallback == null ? (lang == "en" ? "English" : "Other") : fallback;
		return normalized;
	}

	/** Static-field read (class constant). */
	public static function staticFieldSample(value:Int, ?factor:Float):Float {
		var normalized = factor == null ? Math.POSITIVE_INFINITY : factor;
		return value * normalized;
	}

	/** Dependence assertion: same function called with different earlier arguments. */
	public static function dependenceEarlier(a:String, ?b:String):String {
		var normalized = b == null ? a : b;
		return normalized;
	}

	public static function callDependenceA():String {
		return dependenceEarlier("alpha");
	}

	public static function callDependenceB():String {
		return dependenceEarlier("beta");
	}
}
