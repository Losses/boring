package comparison;

import std.ReadOnlyArray;
import std.SortedMap;
import std.SortedMap.SortedMapBuilder;

@:dataClass
class NestedValue<T> {
	public final value:T;
	public function new(value:T) this.value = value;
}

@:dataClass
class ComparedParameterKey<T> {
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
	public final value:NestedValue<T>;
	public function new(value:NestedValue<T>) this.value = value;
}

@:dataClass
class NullableParameter<T> {
	public final value:Null<T>;
	public function new(value:Null<T>) this.value = value;
}

@:dataClass
class SequenceParameter<T> {
	public final value:ReadOnlyArray<T>;
	public function new(value:ReadOnlyArray<T>) this.value = value;
}

class ParameterCompositionCases {
	public static function directInt():SortedMapBuilder<ComparedParameterKey<Int>, String> return SortedMap.builder();
	public static function directString():SortedMapBuilder<ComparedParameterKey<String>, String> return SortedMap.builder();
	public static function unusedInt():SortedMapBuilder<IgnoredParameter<Int>, String> return SortedMap.builder();
	public static function unusedString():SortedMapBuilder<IgnoredParameter<String>, String> return SortedMap.builder();
	public static function nestedInt():SortedMapBuilder<NestedParameter<Int>, String> return SortedMap.builder();
	public static function nestedString():SortedMapBuilder<NestedParameter<String>, String> return SortedMap.builder();
	public static function nullableInt():SortedMapBuilder<NullableParameter<Int>, String> return SortedMap.builder();
	public static function nullableString():SortedMapBuilder<NullableParameter<String>, String> return SortedMap.builder();
	public static function sequenceInt():SortedMapBuilder<SequenceParameter<Int>, String> return SortedMap.builder();
	public static function sequenceString():SortedMapBuilder<SequenceParameter<String>, String> return SortedMap.builder();

	public static function observe():String {
		final direct:SortedMapBuilder<ComparedParameterKey<Int>, String> = directInt();
		direct.put(new ComparedParameterKey(2), "A");
		direct.put(new ComparedParameterKey(10), "B");
		final directTable = direct.build();

		final unused:SortedMapBuilder<IgnoredParameter<String>, String> = unusedString();
		unused.put(new IgnoredParameter(2), "A");
		unused.put(new IgnoredParameter(10), "B");
		final unusedTable = unused.build();

		final nested:SortedMapBuilder<NestedParameter<Int>, String> = nestedInt();
		nested.put(new NestedParameter(new NestedValue(2)), "A");
		nested.put(new NestedParameter(new NestedValue(10)), "B");
		final nestedTable = nested.build();

		final nullable:SortedMapBuilder<NullableParameter<Int>, String> = nullableInt();
		nullable.put(new NullableParameter(null), "N");
		nullable.put(new NullableParameter(2), "V");
		final nullableTable = nullable.build();

		final sequence:SortedMapBuilder<SequenceParameter<String>, String> = sequenceString();
		sequence.put(new SequenceParameter(["b"]), "B");
		sequence.put(new SequenceParameter(["a"]), "A");
		final sequenceTable = sequence.build();

		return "direct=" + directTable.valueAt(0) + directTable.valueAt(1)
			+ ";unused=" + unusedTable.valueAt(0) + unusedTable.valueAt(1)
			+ ";nested=" + nestedTable.valueAt(0) + nestedTable.valueAt(1)
			+ ";nullable=" + nullableTable.valueAt(0) + nullableTable.valueAt(1)
			+ ";sequence=" + sequenceTable.valueAt(0) + sequenceTable.valueAt(1);
	}
}
