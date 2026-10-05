package revp9;

@:dataClass
class Pair<S> {
	public final s:S;

	public function new(s:S) this.s = s;
}
