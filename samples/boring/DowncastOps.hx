package boring;

#if swift_output
@:sealed
interface Animal {
    function name():String;
}

class Dog implements Animal {
    public final legs:Int;

    public function new(legs:Int) {
        this.legs = legs;
    }

    public function name():String {
        return "dog";
    }
}

class Cat implements Animal {
    public final lives:Int;

    public function new(lives:Int) {
        this.lives = lives;
    }

    public function name():String {
        return "cat";
    }
}

/**
    A checked downcast `cast(a, Dog)` narrows an interface value to the
    concrete class. Swift needs `a as! Dog`; dropping the cast leaves the
    protocol value, which has no member for the concrete fields.
*/
class DowncastOps {
    public static function sampleAnimals():Array<Animal> {
        return [new Dog(4), new Cat(9)];
    }

    public static function legs(a:Animal):Int {
        if (Std.isOfType(a, Dog)) {
            final dog:Dog = cast(a, Dog);
            return dog.legs;
        }
        return 0;
    }

    public static function lives(a:Animal):Int {
        if (Std.isOfType(a, Cat)) {
            final cat:Cat = cast(a, Cat);
            return cat.lives;
        }
        return 0;
    }
}
#else
class DowncastOps {}
#end
