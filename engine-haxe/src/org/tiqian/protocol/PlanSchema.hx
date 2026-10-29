package org.tiqian.protocol;

/**
 * Plan JSON schema constants (Stage1-P3). The two constants ride the JSON
 * wire as the first keys (PreparedParagraph.kt:94-95); consumers read them
 * by name and verify the layout revision matches Revision.LAYOUT_REVISION.
 *
 * PLAN_SCHEMA: the schema this producer emits (mirrors PreparedParagraph.kt:15
 *   PREPARED_PARAGRAPH_SCHEMA, plan.rs:13 PLAN_SCHEMA).
 * PLAN_LAYOUT_REVISION: the layout revision this plan was built with (single
 *   source: Revision.LAYOUT_REVISION, Stage1-P4; plan.rs:16 PLAN_LAYOUT_
 *   REVISION).
 */
class PlanSchema {
    public static final PLAN_SCHEMA:Int = 1;
    /** Single source: Revision.LAYOUT_REVISION (Stage1-P4). The boring compiler
        restricts static field initializers to literals, so the value is copied
        here; the two are kept in sync by the protocol batch test. */
    public static final PLAN_LAYOUT_REVISION:String = "tiqian-layout-v2";
}
