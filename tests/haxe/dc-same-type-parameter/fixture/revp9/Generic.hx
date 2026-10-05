package revp9;

@:dataClass
class Generic<T> {
	public final value:T;

	public function new(value:T) this.value = value;
}
