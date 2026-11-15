package driver;

#if js
import js.Syntax;
#end

/**
    Where one pack run writes the registry tree and how the published URLs
    read. The output directory, the owner, the repository and the download
    base are parameters of the pack command: they describe where a caller
    publishes, so a compilation cannot derive them.
**/
typedef PackRegistryConfig = {
    out:String,
    owner:String,
    repo:String,
    assetBase:String
};

/**
    The registry metadata of one pack run (feature spec 26).

    The pack action owns every fact the metadata states. The package
    identity comes from the bundle, the artifact file is the one the
    compilation wrote under the bundle output directory, and a digest
    is of those bytes. The registry generator consumes the tree this writer
    produces: <out>/<owner>/<name>/<version>/<platform>/metadata.json plus
    one README.md per repository directory.

    The registry name depends on the ecosystem. Maven and SwiftPM name one
    artifact per build configuration, which is the artifact stem; cargo,
    npm and pub resolve the package by its package name, and pub writes the
    hyphenless form. A cargo precision companion packs the shared crate
    under a file-name stem and is not a package of its own, so it writes no
    metadata.
**/
class RegistryMetadata {
    /** Writes the metadata of every bundle a pack run named. */
    public static function emitAll(project:Project, bundles:Array<BundleSpec>, config:PackRegistryConfig):Void {
        for (bundle in bundles) {
            emitBundle(project, bundle, config);
        }
    }

    static function emitBundle(project:Project, bundle:BundleSpec, config:PackRegistryConfig):Void {
        final platform = platformOf(bundle.target);
        if (platform == null) return;
        final stem = artifactStem(bundle);
        if (platform == "cargo" && stem != bundle.packageName) return;
        final artifactDir = Host.resolve(project.root, project.outRoot + "/" + bundle.id);
        final version = bundle.packageVersion;
        final name = platform == "maven" || platform == "swift" ? stem : bundle.packageName;
        final dirName = platform == "pub" ? name.split("-").join("_") : name;
        final fields:Array<RegistryField> = [
            {key: "name", value: VText(platform == "pub" ? dirName : name)},
            {key: "version", value: VText(version)},
            {key: "license", value: VText(bundle.packageLicense == "" ? "MIT" : bundle.packageLicense)},
            {key: "repository", value: VText(config.owner + "/" + config.repo)},
            {key: "tag", value: VText("v" + version)}
        ];
        var archiveName = "";
        if (platform == "maven") {
            final files = mavenArtifacts(artifactDir, stem, version);
            if (files.length == 0) {
                fail('bundle "' + bundle.id + '": no Maven artifact matched ' + stem + ' under ' + artifactDir);
                return;
            }
            archiveName = files[0].file;
            fields.push({key: "groupId", value: VText(files[0].groupId)});
            final artifacts = [for (entry in files) mavenArtifact(entry, config.assetBase)];
            fields.push({key: "artifacts", value: VList(artifacts)});
        } else {
            final match = artifactMatch(platform, stem, bundle.packageName);
            final found = findArtifacts(artifactDir, match, false);
            if (found.length == 0) {
                fail('bundle "' + bundle.id + '": no ' + platform + ' artifact matched ' + stem + ' under ' + artifactDir);
                return;
            }
            archiveName = found[0];
            final archive = artifactDir + "/" + archiveName;
            if (platform == "swift") {
                fields.push({key: "packageSwift", value: VText(Host.readText(genDir(project, bundle) + "/Package.swift"))});
                fields.push({key: "archive", value: VText("swift/" + config.repo + "/" + name + "/" + version + ".zip")});
                fields.push({key: "sha256", value: VText(sha256Hex(archive))});
            } else if (platform == "npm") {
                fields.push({key: "url", value: VText(joinUrl(config.assetBase, archiveName))});
                fields.push({key: "sha512", value: VText(sha512Base64(archive))});
            } else if (platform == "cargo") {
                fields.push({key: "url", value: VText(joinUrl(config.assetBase, archiveName))});
                fields.push({key: "sha256", value: VText(sha256Hex(archive))});
                fields.push({key: "features", value: featureRecord(cargoFeatures(project, bundle))});
            } else if (platform == "pub") {
                fields.push({key: "url", value: VText(joinUrl(config.assetBase, archiveName))});
                fields.push({key: "sha256", value: VText(sha256Hex(archive))});
                fields.push({key: "pubspec", value: parsePubspec(Host.readText(genDir(project, bundle) + "/pubspec.yaml"))});
            }
        }
        final out = Host.resolve(project.root, config.out);
        final repoDir = out + "/" + config.owner + "/" + dirName;
        Host.makeDirs(repoDir);
        final readme = repoDir + "/README.md";
        if (!Host.exists(readme)) {
            Host.writeText(readme, "# " + name + "\n\nPackage metadata for " + name + ".\n");
        }
        final platformDir = repoDir + "/" + version + "/" + platform;
        Host.makeDirs(platformDir);
        Host.writeText(platformDir + "/metadata.json", serialize(VRecord(fields)) + "\n");
        Host.outputLine("registry metadata: " + name + " " + platform + " " + archiveName);
    }

