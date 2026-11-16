package tests;

import std.Test;

#if swift_output
import boring.ExtensionSliceMinOps;
#end
#if (swift_output || dart_output)
import boring.ValueTypeStaticMemberOps;
#end
#if (swift_output || dart_output || kotlin_output || rust_output)
import boring.ValueTypeAccessorReadOps;
#end
#if dart_output
import boring.ExtensionLibraryGroupOps;
import boring.ExtensionLibraryGroupOps.ExtensionGroupMode;
import boring.ExtensionMemberCollisionOps;
import boring.ExtensionMemberCollisionOps.ExtensionCollisionMode;
import boring.NarrowedLocalDeclarationOps;
#end
#if kotlin_output
import boring.RecordFieldHopNonNull;
import boring.RecordFieldHopNonNull.RecordFieldHopRow;
#end
#if rust_output
import boring.SharedStaticPublishOps;
#end

/**
    Runtime hooks for the consumer shapes. Each function reads one shape
    that the samples did not previously emit; the fixed targets run the real
    value and the other targets register the same id with a passing no-op, so
    the cross-target test id set stays equal.
**/
class ConsumerShapeCorpusTests {
    @:test("corpus: Swift extension body qualifies the global min")
    public static function extensionSliceMin():Void {
        #if swift_output
        Test.equals("bc", ExtensionSliceMinOps.cut([1, 2], "abcd", 1, 3));
        #else
        Test.equals(true, true);
        #end
    }

    @:test("corpus: value type static factory and throwing member")
    public static function valueTypeStaticMember():Void {
        #if (swift_output || dart_output)
        Test.equals("face", ValueTypeStaticMemberOps.describe("face"));
        Test.equals(4, ValueTypeStaticMemberOps.plainUnits("abcd"));
        Test.equals(true, ValueTypeStaticMemberOps.rejectsBlank(" "));
        #else
        Test.equals(true, true);
        #end
    }

    @:test("corpus: value type accessor read unboxes at the representation site")
    public static function valueTypeAccessorRead():Void {
        #if (swift_output || dart_output || kotlin_output || rust_output)
        Test.equals("[ab]", ValueTypeAccessorReadOps.passArgumentFrom("ab"));
        Test.equals("ab", ValueTypeAccessorReadOps.returnFrom("ab"));
        Test.equals("cd", ValueTypeAccessorReadOps.initializeFrom("cd"));
        Test.equals("fg", ValueTypeAccessorReadOps.factoryRead("fg"));
        #else
        Test.equals(true, true);
        #end
    }

    @:test("corpus: Dart groups extension declarations per library")
    public static function extensionLibraryGroup():Void {
        #if dart_output
        Test.equals("p:cold/cold!", ExtensionLibraryGroupOps.describe(ExtensionGroupMode.Cold));
        Test.equals("p:hot/hot!", ExtensionLibraryGroupOps.describe(ExtensionGroupMode.Hot));
        #else
        Test.equals(true, true);
        #end
    }

    @:test("corpus: Dart colliding extension member keeps its declaring class")
    public static function extensionMemberCollision():Void {
        #if dart_output
        Test.equals("cold/cold!", ExtensionMemberCollisionOps.describe(ExtensionCollisionMode.Cold));
        Test.equals("hot/hot!", ExtensionMemberCollisionOps.describe(ExtensionCollisionMode.Hot));
        #else
        Test.equals(true, true);
        #end
    }

    @:test("corpus: Dart narrowed local declares the non-null type")
    public static function narrowedLocalDeclaration():Void {
        #if dart_output
        Test.equals(2.5, NarrowedLocalDeclarationOps.guardedEdge(2.5));
        Test.equals(0.0, NarrowedLocalDeclarationOps.guardedEdge(null));
        Test.equals(2.0, NarrowedLocalDeclarationOps.stretched(2.0));
        Test.equals(Math.POSITIVE_INFINITY, NarrowedLocalDeclarationOps.stretched(null));
        Test.equals(3.0, NarrowedLocalDeclarationOps.passedToParameter(3.0));
        Test.equals(-1.0, NarrowedLocalDeclarationOps.passedToParameter(null));
        #else
        Test.equals(true, true);
        #end
    }

    @:test("corpus: Kotlin nullable record hop keeps the argument non-null")
    public static function nullableRecordHop():Void {
        #if kotlin_output
        final row:RecordFieldHopRow = { items: ["a", "bb"] };
        Test.equals(2, RecordFieldHopNonNull.readLength(row));
        Test.equals(2, RecordFieldHopNonNull.readLengthArgument(row));
        #else
        Test.equals(true, true);
        #end
    }

    @:test("corpus: Rust shared static publishes one complete value")
    public static function sharedStaticPublish():Void {
        #if rust_output
        SharedStaticPublishOps.reset();
        Test.equals(1, SharedStaticPublishOps.peek(0));
        Test.equals(531441, SharedStaticPublishOps.valueAt(12));
        Test.equals(531441, SharedStaticPublishOps.peek(12));
        SharedStaticPublishOps.reset();
        Test.equals(9, SharedStaticPublishOps.valueAt(2));
        #else
        Test.equals(true, true);
        #end
    }
}
