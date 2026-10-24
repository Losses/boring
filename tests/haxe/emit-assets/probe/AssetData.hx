package probe;

/** A golden-data holder marked as an asset module: its large payload is
    externalized to a data file instead of inlining as a string literal.
    Mirrors the org.tiqian.layout recorded_* holder shape. */
@:asset
class AssetData {
    public static function payload():String {
        return "line-000-abcdefghijklmnopqrstuvwxyz-0123456789\nline-001-abcdefghijklmnopqrstuvwxyz-0123456789\nline-002-abcdefghijklmnopqrstuvwxyz-0123456789\nline-003-abcdefghijklmnopqrstuvwxyz-0123456789\nline-004-abcdefghijklmnopqrstuvwxyz-0123456789\nline-005-abcdefghijklmnopqrstuvwxyz-0123456789\nline-006-abcdefghijklmnopqrstuvwxyz-0123456789\nline-007-abcdefghijklmnopqrstuvwxyz-0123456789\nline-008-abcdefghijklmnopqrstuvwxyz-0123456789\nline-009-abcdefghijklmnopqrstuvwxyz-0123456789\nline-010-abcdefghijklmnopqrstuvwxyz-0123456789\nline-011-abcdefghijklmnopqrstuvwxyz-0123456789\nline-012-abcdefghijklmnopqrstuvwxyz-0123456789\nline-013-abcdefghijklmnopqrstuvwxyz-0123456789\nline-014-abcdefghijklmnopqrstuvwxyz-0123456789";
    }
}
