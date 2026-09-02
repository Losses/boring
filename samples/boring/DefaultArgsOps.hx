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

	// --- Extension grammar roots: coalescing defaults that read parameters ---

	/** Bare earlier-parameter read. */
	public static function greetWithPrefix(name:String, ?prefix:String):String {
		var normalized = prefix == null ? name : prefix;
		return normalized;
	}


	public static function sizeLabel(?items:Array<String>):String {
		final count = items == null ? 0 : items.length;
		return 'size:$count';
	}

	public static function fieldAccessSample(items:Array<String>, ?count:Int):Int {
		var normalized = count == null ? items.length : count;
		return normalized;
	}

	/** Conditional over a parameter. */
	public static function localeSample(lang:String, ?fallback:String):String {
		var normalized = fallback == null ? (lang == "en" ? "English" : "Other") : fallback;
		return normalized;
	}

	/** Instance method call over an earlier parameter. */
	public static function methodCallSample(text:String, ?normalized:String):String {
		var value = normalized == null ? text.toUpperCase() : normalized;
		return value;
	}

	/** Static call with an earlier parameter argument. */
	public static function clampBase(value:Int):Int {
		return value > 0 ? value : 0;
	}

	public static function staticCallSample(value:Int, ?clamped:Int):Int {
		var result = clamped == null ? clampBase(value) : clamped;
		return result;
	}

	/** Static-field read. */
	public static function staticFieldSample(value:Int, ?bound:Int):Int {
		var normalized = bound == null ? StaticStateOps.limit : bound;
		return value + normalized;
	}

	/** Binary operator over a grammar expression. */
	public static function binarySample(value:Int, ?offset:Int):Int {
		var result = offset == null ? value + 1 : offset;
		return result;
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

	/**
		Chain over two coalescing parameters: the later default reads the
		earlier parameter, and both parameters may be omitted at one call.
	*/
	public static function chainedCoalescing(?fallback:Float, ?value:Float):Float {
		var resolvedFallback = fallback == null ? 2.5 : fallback;
		var resolvedValue = value == null ? fallback : value;
		return resolvedFallback + resolvedValue;
	}

	public static function callChainedBothOmitted():Float {
		return chainedCoalescing();
	}

	public static function callChainedLaterOmitted():Float {
		return chainedCoalescing(3.5);
	}

	public static function callChainedBothGiven():Float {
		return chainedCoalescing(1.5, 8.0);
	}
}

/**
	Constructor chain over two coalescing field parameters, the
	RichTextBackgroundPaint shape of the engine port: the later parameter
	defaults to the earlier one.
*/
class ChainedPaint {
	public var radius:Float;
	public var followRadius:Float;

	public function new(?radius:Float, ?followRadius:Float) {
		this.radius = radius == null ? 0.0 : radius;
		this.followRadius = followRadius == null ? radius : followRadius;
	}
}

/**
	The AutoSpacePolicy shape of the engine port: a @:dataClass whose
	constructor parameters all hold coalescing defaults, so the default
	preset constructs with zero arguments. Spec 32 rule 2 keys the
	singleton form on a declaring class with no instance fields, so this
	static is a constructed initializer of spec 35 and the printed form
	stays the spec 31 labeled text.
*/
@:dataClass
class CoalescingPreset {
	public final base:Float;
	public final ceiling:Float;

	public function new(?base:Null<Float>, ?ceiling:Null<Float>) {
		this.base = base == null ? 0.125 : base;
		this.ceiling = ceiling == null ? 0.5 : ceiling;
	}

	public static final Default:CoalescingPreset = new CoalescingPreset();
}
