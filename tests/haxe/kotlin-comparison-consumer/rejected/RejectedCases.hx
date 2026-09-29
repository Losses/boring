package rejected;

import std.SortedMap;
import std.SortedMap.SortedMapBuilder;

@:dataClass
class RejectedKey {
	public final ratio:Float;

	public function new(ratio:Float) {
		this.ratio = ratio;
	}
}

class RejectedCases {
	public static function main():Void {
		final builder:SortedMapBuilder<RejectedKey, String> = SortedMap.builder();
	}
}
