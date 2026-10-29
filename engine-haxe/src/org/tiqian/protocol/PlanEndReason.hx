package org.tiqian.protocol;

/**
 * Plan line-end reason, single-sourced in Haxe (Stage1-P3). The three
 * variants mirror both the Kotlin engine's LineEndReason (LayoutModel.kt:133)
 * and the Rust reader's PlanEndReason (plan.rs:146); the engine serialises
 * the variant name as the wire value through `Type.enumConstructor`.
 */
enum PlanEndReason {
    AutoWrap;
    MandatoryBreak;
    ParagraphEnd;
}