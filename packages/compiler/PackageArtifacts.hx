#if (macro || reflaxe_runtime)
import haxe.macro.Context;

/**
    Package artifact packing shared by the target compilers (feature
    spec 25). The compiler records every main-tree write it performs;
    the emit path packs that list into the install artifact of the
    target's ecosystem and writes it beside the output tree.

    Every artifact is the install unit its registry distributes. The
    cargo `.crate`, the Pub `.tar.gz`, and the Swift `.zip` carry
    source, because those registries install source; the npm `.tgz`
        carries compiled JavaScript plus declarations and the Kotlin target
    writes a Maven repository directory with a compiled jar, because
    those registries install build output. The two compiled targets run
    the host's compiler through a define (`package-tsc`,
    `package-kotlinc`); a missing define or a failing tool stops the
    compilation with the tool's own output.

    - `package-artifacts=emit`: write the artifact after the tree.
    - `package-artifacts=none` (or the absent define): source only.
    - Determinism constants live in the archive builders below: tar
      mtime 0 and mode 0644, gzip MTIME 0, one fixed zip date, sorted
      entry names, compression level 9.
**/
class PackageArtifacts {
    /** The writes of the current compilation, in save order. */
    static var entries:Array<{path:String, content:String}> = [];

    /** True when the compilation packs an install artifact. Errors on any value outside emit/none. */
    public static function enabled():Bool {
        final value = Context.definedValue("package-artifacts");
        if (value == null || value == "none") {
            return false;
        }
        if (value == "emit") {
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
    public static function requireShell():Void {
        if (!PackageShell.enabled()) {
            Context.error("package artifacts require the package shell: an artifact wraps the manifest the shell emits; pass package-shell emit or package-artifacts none",
                Context.currentPos());
        }
    }

    /**
        Records one write the compiler performed through its output
        manager. Paths escaping the output root (the `../` paths of the
        test-output trees) belong to another tree and stay unpacked.
    **/
    public static function record(path:String, content:String):Void {
        if (StringTools.startsWith(path, "../")) {
            return;
        }
        entries.push({path: path, content: content});
    }

    /**
        Packs the recorded writes as a tar+gzip artifact with the tree
        at the archive root (the cargo `.crate` and the Pub `.tar.gz`).
    **/
    public static function emitTarGz(outputDir:String, extension:String):Void {
        final stem = PackageShell.name() + "-" + PackageShell.version();
        final artifactPath = haxe.io.Path.join([artifactDirectory(outputDir), stem + extension]);
        sys.io.File.saveBytes(artifactPath, gzipBytes(tarBytes("")));
    }

    /** Packs the recorded writes as the Swift zip artifact. */
    public static function emitZip(outputDir:String):Void {
        final stem = PackageShell.name() + "-" + PackageShell.version();
        final artifactPath = haxe.io.Path.join([artifactDirectory(outputDir), stem + ".zip"]);
        sys.io.File.saveBytes(artifactPath, zipFromEntries(recordedEntries()));
    }

    // ------------------------------------------------------------------
    // npm: compiled JavaScript plus declarations
    // ------------------------------------------------------------------

    /**
        Packs the npm artifact. The recorded `.ts` writes are staged
        with their import specifiers rewritten from `.ts` to `.js`, the
        host's `tsc` compiles the stage, and the tarball carries `dist/`
        plus the artifact manifest. `excluded` names recorded files that
        stay out of the compile set (the runtime test entry, which
        imports node:fs for the repository's test harness and has no
        role in an installed package). The manifest is the compiler's
        own JSON string, so the exports map targets the compiled files.
    **/
    public static function emitNpmTarGz(outputDir:String, manifest:String, excluded:Array<String>):Void {
        final tsc = requiredTool("package-tsc", "TypeScript target", "the TypeScript compiler: the npm artifact ships compiled JavaScript and declarations");
        if (tsc == null) {
            return;
        }
        final parent = artifactDirectory(outputDir);
        final stage = haxe.io.Path.join([parent, ".package-npm-stage"]);
        deleteTree(stage);
        for (entry in sortedPaths()) {
            if (!StringTools.endsWith(entry.path, ".ts") || excluded.indexOf(entry.path) >= 0) {
                continue;
            }
            final path = haxe.io.Path.join([stage, entry.path]);
            sys.FileSystem.createDirectory(haxe.io.Path.directory(path));
            sys.io.File.saveContent(path, rewriteTsSpecifiers(entry.content));
        }
        // The manifest doubles as the stage's module marker: its
        // `"type": "module"` line is what makes nodenext treat the
        // staged sources as ES modules.
        sys.io.File.saveContent(haxe.io.Path.join([stage, "package.json"]), manifest);
        sys.io.File.saveContent(haxe.io.Path.join([stage, "tsconfig.json"]), TSCONFIG);
        runTool("package-tsc", tsc, ["-p", stage]);
        final files:Array<{name:String, data:haxe.io.Bytes}> = [{name: "package.json", data: haxe.io.Bytes.ofString(manifest)},];
        for (distPath in walkFiles(haxe.io.Path.join([stage, "dist"]))) {
            files.push({name: "dist/" + distPath, data: sys.io.File.getBytes(haxe.io.Path.join([stage, "dist", distPath]))});
        }
        files.sort((a, b) -> Reflect.compare(a.name, b.name));
        final stem = StringTools.replace(PackageShell.name(), "/", "-") + "-" + PackageShell.version();
        sys.io.File.saveBytes(haxe.io.Path.join([parent, stem + ".tgz"]), gzipBytes(tarFromEntries("package/", files)));
        deleteTree(stage);
    }

    /**
        The fixed compile configuration of the staging directory. The
        module pair is `nodenext`: it resolves the rewritten `.js`
        specifiers against the staged `.ts` sources and emits them
        verbatim, which is the form Node's ES-module loader requires.
    **/
    static final TSCONFIG = "{\n" + "  \"compilerOptions\": {\n" + "    \"module\": \"nodenext\",\n" + "    \"target\": \"es2022\",\n"
        + "    \"declaration\": true,\n" + "    \"outDir\": \"dist\",\n" + "    \"rootDir\": \".\",\n" + "    \"skipLibCheck\": true\n" + "  },\n"
        + "  \"include\": [\"**/*\"]\n" + "}\n";

    /**
        Rewrites the import specifiers of one staged module from `.ts`
        to `.js`. The TypeScript target emits every import in the
        `import { ... } from "specifier";` shape, and artifact mode
        holds only relative `.ts` specifiers (the shell of spec 24
        rejects a by-name runtime import), so the anchor on `from` plus
        the relative-path check leave every other string literal alone.
    **/
    static function rewriteTsSpecifiers(content:String):String {
        return ~/from "(\.\.?\/[^"]+)\.ts"/g.replace(content, 'from "$1.js"');
    }

