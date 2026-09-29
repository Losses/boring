package pid;

import std.SortedMap;
import std.SortedMap.SortedMapBuilder;

@:dataClass
class Pair2<T> {
	public final first:T;
	public final second:Inner2<T>;

	public function new(first:T, second:Inner2<T>) {
		this.first = first;
		this.second = second;
	}
}

@:dataClass
class Inner2<T> {
	public final value:T;

	public function new(value:T) {
		this.value = value;
	}
}

class ParameterIdentityProbe {
	public static function build():SortedMapBuilder<Pair2<Int>, String> {
		return SortedMap.builder();
	}
}
