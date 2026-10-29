package org.tiqian.protocol;

import org.tiqian.test.trace.TracedAssertions;

/**
 * Drift-prevention assertion for PlanSchema against Revision (Stage1-P3).
 * PLAN_LAYOUT_REVISION is kept as a literal in PlanSchema because the
 * boring compiler rejects a static field initializer that references
 * another static field (PlanJson.hx:16 "static field initializers accept
 * null, literal, array, and construction forms only"). This assertion
 * catches any accidental desync between the two so the cutover stays
 * single-sourced at the Revision level.
 */
class PlanSchemaTest {
    @:test
    public static function planSchemaConstantsAlignWithRevision():Void {
        TracedAssertions.assertEqualsString(
            Revision.LAYOUT_REVISION, PlanSchema.PLAN_LAYOUT_REVISION,
            "PLAN_LAYOUT_REVISION vs Revision.LAYOUT_REVISION"
        );
        TracedAssertions.assertEquals(
            PlanSchema.PLAN_SCHEMA, Revision.SNAPSHOT_SCHEMA,
            "PLAN_SCHEMA vs SNAPSHOT_SCHEMA"
        );
    }
}