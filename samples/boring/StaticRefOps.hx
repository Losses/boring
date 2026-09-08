package boring;

// Static methods used as values: Kotlin callable-reference sites (tattr3 r1).
// A statics-only class mirrors the std.SortedTable shape where a static
// method is referenced without being called.

class StaticRefStatics {
    public static function compareStrings(a:String, b:String):Int {
        return a.length - b.length;
    }
}

class StaticRefOps {
    public static function render(code:Int):String {
        return "code:" + code;
    }

    public static function takeFn(callback:(code:Int) -> String):String {
        return callback(42);
    }

    // Argument position: static method passed to a function-typed parameter.
    public static function passToParam():String {
        return takeFn(render);
    }

    // Local declaration position: static method bound to a function-typed local.
    public static function storeLocal():String {
        final fn:(code:Int) -> String = render;
        return fn(42);
    }

    // Return position: static method returned as a function value.
    public static function returnFn():(code:Int) -> String {
        return render;
    }

    // Assignment position: static method assigned to a function-typed local.
    public static function reassignLocal():String {
        var fn:(code:Int) -> String = render;
        fn = render;
        return fn(42);
    }

    // Statics-only class: static method used as a value.
    public static function staticsOnlyValue():Int {
        final cmp:(a:String, b:String) -> Int = StaticRefStatics.compareStrings;
        return cmp("ab", "a");
    }

    // Call-site control: the same static method invoked, output must not change.
    public static function callSite():String {
        return render(42);
    }
}
