package admission;

/** Authored declarations for the finite source admission contract. Every
    declaration states one discriminator of stdlib/16 or of the finite demand
    summary. The expectations live in admission-expected.tsv and are written
    from the source rule, never from a probe run. */

/** A plain reference class. It supplies no comparison operation. */
class Reference {
	public function new() {}
}

@:dataClass
class Box<V> {
	public final value:V;

	public function new(value:V) {
		this.value = value;
	}
}

/** The parameter is never compared, so any actual for it stays irrelevant. */
@:dataClass
class Unused<T> {
	public final value:Int;

	public function new(value:Int) {
		this.value = value;
	}
}

/** A direct parameter requirement plus a recursive edge that swaps the two
    binders, so the demand reaches both slots. */
@:dataClass
class Swap<A, B> {
	public final value:A;
	public final next:Null<Swap<B, A>>;

	public function new(value:A, next:Null<Swap<B, A>>) {
		this.value = value;
		this.next = next;
	}
}

/** The recursive edge binds the demanded slot to a mutable array. */
@:dataClass
class Chain<T> {
	public final value:T;
	public final next:Null<Chain<Array<T>>>;

	public function new(value:T, next:Null<Chain<Array<T>>>) {
		this.value = value;
		this.next = next;
	}
}

/** The demanded parameter grows through a read-only sequence on the recursive
    edge, but the declaration and its slot set stay finite. */
@:dataClass
class NestedDemand<T> {
	public final value:T;
	public final next:Null<NestedDemand<std.ReadOnlyArray<T>>>;

	public function new(value:T, next:Null<NestedDemand<std.ReadOnlyArray<T>>>) {
		this.value = value;
		this.next = next;
	}
}

/** The method binder and its owner binder use the same spelling. */
class MethodBinderOwner<T> {
	public function same<T>(value:T):T {
		return value;
	}
}

/** The recursive argument grows through a read-only array and the parameter
    is never demanded, so the expanding form stays admitted. */
@:dataClass
class Expand<T> {
	public final next:Null<Expand<std.ReadOnlyArray<T>>>;

	public function new(next:Null<Expand<std.ReadOnlyArray<T>>>) {
		this.next = next;
	}
}

/** Two declarations whose demand crosses two edges and finds a mutable array
    behind the second edge. */
@:dataClass
class MutA<T> {
	public final value:T;
	public final other:Null<MutB<Box<T>>>;

	public function new(value:T, other:Null<MutB<Box<T>>>) {
		this.value = value;
		this.other = other;
	}
}

@:dataClass
class MutB<U> {
	public final item:U;
	public final back:Null<MutA<Array<U>>>;

	public function new(item:U, back:Null<MutA<Array<U>>>) {
		this.item = item;
		this.back = back;
	}
}

/** The same obligations with both field orders reversed. */
@:dataClass
class MutA2<T> {
	public final other:Null<MutB2<Box<T>>>;
	public final value:T;

	public function new(other:Null<MutB2<Box<T>>>, value:T) {
		this.other = other;
		this.value = value;
	}
}

@:dataClass
class MutB2<U> {
	public final back:Null<MutA2<Array<U>>>;
	public final item:U;

	public function new(back:Null<MutA2<Array<U>>>, item:U) {
		this.back = back;
		this.item = item;
	}
}

/** A user-authored anonymous field whose spelling copies the former binder
    prefix. The registry, never the spelling, decides binder identity. */
@:dataClass
class PrefixTrap<T> {
	public final value:{__comparison_binder_999999_0:Int};

	public function new(value:{__comparison_binder_999999_0:Int}) {
		this.value = value;
	}
}

/** Two declarations that spell their parameter `T` in one module, plus a leaf
    with its own spelling. The demand must cross both parameters and return to
    the first owner's slot. */
@:dataClass
class CrossOwner<T> {
	public final first:T;
	public final next:Null<CrossInner<T>>;

	public function new(first:T, next:Null<CrossInner<T>>) {
		this.first = first;
		this.next = next;
	}
}

@:dataClass
class CrossInner<T> {
	public final inner:T;
	public final last:Null<CrossLeaf<Box<T>>>;

	public function new(inner:T, last:Null<CrossLeaf<Box<T>>>) {
		this.inner = inner;
		this.last = last;
	}
}

@:dataClass
class CrossLeaf<Q> {
	public final leaf:Q;

	public function new(leaf:Q) {
		this.leaf = leaf;
	}
}

/** A source-authored anonymous field whose spelling copies the name the
    previous binder token minted first. Binder provenance is the owner's own
    parameter declaration, so this field stays a source anonymous structure. */
