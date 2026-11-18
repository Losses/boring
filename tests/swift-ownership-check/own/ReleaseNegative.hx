package own;

import ptr.CFString;

extern class BadRelease {
    @:topLevel
    static function CFRelease(value:CFString):Void;
}

class ReleaseNegative {
    public static function main():Void {
        BadRelease.CFRelease("x");
    }
}
