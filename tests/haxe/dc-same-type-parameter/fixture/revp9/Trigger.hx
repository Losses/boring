package revp9;

/** Forces Pair/Boxed/Generic to be COMPILED (not lazy-loaded) before the
    global build macro runs the dedup probes. */
class Trigger {
	public final g:Generic<Int>;
	public final b:Boxed<String>;

	public function new(g:Generic<Int>, b:Boxed<String>) {
		this.g = g;
		this.b = b;
	}
}
