package admission.names.first;

/** One of two record declarations that share one short name. The reference
    path `first.Point -> second.Point` is acyclic, so admission must visit two
    declarations and admit. An identity taken from the short name would read
    the child edge as a return to this declaration and reject. */
@:dataClass
class Point<T> {
	public final child:Null<admission.names.second.Point<T>>;
	public final value:T;

	public function new(child:Null<admission.names.second.Point<T>>, value:T) {
		this.child = child;
		this.value = value;
	}
}
