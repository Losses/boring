#if (macro || reflaxe_runtime)
import haxe.macro.Context;

/**
	Package artifact packing shared by the target compilers (feature
	spec 25). The compiler records every main-tree write it performs;
	the emit path packs that list into the install artifact of the
	target's ecosystem and writes it beside the output tree. The entry
	set is the recorded list and never a directory walk, so files the
	compilation did not write (stale artifacts, test execution output)
	cannot enter an archive.

	- `package-artifacts=emit`: write the artifact after the tree.
	- `package-artifacts=none` (or the absent define): source only.
	- Determinism constants live in the archive builders below: tar
	  mtime 0 and mode 0644, gzip MTIME 0, one fixed zip date, sorted
	  entry names, compression level 9.
**/
class PackageArtifacts {
	/** The writes of the current compilation, in save order. */
	static var entries: Array<{path: String, content: String}> = [];

	/** True when the compilation packs an install artifact. Errors on any value outside emit/none. */
	public static function enabled(): Bool {
		final value = Context.definedValue("package-artifacts");
		if(value == null || value == "none") {
			return false;
		}
		if(value == "emit") {
			return true;
		}
		Context.error("package-artifacts accepts emit or none", Context.currentPos());
		return false;
	}

	/**
		Stops the compilation when the shell is off: the artifact wraps
		the manifest, so packing a manifest-less tree would produce an
		uninstallable archive.
	**/
	public static function requireShell(): Void {
		if(!PackageShell.enabled()) {
			Context.error("package artifacts require the package shell: an artifact wraps the manifest the shell emits; pass package-shell emit or package-artifacts none", Context.currentPos());
		}
	}

	/**
		Stops the compilation on the Kotlin target: Gradle modules
		publish through the consumer's build, and no artifact format
		exists for this lane.
	**/
	public static function rejectUnsupportedTarget(): Void {
		Context.error("package artifacts are undefined for the Kotlin target: Gradle publication belongs to the consumer's build; pass package-artifacts none", Context.currentPos());
	}

	/**
		Records one write the compiler performed through its output
		manager. Paths escaping the output root (the `../` paths of the
		test-output trees) belong to another tree and stay unpacked.
	**/
	public static function record(path: String, content: String): Void {
		if(StringTools.startsWith(path, "../")) {
			return;
		}
		entries.push({path: path, content: content});
	}

	/**
		Packs the recorded writes as a tar+gzip artifact. `npmLayout`
		prefixes every entry with `package/` and sanitizes the scope
		slash out of the file name; the cargo and Pub layouts keep the
		tree at the archive root.
	**/
	public static function emitTarGz(outputDir: String, npmLayout: Bool, extension: String): Void {
		final name = PackageShell.name();
		final version = PackageShell.version();
		final stem = (npmLayout ? StringTools.replace(name, "/", "-") : name) + "-" + version;
		final artifactPath = haxe.io.Path.join([artifactDirectory(outputDir), stem + extension]);
		sys.io.File.saveBytes(artifactPath, gzipBytes(tarBytes(npmLayout ? "package/" : "")));
	}

	/** Packs the recorded writes as the Swift zip artifact. */
	public static function emitZip(outputDir: String): Void {
		final stem = PackageShell.name() + "-" + PackageShell.version();
		final artifactPath = haxe.io.Path.join([artifactDirectory(outputDir), stem + ".zip"]);
		final out = new haxe.io.BytesOutput();
		new haxe.zip.Writer(out).write(zipEntries());
		sys.io.File.saveBytes(artifactPath, out.getBytes());
	}

	// ------------------------------------------------------------------
	// Archive bytes
	// ------------------------------------------------------------------

	/**
		The recorded writes, deduplicated by path (last write wins) and
		sorted by name; every archive format packs this one ordering.
	**/
	static function sortedPaths(): Array<{path: String, content: String}> {
		final latest = new Map<String, String>();
		for(entry in entries) {
			latest.set(entry.path, entry.content);
		}
		final paths = [for(path in latest.keys()) path];
		paths.sort(Reflect.compare);
		return [for(path in paths) {path: path, content: latest.get(path)}];
	}

	static function tarBytes(prefix: String): haxe.io.Bytes {
		final files = new format.tar.Data();
		for(entry in sortedPaths()) {
			final data = haxe.io.Bytes.ofString(entry.content);
			files.add({
				fileName: prefix + entry.path,
				fileSize: data.length,
				fileTime: Date.fromTime(0),
				fmod: 420,
				uid: 0,
				gid: 0,
				uname: "",
				gname: "",
				data: data,
			});
		}
		final out = new haxe.io.BytesOutput();
		new format.tar.Writer(out).write(files);
		return out.getBytes();
	}

	/**
		Gzip framing around a raw deflate body. `haxe.zip.Compress`
		produces a zlib stream (2-byte header, adler32 trailer); the
		gzip format carries the deflate body with its own 10-byte
		header and a CRC-32 plus ISIZE trailer, all written little-end.
		MTIME 0, XFL 0, OS 3 (Unix) hold the determinism constants.
	**/
	static function gzipBytes(input: haxe.io.Bytes): haxe.io.Bytes {
		final zlib = haxe.zip.Compress.run(input, 9);
		final out = new haxe.io.BytesOutput();
		out.writeByte(0x1f);
		out.writeByte(0x8b);
		out.writeByte(0x08);
		out.writeByte(0x00);
		out.writeInt32(0);
		out.writeByte(0x00);
		out.writeByte(0x03);
		out.write(zlib.sub(2, zlib.length - 6));
		out.writeInt32(haxe.crypto.Crc32.make(input));
		out.writeInt32(input.length);
		return out.getBytes();
	}

	static function zipEntries(): haxe.ds.List<haxe.zip.Entry> {
		// June 1, 2020, 12:00:00 read through local-time fields: every
		// timezone encodes the same DOS date bytes.
		final fixedDate = new Date(2020, 5, 1, 12, 0, 0);
		final list = new haxe.ds.List<haxe.zip.Entry>();
		for(entry in sortedPaths()) {
			final data = haxe.io.Bytes.ofString(entry.content);
			final zipEntry: haxe.zip.Entry = {
				fileName: entry.path,
				fileSize: data.length,
				fileTime: fixedDate,
				crc32: haxe.crypto.Crc32.make(data),
				data: data,
				dataSize: data.length,
				compressed: false,
			};
			// The CRC must exist before compression; Tools.compress
			// swaps in the raw deflate body the zip format carries.
			haxe.zip.Tools.compress(zipEntry, 9);
			list.add(zipEntry);
		}
		return list;
	}

	/**
		The artifact lands in the parent of the output directory: the
		tree keeps exactly the files the compilation wrote, and an
		artifact inside the tree would enter later directory-based
		packing as a stale member.
	**/
	static function artifactDirectory(outputDir: String): String {
		final normalized = StringTools.endsWith(outputDir, "/") ? outputDir.substring(0, outputDir.length - 1) : outputDir;
		final parent = haxe.io.Path.directory(normalized);
		return parent == "" ? "." : parent;
	}
}
#end
