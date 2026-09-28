package place;

import std.Console;

/**
	Haxe runner entry for the paired module. It calls the generated
	operations; it implements none of them.
**/
class PlaceStaticMain {
	static function main():Void {
		Console.log("[paired] start");
		new PlaceObserveStatic().run();
		Console.log("[paired] end");
	}
}
