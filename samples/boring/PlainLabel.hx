package boring;

class PlainLabel {
    public final text:String;
    public final width:Int;

    public function new(text:String, width:Int) {
        this.text = text;
        this.width = width;
    }

    public function toString():String {
        return "PlainLabel(text=" + text + ", width=" + width + ")";
    }
}
