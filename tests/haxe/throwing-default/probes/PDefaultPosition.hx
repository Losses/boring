// Admission probe A (task t-mum0wts5-jh3m): a call placed directly in the
// default position. Expected: rejected with the named error "default argument
// values accept compile-time constants only" (spec 22 rule 1 / style standard
// V16 NonConstantDefault row). Compile command: see the admit-default-position
// stage in run.sh (full pipeline: -lib reflaxe -lib boring + Intercept.run).
class PDefaultPosition {
	static function main() {
		use(1);
	}

	static function g(x:Int):Int {
		return x * 2;
	}

	static function use(p:Int = g(2)):Int {
		return p;
	}
}
