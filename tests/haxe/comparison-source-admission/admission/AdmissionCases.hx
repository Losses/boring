package admission;

/** Authored declarations for the finite source admission check. Every
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

/** Two demanded parameters, so a recursive alias can demand one slot directly
    and a second slot only through its own recursive edge. */
@:dataClass
class Pair<X, Y> {
	public final first:X;
	public final second:Y;

	public function new(first:X, second:Y) {
		this.first = first;
		this.second = second;
	}
}

/** The legal recursive alias. The host accepts the declaration, the outer
    `Null` is written, and the only recursive occurrence sits behind the `Box`
    application, so the alias application closes on its own declaration instead
    of being substituted again with one more layer per round. */
typedef Grow<T> = Null<Box<Grow<Array<T>>>>;

/** A demanded slot and a growing recursive edge in one declaration. The slot
    set stays `[0]`, so the growth lives on the edge and never in the graph. */
@:dataClass
class ExpandDemand<T> {
	public final value:T;
	public final next:Null<ExpandDemand<std.ReadOnlyArray<T>>>;

	public function new(value:T, next:Null<ExpandDemand<std.ReadOnlyArray<T>>>) {
		this.value = value;
		this.next = next;
	}
}

/** The alias form of `Chain`. The recursive alias edge carries the demanded
    `Pair` slot, and its own actual binds that slot to a mutable array at the
    second unfolding, so the declaration rejects on its own state. */
typedef AliasChain<A, B> = Pair<A, AliasChain<B, Array<A>>>;

/** A recursive alias whose demanded slot stays comparable on the recursive
    edge, so demand crosses the alias node twice and the declaration admits. */
typedef AliasLoop<T> = Pair<T, AliasLoop<Box<T>>>;

/** A non-recursive alias whose body carries the demand, so the demand has to
    be solved over the alias declaration to reach the slot at all. */
typedef AliasDemand<T> = Box<T>;

// An acyclic alias chain one hop deeper per declaration. Each step is a
// distinct alias declaration, so admission enters 80 distinct heads and still
// reaches the mutable array at the end with no cap and no cycle.
typedef Hop01<T> = Hop02<Array<T>>;
typedef Hop02<T> = Hop03<Array<T>>;
typedef Hop03<T> = Hop04<Array<T>>;
typedef Hop04<T> = Hop05<Array<T>>;
typedef Hop05<T> = Hop06<Array<T>>;
typedef Hop06<T> = Hop07<Array<T>>;
typedef Hop07<T> = Hop08<Array<T>>;
typedef Hop08<T> = Hop09<Array<T>>;
typedef Hop09<T> = Hop10<Array<T>>;
typedef Hop10<T> = Hop11<Array<T>>;
typedef Hop11<T> = Hop12<Array<T>>;
typedef Hop12<T> = Hop13<Array<T>>;
typedef Hop13<T> = Hop14<Array<T>>;
typedef Hop14<T> = Hop15<Array<T>>;
typedef Hop15<T> = Hop16<Array<T>>;
typedef Hop16<T> = Hop17<Array<T>>;
typedef Hop17<T> = Hop18<Array<T>>;
typedef Hop18<T> = Hop19<Array<T>>;
typedef Hop19<T> = Hop20<Array<T>>;
typedef Hop20<T> = Hop21<Array<T>>;
typedef Hop21<T> = Hop22<Array<T>>;
typedef Hop22<T> = Hop23<Array<T>>;
typedef Hop23<T> = Hop24<Array<T>>;
typedef Hop24<T> = Hop25<Array<T>>;
typedef Hop25<T> = Hop26<Array<T>>;
typedef Hop26<T> = Hop27<Array<T>>;
typedef Hop27<T> = Hop28<Array<T>>;
typedef Hop28<T> = Hop29<Array<T>>;
typedef Hop29<T> = Hop30<Array<T>>;
typedef Hop30<T> = Hop31<Array<T>>;
typedef Hop31<T> = Hop32<Array<T>>;
typedef Hop32<T> = Hop33<Array<T>>;
typedef Hop33<T> = Hop34<Array<T>>;
typedef Hop34<T> = Hop35<Array<T>>;
typedef Hop35<T> = Hop36<Array<T>>;
typedef Hop36<T> = Hop37<Array<T>>;
typedef Hop37<T> = Hop38<Array<T>>;
typedef Hop38<T> = Hop39<Array<T>>;
typedef Hop39<T> = Hop40<Array<T>>;
typedef Hop40<T> = Hop41<Array<T>>;
typedef Hop41<T> = Hop42<Array<T>>;
typedef Hop42<T> = Hop43<Array<T>>;
typedef Hop43<T> = Hop44<Array<T>>;
typedef Hop44<T> = Hop45<Array<T>>;
typedef Hop45<T> = Hop46<Array<T>>;
typedef Hop46<T> = Hop47<Array<T>>;
typedef Hop47<T> = Hop48<Array<T>>;
typedef Hop48<T> = Hop49<Array<T>>;
typedef Hop49<T> = Hop50<Array<T>>;
typedef Hop50<T> = Hop51<Array<T>>;
typedef Hop51<T> = Hop52<Array<T>>;
typedef Hop52<T> = Hop53<Array<T>>;
typedef Hop53<T> = Hop54<Array<T>>;
typedef Hop54<T> = Hop55<Array<T>>;
typedef Hop55<T> = Hop56<Array<T>>;
typedef Hop56<T> = Hop57<Array<T>>;
typedef Hop57<T> = Hop58<Array<T>>;
typedef Hop58<T> = Hop59<Array<T>>;
typedef Hop59<T> = Hop60<Array<T>>;
typedef Hop60<T> = Hop61<Array<T>>;
typedef Hop61<T> = Hop62<Array<T>>;
typedef Hop62<T> = Hop63<Array<T>>;
typedef Hop63<T> = Hop64<Array<T>>;
typedef Hop64<T> = Hop65<Array<T>>;
typedef Hop65<T> = Hop66<Array<T>>;
typedef Hop66<T> = Hop67<Array<T>>;
typedef Hop67<T> = Hop68<Array<T>>;
typedef Hop68<T> = Hop69<Array<T>>;
typedef Hop69<T> = Hop70<Array<T>>;
typedef Hop70<T> = Hop71<Array<T>>;
typedef Hop71<T> = Hop72<Array<T>>;
typedef Hop72<T> = Hop73<Array<T>>;
typedef Hop73<T> = Hop74<Array<T>>;
typedef Hop74<T> = Hop75<Array<T>>;
typedef Hop75<T> = Hop76<Array<T>>;
typedef Hop76<T> = Hop77<Array<T>>;
typedef Hop77<T> = Hop78<Array<T>>;
typedef Hop78<T> = Hop79<Array<T>>;
typedef Hop79<T> = Hop80<Array<T>>;
typedef Hop80<T> = Array<T>;

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
