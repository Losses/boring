package boring;

#if rust_output
/**
    A concrete implementor passed to an optional interface parameter. The
    argument boundary adds the Option wrapper, and the fresh constructor
    boxes once into the trait object. An argument already typed as the
    interface carries its own box, so it only wraps; a nullable interface
    local keeps its Option shape.
*/
interface OptionalArgShape {
    function describe():String;
}

class OptionalArgCircle implements OptionalArgShape {
    public function new() {}

    public function describe():String {
        return "circle";
    }
}

class OptionalArgSquare implements OptionalArgShape {
    public function new() {}

    public function describe():String {
        return "square";
    }
}

class OptionalInterfaceArgumentOps {
    public static function render(?shape:OptionalArgShape):String {
        return shape == null ? "none" : shape.describe();
    }

    public static function renderFresh():String {
        return render(new OptionalArgCircle());
    }

    public static function renderLocal(shape:OptionalArgShape):String {
        return render(shape);
    }

    public static function renderNullableLocal(shape:Null<OptionalArgShape>):String {
        return render(shape);
    }

    public static function makeSquare():OptionalArgShape {
        return new OptionalArgSquare();
    }
}
#else
class OptionalInterfaceArgumentOps {}
#end
