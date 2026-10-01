enum GapChoiceO { One; Two; }

class OracleMain {
	static function sourceFirst():Array<Int> return [1, 2];
	static function sourceSecond():Array<Int> return [3];

	static function switchExplicitReturn(choice:GapChoiceO):Array<Int> {
		switch (choice) {
			case One: return sourceFirst();
			case Two: return sourceSecond();
		}
		return sourceFirst();
	}

	static function switchReturnPosition(choice:GapChoiceO):Array<Int> {
		return switch (choice) {
			case One: sourceFirst();
			case Two: sourceSecond();
		}
	}

	static function main() {
		Sys.println("explicitReturn(one).length=" + switchExplicitReturn(One).length);
		Sys.println("explicitReturn(two).length=" + switchExplicitReturn(Two).length);
		Sys.println("switchReturnPosition(one).length=" + switchReturnPosition(One).length);
		Sys.println("switchReturnPosition(two).length=" + switchReturnPosition(Two).length);
	}
}
