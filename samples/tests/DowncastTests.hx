package tests;

import std.Test;

#if swift_output
import boring.DowncastOps;
#end

class DowncastTests {
    @:test("a checked downcast keeps the concrete type")
    public static function testDowncast():Void {
        #if swift_output
        final animals = DowncastOps.sampleAnimals();
        Test.equals(4, DowncastOps.legs(animals[0]));
        Test.equals(0, DowncastOps.legs(animals[1]));
        Test.equals(0, DowncastOps.lives(animals[0]));
        Test.equals(9, DowncastOps.lives(animals[1]));
        #else
        Test.equals(true, true);
        #end
    }
}
