package tests;

import boring.RecordInterfaceOps;
import boring.RecordInterfaceOps.Background;
import boring.RecordInterfaceOps.Link;
import boring.RecordInterfaceOps.RichTextSpan;
import std.RecordStr;
import std.Test;

class RecordInterfaceOpsTests {
    @:test("a singleton interface field prints its bare name")
    public static function singletonRole():Void {
        Test.equals("Background", Background.instance.toString());
        final span = RecordInterfaceOps.singletonSpan();
        Test.equals("RichTextSpan(role=Background, note=null)", span.toString());
        Test.equals(RecordStr.str(span), span.toString());
    }

    @:test("a record interface field prints its labeled form")
    public static function recordRole():Void {
        Test.equals("Link(target=tiqian)", new Link("tiqian").toString());
        final span = RecordInterfaceOps.recordSpan();
        Test.equals("RichTextSpan(role=Link(target=tiqian), note=Background)", span.toString());
        Test.equals(RecordStr.str(span), span.toString());
    }

    @:test("a present nullable interface field prints its member text")
    public static function presentNote():Void {
        final span = new RichTextSpan(Background.instance, new Link("note"));
        Test.equals("RichTextSpan(role=Background, note=Link(target=note))", span.toString());
        Test.equals(RecordStr.str(span), span.toString());
    }
}
