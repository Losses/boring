package tests;

import std.Test;
import boring.protocol.FloatCanonical;
import boring.protocol.CanonicalFingerprint;

/**
 * P-23 conformance fixture: the canonical float bytes and fingerprint every
 * target must reproduce byte-for-byte. The expected hex values are the
 * reference encoder's candidate output (criterion 1); a target passes a case
 * exactly when its canonical bytes match. The five targets together prove
 * byte-for-byte consistency when every case passes on every target.
 */
class FloatCanonicalTests {
    @:test("both signed zeroes encode as zero bits at f64 and f32")
    public static function testSignedZero():Void {
        Test.equals("0000000000000000", FloatCanonical.hex(FloatCanonical.encode64(0.0)), "encode64(+0.0)");
        Test.equals("0000000000000000", FloatCanonical.hex(FloatCanonical.encode64(-0.0)), "encode64(-0.0)");
        Test.equals("00000000", FloatCanonical.hex(FloatCanonical.encode32(0.0)), "encode32(+0.0)");
        Test.equals("00000000", FloatCanonical.hex(FloatCanonical.encode32(-0.0)), "encode32(-0.0)");
    }

    @:test("nonzero finite values encode IEEE bits at their declared width")
    public static function testFinite():Void {
        Test.equals("3ff0000000000000", FloatCanonical.hex(FloatCanonical.encode64(1.0)), "encode64(1.0)");
        Test.equals("bff0000000000000", FloatCanonical.hex(FloatCanonical.encode64(-1.0)), "encode64(-1.0)");
        Test.equals("3fe0000000000000", FloatCanonical.hex(FloatCanonical.encode64(0.5)), "encode64(0.5)");
        Test.equals("3f800000", FloatCanonical.hex(FloatCanonical.encode32(1.0)), "encode32(1.0)");
        Test.equals("bf800000", FloatCanonical.hex(FloatCanonical.encode32(-1.0)), "encode32(-1.0)");
        Test.equals("3f000000", FloatCanonical.hex(FloatCanonical.encode32(0.5)), "encode32(0.5)");
    }

    @:test("Infinity retains IEEE bits at f64 and f32")
    public static function testInfinity():Void {
        Test.equals("7ff0000000000000", FloatCanonical.hex(FloatCanonical.encode64(Math.POSITIVE_INFINITY)), "encode64(+Inf)");
        Test.equals("fff0000000000000", FloatCanonical.hex(FloatCanonical.encode64(Math.NEGATIVE_INFINITY)), "encode64(-Inf)");
        Test.equals("7f800000", FloatCanonical.hex(FloatCanonical.encode32(Math.POSITIVE_INFINITY)), "encode32(+Inf)");
        Test.equals("ff800000", FloatCanonical.hex(FloatCanonical.encode32(Math.NEGATIVE_INFINITY)), "encode32(-Inf)");
    }

    @:test("every NaN encodes the fixed quiet-NaN token regardless of payload or sign")
    public static function testNanPayloads():Void {
        // binary64 NaN payloads: quiet, signaling (smallest and largest payload), negative.
        Test.equals("7ff8000000000000", FloatCanonical.hex(FloatCanonical.encode64(haxe.io.FPHelper.i64ToDouble(0x00000000, 0x7FF80000))), "encode64(quiet f64 NaN)");
        Test.equals("7ff8000000000000", FloatCanonical.hex(FloatCanonical.encode64(haxe.io.FPHelper.i64ToDouble(0x00000001, 0x7FF00000))), "encode64(signaling f64 NaN)");
        Test.equals("7ff8000000000000", FloatCanonical.hex(FloatCanonical.encode64(haxe.io.FPHelper.i64ToDouble(0xFFFFFFFF, 0x7FF7FFFF))), "encode64(largest-signaling f64 NaN)");
        Test.equals("7ff8000000000000", FloatCanonical.hex(FloatCanonical.encode64(haxe.io.FPHelper.i64ToDouble(0x00000001, 0xFFF00000))), "encode64(negative signaling f64 NaN)");
        // binary32 NaN payloads: quiet, signaling, negative.
        Test.equals("7fc00000", FloatCanonical.hex(FloatCanonical.encode32(haxe.io.FPHelper.i32ToFloat(0x7FC00000))), "encode32(quiet f32 NaN)");
        Test.equals("7fc00000", FloatCanonical.hex(FloatCanonical.encode32(haxe.io.FPHelper.i32ToFloat(0x7F800001))), "encode32(signaling f32 NaN)");
        Test.equals("7fc00000", FloatCanonical.hex(FloatCanonical.encode32(haxe.io.FPHelper.i32ToFloat(0xFFC00000))), "encode32(negative f32 NaN)");
    }

