package boring;

class FieldGuardBox {
    public final width:Float;
    public final height:Float;
    public function new(width:Float, height:Float) {
        this.width = width;
        this.height = height;
    }
}

class FieldGuardHolder {
    public final box:Null<FieldGuardBox>;
    public function new(?box:Null<FieldGuardBox>) {
        this.box = box;
    }
}

class FieldGuardOps {
    public static function area():Float {
        final holder = new FieldGuardHolder(new FieldGuardBox(3.0, 4.0));
        if (holder.box != null) {
            final box:FieldGuardBox = holder.box;
            return box.width * box.height;
        }
        return 0.0;
    }

    public static function emptyArea():Float {
        final holder = new FieldGuardHolder(null);
        if (holder.box != null) {
            final box:FieldGuardBox = holder.box;
            return box.width * box.height;
        }
        return 0.0;
    }
}
