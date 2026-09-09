package tests;

import boring.ResidentModuleImportOps;
import std.Test;

/**
    Assertion coverage for direct module-path imports of a resident
    runtime module (docs/specs/features/14). The TypeScript backend must
    emit the resident at its module path so the relative import resolves.
**/
class ResidentModuleImportTests {
	@:test("resident module imports resolve on their own module path")
	public static function testResidentModuleImport():Void {
		Test.equals(100, ResidentModuleImportOps.mapLookup(), "map lookup through resident module-path import");
	}
}