    // ------------------------------------------------------------------
    // Kotlin: a Maven repository directory
    // ------------------------------------------------------------------

    /**
        Packs the Kotlin artifact as a Maven repository directory beside
        the output tree: `maven/<groupId path>/<name>/<version>/` holding
        the jar, the pom, and their sha1 checksums. The host's `kotlinc`
        compiles the recorded `.kt` writes into exploded classes, which
        this class repacks through its fixed-date zip writer so the jar
        metadata stays deterministic; the pom is written here from the
        spec 24 identity plus `package-group`. `maven-metadata.xml`
        belongs to the registry generator, which owns every
        registry-wide field.
    **/
    public static function emitMaven(outputDir:String):Void {
        final kotlinc = requiredTool("package-kotlinc", "Kotlin target",
            "the Kotlin compiler: the Maven artifact carries a jar compiled from the generated sources");
        if (kotlinc == null) {
            return;
        }
        final groupDefine = Context.definedValue("package-group");
        final groupId = groupDefine == null ? PackageShell.name() : groupDefine;
        final name = PackageShell.name();
        final version = PackageShell.version();
        final parent = artifactDirectory(outputDir);
        final versionDir = haxe.io.Path.join([parent, "maven", StringTools.replace(groupId, ".", "/"), name, version]);
        sys.FileSystem.createDirectory(versionDir);

        final classes = haxe.io.Path.join([parent, ".package-kotlinc-classes"]);
        deleteTree(classes);
        final args:Array<String> = [];
        for (entry in sortedPaths()) {
            // `build.gradle.kts` (the shell manifest) ends in `.kts`
            // and stays out of the compile set.
            if (StringTools.endsWith(entry.path, ".kt")) {
                args.push(haxe.io.Path.join([outputDir, entry.path]));
            }
        }
        args.push("-d");
        args.push(classes);
        runTool("package-kotlinc", kotlinc, args);

        final jarFiles:Array<{name:String, data:haxe.io.Bytes}> = [];
        for (classPath in walkFiles(classes)) {
            jarFiles.push({name: classPath, data: sys.io.File.getBytes(haxe.io.Path.join([classes, classPath]))});
        }
        jarFiles.sort((a, b) -> Reflect.compare(a.name, b.name));
        final jarBytes = zipFromEntries(jarFiles);
        final pomBytes = haxe.io.Bytes.ofString(pom(groupId, name, version));
        final stem = name + "-" + version;
        sys.io.File.saveBytes(haxe.io.Path.join([versionDir, stem + ".jar"]), jarBytes);
        sys.io.File.saveBytes(haxe.io.Path.join([versionDir, stem + ".pom"]), pomBytes);
        writeSha1(haxe.io.Path.join([versionDir, stem + ".jar"]), jarBytes);
        writeSha1(haxe.io.Path.join([versionDir, stem + ".pom"]), pomBytes);
        deleteTree(classes);
    }

