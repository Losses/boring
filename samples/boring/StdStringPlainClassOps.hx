package boring;

class PlainPoint {
    public final x:Int;
    public final y:Int;

    public function new(x:Int, y:Int) {
        this.x = x;
        this.y = y;
    }

    public function toString():String {
        return "Point(" + x + "," + y + ")";
    }
}

@:dataClass
class PlainClassRecord {
    public final point:PlainPoint;
    public final points:Array<PlainPoint>;

    public function new(point:PlainPoint, points:Array<PlainPoint>) {
        this.point = point;
        this.points = points;
    }
}
