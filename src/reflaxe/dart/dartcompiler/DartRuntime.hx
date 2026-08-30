package dartcompiler;

#if (macro || reflaxe_runtime)

/**
	Source of the runtime library emitted next to the generated files
	(docs/specs/targets/dart.md). It only hosts what the translatable
	subset cannot express inline: the Int64 bit representation
	(stdlib/05), the exception base class of features/06, and the
	unit-order comparator tear-off the sorted builders bind
	(stdlib/07). The byte sink and the string-view helpers of the Swift
	lane have no Dart counterparts: haxe.io.BytesBuffer lowers to the
	list itself (stdlib/02) and native String is the UTF-16 view
	natively. Resident modules compile through the normal pipeline and
	append after this prelude.
**/
class DartRuntime {
	public static final SOURCE = "

/// The two 32-bit halves of a binary64 value (stdlib/05). The halves
/// carry the bit patterns as the signed halves the codec boundaries
/// read, recombined through a typed view at the float edge.
class Int64Halves {
  final int high;
  final int low;

  Int64Halves(this.high, this.low);
}

/// The bit pattern of a double as its two 32-bit halves (stdlib/05).
Int64Halves doubleToI64(double value) {
  final bytes = ByteData(8);
  bytes.setFloat64(0, value, Endian.little);
  return Int64Halves(bytes.getInt32(4, Endian.little), bytes.getInt32(0, Endian.little));
}

/// The double of two 32-bit halves (stdlib/05).
double i64ToDouble(int low, int high) {
  final bytes = ByteData(8);
  bytes.setInt32(0, low, Endian.little);
  bytes.setInt32(4, high, Endian.little);
  return bytes.getFloat64(0, Endian.little);
}

/// Base class of the exception classes features/06 lowers; the caught
/// side reads the display message through it.
class BoringException implements Exception {
  final String message;

  BoringException(this.message);
}

/// UTF-16 code-unit ordering of two strings, the order stdlib/07 rules
/// for sorted keys. Native order on this lane already compares by code
/// units, so the helper only provides the tear-off shape the sorted
/// builders bind.
int compareUnitOrder(String a, String b) {
  return a.compareTo(b);
}

/// The code point at a unit index, combining a surrogate pair when one
/// starts there. The resident cursor walk (stdlib/03) reads code points
/// through this; the same helper lives privately in every library that
/// inlines the walk.
int _codePointAt(String s, int i) {
  final lead = s.codeUnitAt(i);
  if (lead >= 55296 && lead <= 56319 && i + 1 < s.length) {
    final tail = s.codeUnitAt(i + 1);
    if (tail >= 56320 && tail <= 57343) {
      return 65536 + ((lead - 55296) << 10) + (tail - 56320);
    }
  }
  return lead;
}

";

	/**
		Source of the test host entry. It holds the raise type of this
		language, the runner state behind a library-private variable with
		one accessor, and the stdout edge; the consistency run redirects
		stdout to the jsonl results file. The runtime import is prepended
		by the compiler because its relative path depends on the output
		defines; TestCore compiles through the normal pipeline and
		appends after this host in the same library.
	**/
	public static final TEST_SOURCE = "
/// The code point at a unit index, the private twin of the runtime
/// library's helper; TestCore inlines the same resident cursor walk.
int _codePointAt(String s, int i) {
  final lead = s.codeUnitAt(i);
  if (lead >= 55296 && lead <= 56319 && i + 1 < s.length) {
    final tail = s.codeUnitAt(i + 1);
    if (tail >= 56320 && tail <= 57343) {
      return 65536 + ((lead - 55296) << 10) + (tail - 56320);
    }
  }
  return lead;
}

/// The assertion failure of features/19: the canonical message, raised
/// as a plain exception object the host catches.
class TestFailure implements Exception {
  final String message;

  TestFailure(this.message);
}

String _currentTestId = '';

/// The running test's id, for failure messages raised below the frame
/// that knows it.
String currentTestId() {
  return _currentTestId;
}

/// Host edge of the test entry (features/19): the runner state, the
/// raise of this language, and the stdout result edge. The result line
/// carries its own newline; a write with no terminator keeps one record
/// per line in the redirected results file. The return tells the runner
/// whether the test failed, so the process exits nonzero on any
/// failure.
bool run(String id, String name, void Function() body) {
  _currentTestId = id;
  var failed = false;
  try {
    body();
    stdout.write(TestCore.resultLine(id, name, false, ''));
  } on TestFailure catch (e) {
    failed = true;
    stdout.write(TestCore.resultLine(id, name, true, e.message));
  } on runtime.BoringException catch (e) {
    failed = true;
    stdout.write(TestCore.resultLine(id, name, true, e.message));
  } catch (e) {
    failed = true;
    stdout.write(TestCore.resultLine(id, name, true, e.toString()));
  }
  _currentTestId = '';
  return failed;
}
";
}
#end