    /** The registry platform of one bundle target, or null for a target that publishes nothing. */
    static function platformOf(target:String):Null<String> {
        if (target == "rust") return "cargo";
        if (target == "ts") return "npm";
        if (target == "kotlin") return "maven";
        if (target == "swift") return "swift";
        if (target == "dart") return "pub";
        return null;
    }

    /**
        The artifact file name stem of one bundle: the package-artifact-stem
        define when the bundle sets it, and the package name otherwise.
    **/
    static function artifactStem(bundle:BundleSpec):String {
        final args = bundle.haxeArgs;
        var index = 0;
        while (index < args.length) {
            final arg = args[index];
            if (arg == "-D" && index + 1 < args.length && StringTools.startsWith(args[index + 1], "package-artifact-stem=")) {
                return args[index + 1].substr("package-artifact-stem=".length);
            }
            if (StringTools.startsWith(arg, "-Dpackage-artifact-stem=")) {
                return arg.substr("-Dpackage-artifact-stem=".length);
            }
            index++;
        }
        return bundle.packageName;
    }

    static function genDir(project:Project, bundle:BundleSpec):String {
        return Host.resolve(project.root, project.outRoot + "/" + bundle.id + "/gen");
    }

    /** The predicate one platform's artifact file name satisfies. */
    static function artifactMatch(platform:String, stem:String, packageName:String):String->Bool {
        final prefix = platform == "pub" ? stem.split("-").join("_") : stem;
        var suffix = "";
        if (platform == "cargo") {
            suffix = ".crate";
        } else if (platform == "npm") {
            suffix = ".tgz";
        } else if (platform == "swift") {
            suffix = ".zip";
        } else if (platform == "pub") {
            suffix = ".tar.gz";
        }
        return function(file:String):Bool {
            return StringTools.startsWith(file, prefix + "-") && StringTools.endsWith(file, suffix);
        };
    }

    /**
        Every Maven file under one bundle's publication directory, each with
        the artifactId the directory it sits in names. The pack action points
        the project's publication command at a dedicated directory, so the
        tree holds exactly that package's publications: the Kotlin
        Multiplatform root coordinate and its target modules, with the
        payload (jar, klib, aar), the pom and the Gradle module metadata.
        The file name is not filtered by the stem, because a publication
        names its own artifactId and the directory layout is the only
        authority. A file that names no artifactId directory falls back to
        the stem, the single artifactId of the old shape.
    **/
    static function mavenArtifacts(artifactDir:String, stem:String, version:String):Array<MavenArtifact> {
        return [for (relative in findArtifacts(artifactDir + "/maven", function(relative:String):Bool {
            final file = baseName(relative);
            final extension = extensionOf(file);
            return extension == ".jar" || extension == ".pom" || extension == ".module"
                || extension == ".klib" || extension == ".aar";
        }, true)) {
            file: baseName(relative),
            artifactId: mavenArtifactIdOf(relative, version, stem),
            groupId: mavenGroupIdOf(relative, version, stem)
        }];
    }

    /**
        The artifactId of one Maven file: the path segment above the version
        directory, which Gradle names after the artifactId. A file that
        carries no such directory falls back to the stem, the single
        artifactId of the old shape.
    **/
    static function mavenArtifactIdOf(relative:String, version:String, stem:String):String {
        final parts = relative.split("/");
        var index = parts.length - 2;
        while (index > 0) {
            if (parts[index] == version) return parts[index - 1];
            index--;
        }
        return stem;
    }

    /**
        The groupId of one Maven file: every path segment above the
        artifactId directory, joined with the dots the Maven repository path
        splits. The directory is the compiler's package-group and the only
        authority for the coordinate the metadata describes; a file that
        carries no such directory falls back to the stem.
    **/
    static function mavenGroupIdOf(relative:String, version:String, stem:String):String {
        final parts = relative.split("/");
        var index = parts.length - 2;
        while (index > 0) {
            if (parts[index] == version) {
                final groups:Array<String> = [];
                var gi = 0;
                while (gi < index - 1) {
                    groups.push(parts[gi]);
                    gi++;
                }
                return groups.length == 0 ? stem : groups.join(".");
            }
            index--;
        }
        return stem;
    }

    static function baseName(relative:String):String {
        final slash = relative.lastIndexOf("/");
        return slash < 0 ? relative : relative.substr(slash + 1);
    }

