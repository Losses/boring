package boring;

typedef InnerNote = {label:String, weight:Int};
typedef ValueCard = {title:String, tags:Array<String>, note:InnerNote};

class ValuePassingOps {
    public static function readTwoFields(card:ValueCard):String {
        var first:String = card.title;
        var second:String = card.title;
        return first + "|" + second;
    }

    public static function passTwice(card:ValueCard):Int {
        var a:Int = tagCount(card);
        var b:Int = tagCount(card);
        return a + b;
    }

    static function tagCount(card:ValueCard):Int {
        return card.tags.length;
    }

    public static function forwardParameter(tags:Array<String>):Int {
        return countAll(tags);
    }

    static function countAll(tags:Array<String>):Int {
        var total:Int = 0;
        for (i in 0...tags.length)
            total = total + tags[i].length;
        return total;
    }

    public static function pushThrough(tags:Array<String>):String {
        appendOne(tags);
        return tags[tags.length - 1];
    }

    static function appendOne(tags:Array<String>):Void {
        tags.push("added");
    }

    public static function lengthArithmetic(text:String):Int {
        var n:Int = text.length;
        return n * 2 + 1;
    }

    public static function buildCard():ValueCard {
        var inner:InnerNote = {label: "note", weight: 2};
        return {title: "card", tags: ["alpha", "beta"], note: inner};
    }
}