    @:test("quiet and signaling NaN collapse to the same token")
    public static function testQuietVsSignaling():Void {
        final quiet = haxe.io.FPHelper.i64ToDouble(0x00000000, 0x7FF80000);
        final signaling = haxe.io.FPHelper.i64ToDouble(0x00000001, 0x7FF00000);
        Test.equals(FloatCanonical.hex(FloatCanonical.encode64(quiet)), FloatCanonical.hex(FloatCanonical.encode64(signaling)), "quiet == signaling f64 token");
        final q32 = haxe.io.FPHelper.i32ToFloat(0x7FC00000);
        final s32 = haxe.io.FPHelper.i32ToFloat(0x7F800001);
        Test.equals(FloatCanonical.hex(FloatCanonical.encode32(q32)), FloatCanonical.hex(FloatCanonical.encode32(s32)), "quiet == signaling f32 token");
    }

    @:test("record fingerprint frames fields with null markers in declaration order")
    public static function testRecordFingerprint():Void {
        final fields:Array<FingerprintField> = [
            { key: "ratio", typeTag: CanonicalFingerprint.TAG_F64, isNull: false, value: FloatCanonical.encode64(0.5) },
            { key: "count", typeTag: CanonicalFingerprint.TAG_F64, isNull: true, value: haxe.io.Bytes.alloc(0) },
            { key: "level", typeTag: CanonicalFingerprint.TAG_F32, isNull: false, value: FloatCanonical.encode32(1.0) }
        ];
        Test.equals("04d2ef36c00655891c4b543fed2185f5d4fef8d88209b585297b7980a89acbb5", FloatCanonical.hex(CanonicalFingerprint.encode(fields)), "record fingerprint");
    }

    @:test("nested record fingerprint flattens with dotted keys")
    public static function testNestedRecord():Void {
        final fields:Array<FingerprintField> = [
            { key: "outer", typeTag: CanonicalFingerprint.TAG_F64, isNull: false, value: FloatCanonical.encode64(1.0) },
            { key: "inner.x", typeTag: CanonicalFingerprint.TAG_F64, isNull: false, value: FloatCanonical.encode64(-0.5) }
        ];
        Test.equals("29277e4e97aef3ed85b867e4581755691059294fc2cc5ba68cc22c20dc71b981", FloatCanonical.hex(CanonicalFingerprint.encode(fields)), "nested record fingerprint");
    }

    @:test("map key fingerprint feeds entries in canonical key order")
    public static function testMapKey():Void {
        final fields:Array<FingerprintField> = [
            { key: "m[0]", typeTag: CanonicalFingerprint.TAG_F64, isNull: false, value: FloatCanonical.encode64(-1.0) },
            { key: "m[1]", typeTag: CanonicalFingerprint.TAG_F64, isNull: false, value: FloatCanonical.encode64(0.5) }
        ];
        Test.equals("7f595def5beff84aaefc4d5c74a031df6f80c1bc3a167117a212d9076664d098", FloatCanonical.hex(CanonicalFingerprint.encode(fields)), "map key fingerprint");
    }
}