    static function mavenArtifact(entry:MavenArtifact, assetBase:String):RegistryValue {
        return VRecord([
            {key: "file", value: VText(entry.file)},
            {key: "url", value: VText(joinUrl(assetBase, entry.file))},
            {key: "artifactId", value: VText(entry.artifactId)}
        ]);
    }

    static function extensionOf(file:String):String {
        final dot = file.lastIndexOf(".");
        return dot < 0 ? "" : file.substr(dot);
    }

    /**
        Every regular file under the root whose relative path satisfies
        the predicate, sorted. The walk descends only when the
        caller asks for it: the Maven artifact sits below a group-id
        directory, while the other platforms write their artifact directly
        into the bundle output directory beside the generated tree.
    **/
    static function findArtifacts(root:String, match:String->Bool, recursive:Bool):Array<String> {
        final found:Array<String> = [];
        collectArtifacts(root, "", match, recursive, found);
        sortStrings(found);
        return found;
    }

    static function collectArtifacts(root:String, prefix:String, match:String->Bool, recursive:Bool, found:Array<String>):Void {
        final dir = prefix == "" ? root : root + "/" + prefix;
        if (!Host.exists(dir) || !Host.isDirectory(dir)) return;
        for (entry in Host.readDir(dir)) {
            final relative = prefix == "" ? entry : prefix + "/" + entry;
            final absolute = root + "/" + relative;
            if (Host.isDirectory(absolute)) {
                if (recursive) collectArtifacts(root, relative, match, recursive, found);
                continue;
            }
            if (match(relative)) found.push(relative);
        }
    }

    /**
        A callback-free lexicographic sort of strings. The guarded subset
        rejects a comparator sort, so the ordering is written out: insertion
        sort states the same string order Reflect.compare does, and it keeps
        equal entries in their original positions.
    **/
    static function sortStrings(items:Array<String>):Void {
        for (i in 1...items.length) {
            final x = items[i];
            var j = i - 1;
            while (j >= 0 && items[j] > x) {
                items[j + 1] = items[j];
                j = j - 1;
            }
            items[j + 1] = x;
        }
    }

    /** The same callback-free ordering for a record's fields, by key. */
    static function sortFieldsByKey(fields:Array<RegistryField>):Void {
        for (i in 1...fields.length) {
            final x = fields[i];
            var j = i - 1;
            while (j >= 0 && fields[j].key > x.key) {
                fields[j + 1] = fields[j];
                j = j - 1;
            }
            fields[j + 1] = x;
        }
    }

    /**
        The cargo features the index has to declare for one package. A
        package shared by several build configurations carries the
        configuration switch as a cargo feature, and each configuration
        bundle names the feature it is built and tested with, so the union
        of those values is the declared set.
    **/
    static function cargoFeatures(project:Project, bundle:BundleSpec):Array<String> {
        final features:Array<String> = [];
        for (candidate in project.bundles) {
            if (candidate.packageName != bundle.packageName) continue;
            for (step in [candidate.build, candidate.run]) {
                final lists:Array<Array<String>> = [step.args, step.cargoArgs == null ? [] : step.cargoArgs];
                for (list in lists) {
                    var index = 0;
                    while (index < list.length) {
                        final value = list[index];
                        var declared:Null<String> = null;
                        if (value == "--features") {
                            if (index + 1 < list.length) declared = list[index + 1];
                        } else if (StringTools.startsWith(value, "--features=")) {
                            declared = value.substr("--features=".length);
                        }
                        if (declared != null) {
                            for (feature in declared.split(",")) {
                                final trimmed = StringTools.trim(feature);
                                if (trimmed != "" && !features.contains(trimmed)) features.push(trimmed);
                            }
                        }
                        index++;
                    }
                }
            }
        }
        sortStrings(features);
        return features;
    }

    static function featureRecord(features:Array<String>):RegistryValue {
        final fields = new Array<RegistryField>();
        for (feature in features) {
            fields.push({key: feature, value: VList([])});
        }
        return VRecord(fields);
    }

    static function joinUrl(base:String, file:String):String {
        var trimmed = base;
        while (StringTools.endsWith(trimmed, "/")) {
            trimmed = trimmed.substr(0, trimmed.length - 1);
        }
        return trimmed + "/" + file;
    }

    static function sha256Hex(path:String):String {
        #if js
        return cast Syntax.code('require("node:crypto").createHash("sha256").update(require("fs").readFileSync({0})).digest("hex")', path);
        #else
        throw "registry metadata digests require the JavaScript driver";
        #end
    }

    static function sha512Base64(path:String):String {
        #if js
        return cast Syntax.code('require("node:crypto").createHash("sha512").update(require("fs").readFileSync({0})).digest("base64")', path);
        #else
        throw "registry metadata digests require the JavaScript driver";
        #end
    }

