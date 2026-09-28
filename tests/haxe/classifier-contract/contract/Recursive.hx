package contract;

/**
 * Recursive declarations. Their field and constructor types are the places
 * where the compiler may retain a lazy type in the public macro API; the
 * probe reports whether any lazy type survives typing here.
 */
class Recursive {
	public var self:Recursive;
	public var items:Array<Recursive>;

	public function new() {
		self = this;
		items = [];
	}
}
