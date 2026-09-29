package dartcomparison;

@:dataClass
class MultiKey {
    public final first:Int;
    public final optional:Null<Int>;
    public final values:std.ReadOnlyArray<Int>;

    public function new(first:Int, optional:Null<Int>, values:std.ReadOnlyArray<Int>) {
        this.first = first;
        this.optional = optional;
        this.values = values;
    }
}

@:dataClass
class NullableElementsKey {
    public final values:std.ReadOnlyArray<Null<Int>>;
    public function new(values:std.ReadOnlyArray<Null<Int>>) this.values = values;
}

@:dataClass
class ChainKey {
    public final value:Int;
    public final next:Null<ChainKey>;

    public function new(value:Int, next:Null<ChainKey>) {
        this.value = value;
        this.next = next;
    }
}

@:dataClass
class NullSequenceCrossKey {
    public final values:Null<std.ReadOnlyArray<dartcomparison.left.Same>>;
    public function new(values:Null<std.ReadOnlyArray<dartcomparison.left.Same>>) this.values = values;
}

class ComparisonCases {}