@:dataClass
class Trap<T> {
	public final value:{__comparison_binder_0_0:Int};

	public function new(value:{__comparison_binder_0_0:Int}) {
		this.value = value;
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
class GenericValue<T> {
	public final value:T;

	public function new(value:T) {
		this.value = value;
	}
}

// A chain deeper than the former test-only 24-node analysis limit. Each step
// is a distinct declaration, so admission visits 28 declarations and no
// instantiation becomes a node.
@:dataClass
class Step0 {
	public final next:Null<Step1>;

	public function new(next:Null<Step1>) {
		this.next = next;
	}
}
@:dataClass
class Step1 {
	public final next:Null<Step2>;

	public function new(next:Null<Step2>) {
		this.next = next;
	}
}
@:dataClass
class Step2 {
	public final next:Null<Step3>;

	public function new(next:Null<Step3>) {
		this.next = next;
	}
}
@:dataClass
class Step3 {
	public final next:Null<Step4>;

	public function new(next:Null<Step4>) {
		this.next = next;
	}
}
@:dataClass
class Step4 {
	public final next:Null<Step5>;

	public function new(next:Null<Step5>) {
		this.next = next;
	}
}
@:dataClass
class Step5 {
	public final next:Null<Step6>;

	public function new(next:Null<Step6>) {
		this.next = next;
	}
}
@:dataClass
class Step6 {
	public final next:Null<Step7>;

	public function new(next:Null<Step7>) {
		this.next = next;
	}
}
@:dataClass
class Step7 {
	public final next:Null<Step8>;

	public function new(next:Null<Step8>) {
		this.next = next;
	}
}
@:dataClass
class Step8 {
	public final next:Null<Step9>;

	public function new(next:Null<Step9>) {
		this.next = next;
	}
}
@:dataClass
class Step9 {
	public final next:Null<Step10>;

	public function new(next:Null<Step10>) {
		this.next = next;
	}
}
@:dataClass
class Step10 {
	public final next:Null<Step11>;

	public function new(next:Null<Step11>) {
		this.next = next;
	}
}
@:dataClass
class Step11 {
	public final next:Null<Step12>;

	public function new(next:Null<Step12>) {
		this.next = next;
	}
}
@:dataClass
class Step12 {
	public final next:Null<Step13>;

	public function new(next:Null<Step13>) {
		this.next = next;
	}
}
@:dataClass
class Step13 {
	public final next:Null<Step14>;

	public function new(next:Null<Step14>) {
		this.next = next;
	}
}
@:dataClass
class Step14 {
	public final next:Null<Step15>;

	public function new(next:Null<Step15>) {
		this.next = next;
	}
}
@:dataClass
class Step15 {
	public final next:Null<Step16>;

	public function new(next:Null<Step16>) {
		this.next = next;
	}
}
@:dataClass
class Step16 {
	public final next:Null<Step17>;

	public function new(next:Null<Step17>) {
		this.next = next;
	}
}
@:dataClass
class Step17 {
	public final next:Null<Step18>;

	public function new(next:Null<Step18>) {
		this.next = next;
	}
}
@:dataClass
class Step18 {
	public final next:Null<Step19>;

	public function new(next:Null<Step19>) {
		this.next = next;
	}
}
@:dataClass
class Step19 {
	public final next:Null<Step20>;

	public function new(next:Null<Step20>) {
		this.next = next;
	}
}
@:dataClass
class Step20 {
	public final next:Null<Step21>;

	public function new(next:Null<Step21>) {
		this.next = next;
	}
}
@:dataClass
class Step21 {
	public final next:Null<Step22>;

	public function new(next:Null<Step22>) {
		this.next = next;
	}
}
@:dataClass
class Step22 {
	public final next:Null<Step23>;

	public function new(next:Null<Step23>) {
		this.next = next;
	}
}
@:dataClass
class Step23 {
	public final next:Null<Step24>;

	public function new(next:Null<Step24>) {
		this.next = next;
	}
}
@:dataClass
class Step24 {
	public final next:Null<Step25>;

	public function new(next:Null<Step25>) {
		this.next = next;
	}
}
@:dataClass
class Step25 {
	public final next:Null<Step26>;

	public function new(next:Null<Step26>) {
		this.next = next;
	}
}
@:dataClass
class Step26 {
	public final next:Null<Step27>;

	public function new(next:Null<Step27>) {
		this.next = next;
	}
}
@:dataClass
class Step27 {
	public final value:Int;

	public function new(value:Int) {
		this.value = value;
	}
}
