package admission.names.second;

/** The other declaration named `Point`. It stores one comparable field, so it
    supplies the leaf of the path that starts at `first.Point`. */
@:dataClass
class Point<U> {
	public final value:U;

	public function new(value:U) {
		this.value = value;
	}
}
