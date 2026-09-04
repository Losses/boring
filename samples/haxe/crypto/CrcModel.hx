package haxe.crypto;

class CrcModel {
    public var width:Int;
    public var poly:Int;
    public var init:Int;
    public var refin:Bool;
    public var refout:Bool;
    public var xorout:Int;

    public function new(width:Int, poly:Int, init:Int, refin:Bool, refout:Bool, xorout:Int) {
        this.width = width;
        this.poly = poly;
        this.init = init;
        this.refin = refin;
        this.refout = refout;
        this.xorout = xorout;
    }
}
