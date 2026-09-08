package boring;

interface TraitSignOps {
    function name():String;
    function risky(value:Int):Int;
    function bump():Int;
}

class TraitSignImpl implements TraitSignOps {
    public var count:Int;

    public function new() {
        count = 0;
    }

    public function name():String {
        return "trait";
    }

    public function risky(value:Int):Int {
        if (value < 0) {
            throw new VectorException(VectorError.CountOverflow);
        }
        return value;
    }

    public function bump():Int {
        count = count + 1;
        return count;
    }
}

class TraitSignOpsRunner {
    public static function run():String {
        final value:TraitSignOps = new TraitSignImpl();
        return value.name() + ":" + value.bump();
    }
}
