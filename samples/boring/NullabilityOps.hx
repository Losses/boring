package boring;

class NullabilityOps {
    public static function nullableToString(value:Null<NullableReceiver>):String {
        return value.toString();
    }
    
    public static function nullableToStringWithParam(value:Null<NullableReceiver>, suffix:String):String {
        return value.toString() + suffix;
    }

    #if kotlin_output
    public static function narrowedFloat(values:Array<Null<Float>>, index:Int):Float {
        final value:Float = values[index] == null ? 0 : values[index];
        return value;
    }

    public static function ctorFieldLabel(label:Null<String>):Null<String> {
        return new NullableLabelHolder(label).render();
    }
    #end
}

#if kotlin_output
class NullableLabelHolder {
    private final label:String;

    public function new(?label:String) {
        this.label = label;
    }

    public function render():String {
        return this.label.toUpperCase();
    }
}
#end
