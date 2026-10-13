package tprobe;

import std.Fs;

/**
    P6.6 probe: a fallible std.Fs call inside a test module.

    The test module (a @:test class) is emitted in-crate under "#![cfg(test)]"
    inside the SAME rust-output root and the SAME Intercept roots as the main
    scope -- Rust has no separate test-output directory.  readText() is
    uncaught, so its error slot resolves through the std.FsError payload enum.

    When samples/std is outside Intercept scope that payload enum has no
    declaration site: post-P6.4 generation fails with the domain diagnostic,
    and pre-P6.4 the fallback module "std.FsException" produced an unresolved
    crate::std::fs_exception reference (round-2 E0432/E0433).
**/
class RustGenTestsProbe {
    @:test("fallible std.Fs.readText call inside a test module")
    public static function fsReadTextInTestModule():Void {
        Fs.readText("probe.txt");
    }
}