    /**
        The pom of the artifact. The jar carries the module's classes
        only, so the pom declares the Kotlin stdlib it was compiled
        against, pinned to the plugin version the spec 24 build
        manifest states. Everything else is the spec 24 identity.
    **/
    static function pom(groupId:String, name:String, version:String):String {
        final lines = [
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<project xmlns=\"http://maven.apache.org/POM/4.0.0\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xsi:schemaLocation=\"http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd\">",
            "  <modelVersion>4.0.0</modelVersion>",
            "  <groupId>" + xmlEscape(groupId) + "</groupId>",
            "  <artifactId>" + xmlEscape(name) + "</artifactId>",
            "  <version>" + xmlEscape(version) + "</version>",
            "  <packaging>jar</packaging>",
        ];
        final license = PackageShell.license();
        if (license != null) {
            lines.push("  <licenses>");
            lines.push("    <license><name>" + xmlEscape(license) + "</name></license>");
            lines.push("  </licenses>");
        }
        lines.push("  <dependencies>");
        lines.push("    <dependency>");
        lines.push("      <groupId>org.jetbrains.kotlin</groupId>");
        lines.push("      <artifactId>kotlin-stdlib</artifactId>");
        lines.push("      <version>2.4.10</version>");
        lines.push("    </dependency>");
        lines.push("  </dependencies>");
        lines.push("</project>");
        return lines.join("\n") + "\n";
    }

    /** An XML text node with the four escapes a pom value needs. */
    static function xmlEscape(value:String):String {
        var out = StringTools.replace(value, "&", "&amp;");
        out = StringTools.replace(out, "<", "&lt;");
        out = StringTools.replace(out, ">", "&gt;");
        return StringTools.replace(out, "\"", "&quot;");
    }

    /**
        Writes the Maven checksum file beside one artifact file: forty
        lowercase hex digits under the artifact name plus `.sha1`.
    **/
    static function writeSha1(artifactPath:String, data:haxe.io.Bytes):Void {
        sys.io.File.saveContent(artifactPath + ".sha1", haxe.crypto.Sha1.make(data).toHex());
    }

    // ------------------------------------------------------------------
    // Host tools
    // ------------------------------------------------------------------

    /**
        The executable one compiled target needs, or null after an error.
        The artifact of that target is build output, so packing it without
        the tool is impossible; the message names the define that
        supplies the executable.
    **/
    static function requiredTool(define:String, lane:String, role:String):Null<String> {
        final value = Context.definedValue(define);
        if (value != null) {
            return value;
        }
        Context.error("package artifacts on the " + lane + " require " + role + "; pass " + define + " <executable> or package-artifacts none",
            Context.currentPos());
        return null;
    }

