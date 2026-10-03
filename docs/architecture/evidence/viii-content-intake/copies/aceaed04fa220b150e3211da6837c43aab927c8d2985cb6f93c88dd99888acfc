package revp9;

/** Two nested Pair<T> fields sharing one type parameter, no bare T field:
    isolates Builder.sameTypeParameter dedup inside one Builder. */
@:dataClass
class Boxed<T> {
	public final child:Null<Pair<T>>;
	public final pair:Pair<T>;

	public function new(child:Null<Pair<T>>, pair:Pair<T>) {
		this.child = child;
		this.pair = pair;
	}
}
