package comparisonplan;

@:dataClass
class Box<T> {
	public final value:T;

	public function new(value:T) {
		this.value = value;
	}
}

@:dataClass
class ComparedParameter<T> {
	public final value:T;
	public function new(value:T) this.value = value;
}

@:dataClass
class IgnoredParameter<T> {
	public final value:Int;
	public function new(value:Int) this.value = value;
}

@:dataClass
class NestedParameter<T> {
	public final value:Box<T>;
	public function new(value:Box<T>) this.value = value;
}

@:dataClass
class NullableParameter<T> {
	public final value:Null<T>;
	public function new(value:Null<T>) this.value = value;
}

@:dataClass
class SequenceParameter<T> {
	public final value:std.ReadOnlyArray<T>;
	public function new(value:std.ReadOnlyArray<T>) this.value = value;
}

@:dataClass
class FieldOrder {
	public final first:Int;
	public final second:String;
	public var computed(get, never):Int;

	public function new(first:Int, second:String) {
		this.first = first;
		this.second = second;
	}

	function get_computed():Int {
		return first;
	}
}

@:dataClass
class Swap<A, B> {
	public final next:Null<Swap<B, A>>;

	public function new(next:Null<Swap<B, A>>) {
		this.next = next;
	}
}

@:dataClass
class FiniteGrowth<A, B> {
	public final next:Null<FiniteGrowth<Box<B>, Box<Box<Int>>>>;

	public function new(next:Null<FiniteGrowth<Box<B>, Box<Box<Int>>>>) {
		this.next = next;
	}
}

@:dataClass
class Expand<T> {
	public final next:Expand<Array<T>>;

	public function new(next:Expand<Array<T>>) {
		this.next = next;
	}
}

@:dataClass
class FloatKey {
	public final value:Float;

	public function new(value:Float) {
		this.value = value;
	}
}

@:dataClass
class BoolKey {
	public final value:Bool;

	public function new(value:Bool) {
		this.value = value;
	}
}