    /**
        The pubspec of the packed Dart tree as a JSON object. The generated
        pubspec is flat: one top-level key per line, and one indented
        section whose entries become an object. A line without a key is
        skipped. The document is an ordered entry list because haxe.ds.Map
        has no translation (V13); a pubspec is tens of lines, so the exact-key
        scan costs nothing.
    **/
    static function parsePubspec(text:String):RegistryValue {
        final document = new Array<RegistryField>();
        var section:Null<String> = null;
        for (line in text.split("\n")) {
            final trimmed = StringTools.trim(line);
            if (trimmed == "" || StringTools.startsWith(trimmed, "#")) continue;
            final separator = line.indexOf(":");
            if (separator < 0) continue;
            final key = StringTools.trim(line.substr(0, separator));
            final value = StringTools.trim(line.substr(separator + 1));
            if (!StringTools.startsWith(line, " ")) {
                if (value != "") {
                    setPubspecField(document, key, VText(value));
                    section = null;
                } else {
                    setPubspecField(document, key, VRecord([]));
                    section = key;
                }
            } else if (section != null) {
                final sectionFields = pubspecSection(document, section);
                if (sectionFields == null) continue;
                sectionFields.push({key: key, value: VText(value)});
            }
        }
        return VRecord(document);
    }

    /** The fields of the pubspec section one top-level key opened, or null. */
    static function pubspecSection(document:Array<RegistryField>, key:String):Null<Array<RegistryField>> {
        for (field in document) {
            if (field.key != key) continue;
            final value = field.value;
            return switch value {
                case VRecord(sectionFields): sectionFields;
                case VText(_) | VList(_): null;
            }
        }
        return null;
    }

    /** Records one top-level pubspec key, replacing the value of a key already present. */
    static function setPubspecField(document:Array<RegistryField>, key:String, value:RegistryValue):Void {
        var index = 0;
        while (index < document.length) {
            if (document[index].key == key) {
                document[index] = {key: key, value: value};
                return;
            }
            index++;
        }
        document.push({key: key, value: value});
    }

    /**
        The metadata as the registry generator reads it: object keys sorted,
        each member separated by a comma and a space and each key from its
        value by a colon and a space, with non-ASCII characters escaped.
        The format stays stable under a reordered field list.
    **/
    static function serialize(value:RegistryValue):String {
        return switch value {
            case VText(text): quote(text);
            case VList(items): serializeList(items);
            case VRecord(fields): serializeRecord(fields);
        }
    }

    static function serializeList(items:Array<RegistryValue>):String {
        final parts = [for (item in items) serialize(item)];
        return "[" + parts.join(", ") + "]";
    }

    static function serializeRecord(fields:Array<RegistryField>):String {
        final sorted = sortedFields(fields);
        final parts = [for (field in sorted) quote(field.key) + ": " + serialize(field.value)];
        return "{" + parts.join(", ") + "}";
    }

    /** A copy of one record's fields in ascending key order. */
    static function sortedFields(fields:Array<RegistryField>):Array<RegistryField> {
        final sorted = fields.copy();
        sortFieldsByKey(sorted);
        return sorted;
    }

    static function quote(value:String):String {
        final out = new StringBuf();
        out.add('"');
        var index = 0;
        while (index < value.length) {
            final code = value.charCodeAt(index);
            if (code == 0x22) out.add('\\"');
            else if (code == 0x5C) out.add("\\\\");
            else if (code == 0x08) out.add("\\b");
            else if (code == 0x0C) out.add("\\f");
            else if (code == 0x0A) out.add("\\n");
            else if (code == 0x0D) out.add("\\r");
            else if (code == 0x09) out.add("\\t");
            else if (code < 0x20) out.add("\\u" + StringTools.hex(code, 4).toLowerCase());
            else if (code < 0x7F) out.add(value.charAt(index));
            else if (code <= 0xFFFF) out.add("\\u" + StringTools.hex(code, 4).toLowerCase());
            else {
                final rest = code - 0x10000;
                out.add("\\u" + StringTools.hex(0xD800 + (rest >> 10), 4).toLowerCase());
                out.add("\\u" + StringTools.hex(0xDC00 + (rest & 0x3FF), 4).toLowerCase());
            }
            index++;
        }
        out.add('"');
        return out.toString();
    }

    static function fail(message:String):Void {
        throw new DriverException(InvalidConfig(message));
    }
}

enum RegistryValue {
    VText(value:String);
    VList(items:Array<RegistryValue>);
    VRecord(fields:Array<RegistryField>);
}

typedef RegistryField = {key:String, value:RegistryValue};

/** One Maven file of a publication with the artifactId and groupId its directory states. */
typedef MavenArtifact = {file:String, artifactId:String, groupId:String};