    /**
        Runs one host compiler the artifact pipeline needs. A nonzero
        exit stops the compilation with the command line, the exit code,
        and the tool's complete output, so a failing compile is reported in
        the Haxe invocation that requested the artifact. The output is
        read before the exit code is queried; compile output fits the
        pipe buffer, so the streams cannot deadlock.
    **/
    static function runTool(label:String, command:String, args:Array<String>):Void {
        var proc:sys.io.Process = null;
        try {
            proc = new sys.io.Process(command, args);
        } catch (e:Dynamic) {
            Context.fatalError(label + " could not start: " + command + " (" + Std.string(e) + ")", Context.currentPos());
        }
        final output = proc.stdout.readAll().toString() + proc.stderr.readAll().toString();
        final code = proc.exitCode();
        proc.close();
        if (code != 0) {
            Context.fatalError(label + " failed with exit code " + code + ":\n" + command + " " + args.join(" ") + "\n" + output, Context.currentPos());
        }
    }

    /**
        The regular files under one directory, relative to it, in no
        particular order; callers sort for the archive ordering.
    **/
    static function walkFiles(dir:String):Array<String> {
        return walkFilesInner(dir, "");
    }

    static function walkFilesInner(dir:String, prefix:String):Array<String> {
        final out:Array<String> = [];
        for (entry in sys.FileSystem.readDirectory(dir)) {
            final full = haxe.io.Path.join([dir, entry]);
            final rel = prefix.length == 0 ? entry : prefix + "/" + entry;
            if (sys.FileSystem.isDirectory(full)) {
                for (sub in walkFilesInner(full, rel)) {
                    out.push(sub);
                }
            } else {
                out.push(rel);
            }
        }
        return out;
    }

    /** Removes a staging tree of this pack step, file by file. */
    static function deleteTree(path:String):Void {
        if (!sys.FileSystem.exists(path)) {
            return;
        }
        if (sys.FileSystem.isDirectory(path)) {
            for (entry in sys.FileSystem.readDirectory(path)) {
                deleteTree(haxe.io.Path.join([path, entry]));
            }
            sys.FileSystem.deleteDirectory(path);
        } else {
            sys.FileSystem.deleteFile(path);
        }
    }

    // ------------------------------------------------------------------
    // Archive bytes
    // ------------------------------------------------------------------

    /**
        The recorded writes, deduplicated by path (last write wins) and
        sorted by name; every source-shipping format packs this one
        ordering.
    **/
    static function sortedPaths():Array<{path:String, content:String}> {
        final latest = new Map<String, String>();
        for (entry in entries) {
            latest.set(entry.path, entry.content);
        }
        final paths = [for (path in latest.keys()) path];
        paths.sort(Reflect.compare);
        return [for (path in paths) {path: path, content: latest.get(path)}];
    }

    static function recordedEntries():Array<{name:String, data:haxe.io.Bytes}> {
        return [
            for (entry in sortedPaths()) {name: entry.path, data: haxe.io.Bytes.ofString(entry.content)}
        ];
    }

    static function tarBytes(prefix:String):haxe.io.Bytes {
        return tarFromEntries(prefix, recordedEntries());
    }

    /**
        The tar member writer keeps the `format.tar.Writer` 3.8.0 header
        layout byte for byte with the spec 25 determinism constants
        (mtime 0, mode 0644, uid/gid 0, empty owner names). The local
        copy replaces the library call because its data padding writes a
        full zero block for a member sized a multiple of 512: that block
        sits mid-archive, `tar -t` reads it as the end-of-archive marker,
        and the listing stops at the next member. Member data pads to a
        512-byte boundary and a member already on the boundary takes no
        padding block.
    **/
    static function tarFromEntries(prefix:String, files:Array<{name:String, data:haxe.io.Bytes}>):haxe.io.Bytes {
        final out = new haxe.io.BytesOutput();
        for (file in files) {
            writeTarMember(out, prefix + file.name, file.data);
        }
        for (i in 0...2 * 512)
            out.writeByte(0);
        return out.getBytes();
    }

