package toplevelconst.consumer;

import toplevelconst.MarkedConsts;
import toplevelconst.UnmarkedConsts;

/**
    Cross-package consumer: a marked constant renders as the bare name plus
    a file-top-level import, an unmarked one keeps the holder qualifier. The
    generated Kotlin therefore imports
    `toplevelconst.PLATFORM_MULTI_FACE_STRING_DRAW_ISSUE`, the import form
    a published consumer writes.
**/
class ConstConsumer {
    public static function markedIssue():String {
        return MarkedConsts.PLATFORM_MULTI_FACE_STRING_DRAW_ISSUE;
    }

    public static function markedCoverage():String {
        return MarkedConsts.COVERAGE_ISSUE;
    }

    public static function markedFloat():Float {
        return MarkedConsts.FLOAT_CONST;
    }

    public static function unmarkedIssue():String {
        return UnmarkedConsts.PLATFORM_MULTI_FACE_STRING_DRAW_ISSUE;
    }
}
