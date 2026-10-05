package std;

/**
	The exception every failing std.Fs host operation raises
	(docs/specs/stdlib/17-platform-modules.md): a haxe.Exception subclass
	carrying the FsError variant as its canonical failure identity. A catch
	clause names this one concrete class and reads the normalized kind off
	`error.error` (docs/specs/features/06-errors-and-results.md). The
	haxe.Exception base stays the catch-all.
**/
class FsException extends haxe.Exception {
	public final error:FsError;

	public function new(error:FsError) {
		this.error = error;
		super(FsException.describe(error));
	}

	/** The display message: the operation, the path, the normalized kind
	    and the attached host diagnostic, or the fixed unavailability text
	    for the no-capability case. */
	public static function describe(error:FsError):String {
		return switch (error) {
			case NotFound(operation, path, nativeDetail): 'std.Fs.$operation: $path not found: $nativeDetail';
			case PermissionDenied(operation, path, nativeDetail): 'std.Fs.$operation: $path: permission denied: $nativeDetail';
			case NotDirectory(operation, path, nativeDetail): 'std.Fs.$operation: $path: not a directory: $nativeDetail';
			case AlreadyExists(operation, path, nativeDetail): 'std.Fs.$operation: $path already exists: $nativeDetail';
			case InvalidInput(operation, path, nativeDetail): 'std.Fs.$operation: $path: invalid input: $nativeDetail';
			case IsDirectory(operation, path, nativeDetail): 'std.Fs.$operation: $path is a directory: $nativeDetail';
			case Unavailable(operation, path): 'std.Fs.$operation: std.Fs is not available on this host';
			case Other(operation, path, nativeDetail): 'std.Fs.$operation: $path: $nativeDetail';
		};
	}
}