    static function writeTarMember(out:haxe.io.BytesOutput, name:String, data:haxe.io.Bytes):Void {
        final mode = tarOctal(420 & 0x1FF, 7);
        final uid = tarOctal(0, 7);
        final gid = tarOctal(0, 7);
        final size = tarOctal(data.length, 11);
        final date = tarOctal(0, 6) + tarOctal(0, 5);
        // 879 is the checksum of the eight spaces and the "ustar  "
        // magic the fixed header fields contribute.
        var chsum = 879
            + tarCharSum(name)
            + tarCharSum(mode)
            + tarCharSum(uid)
            + tarCharSum(gid)
            + tarCharSum(size)
            + tarCharSum(date)
            + tarCharSum("0");
        out.writeString(name);
        for (i in 0...100 - name.length)
            out.writeByte(0);
        out.writeString(mode);
        out.writeByte(0);
        out.writeString(uid);
        out.writeByte(0);
        out.writeString(gid);
        out.writeByte(0);
        out.writeString(size);
        out.writeByte(0);
        out.writeString(date);
        out.writeByte(0);
        out.writeString(tarOctal(chsum, 6));
        out.writeByte(0);
        out.writeString(" 0");
        for (i in 0...100)
            out.writeByte(0);
        out.writeString("ustar  ");
        out.writeByte(0);
        for (i in 0...32)
            out.writeByte(0);
        for (i in 0...32)
            out.writeByte(0);
        for (i in 0...8 + 8 + 155 + 12)
            out.writeByte(0);
        out.writeFullBytes(data, 0, data.length);
        for (i in 0...(512 - data.length % 512) % 512)
            out.writeByte(0);
    }

    /** One number as `len` zero-padded octal digits, the field form the tar header carries. */
    static function tarOctal(num:Int, len:Int):String {
        var octal = 0;
        var scale = 1;
        var rest = num;
        while (rest != 0) {
            octal += scale * (rest & 7);
            rest >>= 3;
            scale *= 10;
        }
        return StringTools.lpad(Std.string(octal), "0", len);
    }

    static function tarCharSum(s:String):Int {
        var sum = 0;
        for (i in 0...s.length)
            sum += s.charCodeAt(i);
        return sum;
    }

    /**
        Gzip framing around a raw deflate body. `haxe.zip.Compress`
        produces a zlib stream (2-byte header, adler32 trailer); the
        gzip format carries the deflate body with its own 10-byte
        header and a CRC-32 plus ISIZE trailer, all written little-end.
        MTIME 0, XFL 0, OS 3 (Unix) hold the determinism constants.
    **/
    static function gzipBytes(input:haxe.io.Bytes):haxe.io.Bytes {
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

    static function zipFromEntries(files:Array<{name:String, data:haxe.io.Bytes}>):haxe.io.Bytes {
        // June 1, 2020, 12:00:00 read through local-time fields: every
        // timezone encodes the same DOS date bytes.
        final fixedDate = new Date(2020, 5, 1, 12, 0, 0);
        final list = new haxe.ds.List<haxe.zip.Entry>();
        for (file in files) {
            final zipEntry:haxe.zip.Entry = {
                fileName: file.name,
                fileSize: file.data.length,
                fileTime: fixedDate,
                crc32: haxe.crypto.Crc32.make(file.data),
                data: file.data,
                dataSize: file.data.length,
                compressed: false,
            };
            // The CRC must exist before compression; Tools.compress
            // swaps in the raw deflate body the zip format carries.
            haxe.zip.Tools.compress(zipEntry, 9);
            list.add(zipEntry);
        }
        final out = new haxe.io.BytesOutput();
        new haxe.zip.Writer(out).write(list);
        return out.getBytes();
    }

    /**
        The artifact is written to the parent of the output directory: the
        tree keeps exactly the files the compilation wrote, and an
        artifact inside the tree would enter later directory-based
        packing as a stale member.
    **/
    static function artifactDirectory(outputDir:String):String {
        final normalized = StringTools.endsWith(outputDir, "/") ? outputDir.substring(0, outputDir.length - 1) : outputDir;
        final parent = haxe.io.Path.directory(normalized);
        return parent == "" ? "." : parent;
    }
}
#end
