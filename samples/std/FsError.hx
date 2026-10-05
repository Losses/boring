package std;

/**
	The canonical failure identity of a failing std.Fs host operation
	(docs/specs/stdlib/17-platform-modules.md). The variant is the
	normalized kind; features spec 06 R5 rules that the failure identity
	is the variant, so the kind is read off the variant and never parsed
	back out of the message. Every variant carries the operation name and
	the path; every variant but Unavailable also carries the host's native
	diagnostic text, which is attached for display only and never decides
	control flow or the kind.
**/
enum FsError {
	/** The path, or one of its ancestors, does not exist: ENOENT/ENOTDIR,
	    java.nio.file.NoSuchFileException/NotDirectoryException,
	    PathNotFoundException, std::io::ErrorKind::NotFound. */
	NotFound(operation:String, path:String, nativeDetail:String);

	/** The host refused access: EACCES/EPERM,
	    java.nio.file.AccessDeniedException. */
	PermissionDenied(operation:String, path:String, nativeDetail:String);

	/** A path component that had to be a directory is not one: ENOTDIR. */
	NotDirectory(operation:String, path:String, nativeDetail:String);

	/** The operation's target already exists: EEXIST,
	    java.nio.file.FileAlreadyExistsException. */
	AlreadyExists(operation:String, path:String, nativeDetail:String);

	/** The host rejected the operation's input: EINVAL, ENAMETOOLONG. */
	InvalidInput(operation:String, path:String, nativeDetail:String);

	/** The operation required a file but the path is a directory: EISDIR. */
	IsDirectory(operation:String, path:String, nativeDetail:String);

	/** The host has no filesystem capability at all (a browser). The
	    message is the fixed unavailability text of stdlib/17. */
	Unavailable(operation:String, path:String);

	/** Every host failure the normalized kinds above do not name. */
	Other(operation:String, path:String, nativeDetail:String);
}
