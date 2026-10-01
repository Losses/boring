// Admission probe B (task t-mum0wts5-jh3m): the default expression E of a
// coalescing default is a throwable static call (throwingG in this same file;
// it throws an enum-carried exception when seed exceeds the threshold).
// Expected: accepted (rc=0, empty output): the spec 22 Stage-A static-call
// syntax root does not check the fallibility of the called function, and
// DefaultArgExpander.validateCoalescingGrammar rule 6 is a purely syntactic
// judgment. main omits the value argument to trigger default evaluation.
// Compile command: see the admit-coalescing-throwing stage in run.sh.
enum ProbeFault {
	OverLimit(seed:Int);
}

class ProbeException extends haxe.Exception {
	public final fault:ProbeFault;

	public function new(fault:ProbeFault) {
		this.fault = fault;
		super(switch (fault) {
			case OverLimit(seed): 'over limit: $seed';
		});
	}
}

class PCoalescingThrowing {
	static function main() {
		use(1);
	}

	static function throwingG(seed:Int):Int {
		if (seed > 10) {
			throw new ProbeException(OverLimit(seed));
		}
		return seed * 2;
	}

	static function use(seed:Int, ?value:Int):Int {
		var normalized = value == null ? throwingG(seed) : value;
		return normalized;
	}
}
