// expect: V01 IteratorLoop
import haxe.iterators.ArrayIterator;
class Case {
	static function main() {
		final values:Iterable<Int> = [1, 2, 3];
		for (item in values) trace(item);
	}
}
