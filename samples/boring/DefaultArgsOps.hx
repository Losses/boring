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
	public function new() {}

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

	public static function computeWithLocal(x:Int):Int {
		final localAdd = function(a:Int, b:Int = 100):Int {
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

	public static function callLocal():Int {
		return computeWithLocal(7);
	}

	public static function callInterface0():String {
		final greeter:IGreeter = new GreeterImpl();
		return greeter.say("Sam", "Admin");
	}

	public static function callInterface1():String {
		final greeter:IGreeter = new GreeterImpl();
		return greeter.say("Sam");
	}
}
