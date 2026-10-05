#if macro
import haxe.macro.Compiler;

/** Registers the one-shot build probe as a global @:build, the same
    mechanism packages/compiler/Intercept.hx uses. The probe guards on the
    local class and runs exactly once (on revp9.Trigger). */
class Setup {
	public static function run():Void {
		Compiler.addGlobalMetadata("", "@:build(DedupProbe.run())", true, true);
	}
}
#end
