package org.tiqian.protocol;

/**
 * The NamedError family's golden name assertions (features/06-errors-and-
 * results.md:397: tests assert variant identity, never message content —
 * here the identity is the published name itself). The golden list and the
 * position-to-variant mapping live in NamedErrorTestSupport; the two tests
 * pin that the generated variant list and the describe mapping carry the
 * published names, in check order, with no duplicate. The rust target
 * renders the exception payload enum without the Copy derive, so the
 * assertions pass fresh constructor values (variantAt) instead of moving
 * them out of the variants vector index.
 */
class NamedErrorTest {
    @:test
    public static function theVariantListMatchesThePublishedNamesInCheckOrder():Void {
        final recorder = new org.tiqian.test.trace.TestTraceRecorder("NamedErrorTest");
        recorder.section("theVariantListMatchesThePublishedNamesInCheckOrder");
        final variants = NamedErrorNames.variants();
        final names:Array<String> = [];
        var indexIdx:Int = 0;
        while (indexIdx < variants.length) {
            names.push(NamedErrorNames.describe(NamedErrorTestSupport.variantAt(indexIdx)));
            org.tiqian.test.trace.TracedAssertions.assertTrue(
                variants[indexIdx] == NamedErrorTestSupport.variantAt(indexIdx),
                "the variant list order drifts from the declaration order");
            indexIdx++;
        }
        org.tiqian.test.trace.TracedAssertions.assertEquals(
            NamedErrorTestSupport.golden().length, variants.length,
            "the family has the 21 published names");
        org.tiqian.test.trace.TracedAssertions.assertEqualsStringArray(
            NamedErrorTestSupport.golden(), names);
    }

    @:test
    public static function thePublishedNamesAreAllDistinct():Void {
        final recorder = new org.tiqian.test.trace.TestTraceRecorder("NamedErrorTest");
        recorder.section("thePublishedNamesAreAllDistinct");
        final variants = NamedErrorNames.variants();
        var outerIdx:Int = 0;
        while (outerIdx < variants.length) {
            var innerIdx:Int = outerIdx + 1;
            while (innerIdx < variants.length) {
                org.tiqian.test.trace.TracedAssertions.assertTrue(
                    NamedErrorNames.describe(NamedErrorTestSupport.variantAt(outerIdx)) != NamedErrorNames.describe(NamedErrorTestSupport.variantAt(innerIdx)),
                    "two variants publish the same name");
                innerIdx++;
            }
            outerIdx++;
        }
    }
}
