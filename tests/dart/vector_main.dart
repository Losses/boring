// Cross-language vector verification for the generated Dart tree: the
// committed roundtrip binaries must decode to the same records the other
// lanes verify, and re-encoding must reproduce the committed bytes
// exactly (binary spec 05).

import 'dart:io';

import '../../reference/dart/gen/lib/boring/float_width.dart' as float_width;
import '../../reference/dart/gen/lib/boring/glyph_metrics.dart' as glyph_metrics;
import '../../reference/dart/gen/lib/boring/vector_codec.dart' as vector_codec;

var failures = 0;

void check(bool condition, String name) {
  if (condition) {
    print('pass: $name');
  } else {
    print('FAIL: $name');
    failures++;
  }
}

List<int> readBytes(String path) {
  return File(path).readAsBytesSync();
}

bool bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

bool recordsEqual(List<glyph_metrics.GlyphMetrics> a, List<glyph_metrics.GlyphMetrics> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

List<glyph_metrics.GlyphMetrics> expectedRecords() {
  return [
    glyph_metrics.GlyphMetrics(65, 0.5, glyph_metrics.BoundsEm(0.03125, -0.21875, 0.46875, 0.03125)),
    glyph_metrics.GlyphMetrics(19969, 1.0, glyph_metrics.BoundsEm(0.03125, -0.875, 0.96875, 0.03125)),
    glyph_metrics.GlyphMetrics(65292, 0.5, glyph_metrics.BoundsEm(0.03125, -0.21875, 0.46875, 0.03125)),
    glyph_metrics.GlyphMetrics(65311, 0.75, glyph_metrics.BoundsEm(0.0625, -0.15625, 0.6875, 0.0625)),
  ];
}

void main() {
  final records = expectedRecords();
  final widths = <float_width.FloatWidth>[
    float_width.FloatWidthF64(),
    float_width.FloatWidthF32(),
    float_width.FloatWidthF16(),
  ];
  final paths = <String>[
    'tests/vectors/roundtrip.bin',
    'tests/vectors/roundtrip-f32.bin',
    'tests/vectors/roundtrip-f16.bin',
  ];
  for (var i = 0; i < widths.length; i++) {
    final committed = readBytes(paths[i]);
    check(committed.length > 0, '${paths[i]} loads');

    var decoded = <glyph_metrics.GlyphMetrics>[];
    var rejected = false;
    try {
      decoded = vector_codec.decode(committed);
    } catch (error) {
      rejected = true;
    }
    check(!rejected && recordsEqual(decoded, records), '${paths[i]} decodes to the shared records');

    if (!rejected) {
      final reencoded = vector_codec.encode(records, widths[i]);
      check(bytesEqual(reencoded, committed), 're-encoding ${paths[i]} reproduces the committed bytes');
    }
  }

  // A magic outside the table refuses the block; the reader never guesses
  // a layout (binary spec 05).
  final badMagic = readBytes('tests/vectors/roundtrip.bin').toList();
  badMagic[3] = 0x34;
  var badMagicRejected = false;
  try {
    vector_codec.decode(badMagic);
  } catch (error) {
    badMagicRejected = true;
  }
  check(badMagicRejected, 'an unknown magic rejects the block');

  if (failures > 0) {
    print('$failures check(s) failed');
    exitCode = 1;
    return;
  }
  print('all vector checks passed');
}
