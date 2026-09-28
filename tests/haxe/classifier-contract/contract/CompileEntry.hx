package contract;

/**
 * Ordinary Haxe compile entry that references the fixture declarations so
 * the full typer covers them. It establishes source acceptance of the
 * fixture as a stage distinct from the macro probe's context observation:
 * docs/compiler-problem-analysis.md records source acceptance separately
 * from a stage's observation, and a successful ordinary compile is that
 * acceptance record. It performs no Boring generation and no target
 * compilation.
 */
class CompileEntry {
	public static function main():Void {
		final fixtures = new Fixtures();
		final recursive = new Recursive();
		trace(fixtures.instPlainArray.length);
		trace(recursive.items.length);
	}
}
