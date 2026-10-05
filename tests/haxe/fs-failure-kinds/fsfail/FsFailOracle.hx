package fsfail;

import std.Fs;
import std.FsError;
import std.FsException;

/**
	Cross-target failure-identity fixture for std.Fs
	(docs/specs/stdlib/17-platform-modules.md, docs/specs/stdlib/03-haxe-exception.md).

	A host failure must surface as one std.FsException carrying one normalized
	std.FsError variant, so the Haxe-observable identity is `Kind|operation` on
	every target and never the host text. Only the fallible operations raise;
	exists/isDirectory stay total and answer false for a missing path.
**/
class FsFailOracle {
	/** `Kind|operation` of the FsError, the cross-target identity. */
	static function identity(error:FsError):String {
		return switch (error) {
			case NotFound(operation, _, _): "NotFound|" + operation;
			case PermissionDenied(operation, _, _): "PermissionDenied|" + operation;
			case NotDirectory(operation, _, _): "NotDirectory|" + operation;
			case AlreadyExists(operation, _, _): "AlreadyExists|" + operation;
			case InvalidInput(operation, _, _): "InvalidInput|" + operation;
			case IsDirectory(operation, _, _): "IsDirectory|" + operation;
			case Unavailable(operation, _): "Unavailable|" + operation;
			case Other(operation, _, _): "Other|" + operation;
		}
	}

	/** readText(path) outcome: the normalized identity, or `no-throw`. */
	public static function readIdentity(path:String):String {
		var out = "no-throw";
		try {
			out = "read:" + Fs.readText(path);
		} catch (e:FsException) {
			out = identity(e.error);
		}
		return out;
	}

	/** writeText(path, "x") outcome: the normalized identity, or `no-throw`. */
	public static function writeIdentity(path:String):String {
		var out = "no-throw";
		try {
			Fs.writeText(path, "x");
		} catch (e:FsException) {
			out = identity(e.error);
		}
		return out;
	}

	/** `<exists>|<isDirectory>`; the predicates never raise. */
	public static function predicatePair(path:String):String {
		return (Fs.exists(path) ? "true" : "false") + "|" + (Fs.isDirectory(path) ? "true" : "false");
	}

	/** A directly thrown FsError caught as FsException. */
	public static function manualCatchIdentity():String {
		var out = "no-throw";
		try {
			throw new FsException(FsError.NotFound("readText", "p", "d"));
		} catch (e:FsException) {
			out = identity(e.error);
		}
		return out;
	}
}
