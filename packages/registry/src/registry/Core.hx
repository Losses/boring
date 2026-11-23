package registry;

using Lambda;
using StringTools;

import registry.Json.JsonValue;
import registry.Json.JsonField;

typedef InputRecord = {path:String, content:String, inputRecord:Int};
typedef OutputFile = {path:String, content:String, outputFile:Int};
typedef RegistryConfig = {tree:String, output:String, baseUrl:String, swiftScope:String, archiveBase:String, configRecord:Int};

class Core {
    static final USAGE = "usage: generate --tree <dir> --output <site> --base-url <url> [--swift-scope <scope>] [--archive-base <url>]";

    static function fail(x:String):Void
        throw new CoreException(Tree(x));

    static function configFail(x:String):Void
        throw new CoreException(Config(x));

    static function S(x:String):JsonValue
        return JString(x);

    static function O(x:Array<JsonField>):JsonValue
        return JObject(x);

    static function A(x:Array<JsonValue>):JsonValue
        return JArray(x);

    static function get(o:JsonValue, n:String):JsonValue
        return Json.getField(o, n);

    /** Shape probes as return-position switches; every target lowers a
        variant switch only at return position. */
    static function jsonKind(v:JsonValue):Int
        return switch (v) {
            case JNull: 0;
            case JString(_): 1;
            case JObject(_): 2;
            case JArray(_): 3;
            case JNumber(_): 4;
            case JBool(_): 5;
        };

    static function jstring(v:JsonValue):String
        return switch (v) {
            case JString(x): x;
            case JObject(_): "";
            case JArray(_): "";
            case JNumber(_): "";
            case JBool(_): "";
            case JNull: "";
        };

    static function jarray(v:JsonValue):Array<JsonValue>
        return switch (v) {
            case JArray(a): a;
            case JObject(_): [];
            case JString(_): [];
            case JNumber(_): [];
            case JBool(_): [];
            case JNull: [];
        };

    static function jobject(v:JsonValue):Array<JsonField>
        return switch (v) {
            case JObject(x): x;
            case JArray(_): [];
            case JString(_): [];
            case JNumber(_): [];
            case JBool(_): [];
            case JNull: [];
        };

    static function str(o:JsonValue, n:String):String {
        var v = get(o, n);
        if (jsonKind(v) != 1) {
            fail("missing or invalid " + n);
            return "";
        }
        return jstring(v);
    }

    static function opt(o:JsonValue, n:String):Null<String> {
        var v = get(o, n);
        var k = jsonKind(v);
        if (k != 0 && k != 1) {
            fail("invalid " + n);
            return null;
        }
        if (k == 0)
            return null;
        return jstring(v);
    }

    static function nullValue():JsonValue
        return JNull;

    static function readMetadata(text:String, pp:String):JsonValue {
        var result = nullValue();
        try {
            result = Json.read(text);
        } catch (e:JsonException) {
            fail(pp + ": invalid JSON");
        }
        return result;
    }

    /** The cargo feature map the index entry declares. A metadata file
        written before the field existed carries none, and the entry then
        declares an empty map, which is what cargo reads for a crate with
        no features. */
    static function readFeatures(j:JsonValue, pp:String):Null<JsonValue> {
        var v = get(j, "features");
        var k = jsonKind(v);
        if (k == 0)
            return null;
        if (k != 2)
            fail(pp + ": invalid features");
        return v;
    }

    /** The package.json fields the npm client resolves from the packument
        version entry before it downloads the tarball. npm builds the
        dependency tree from this entry alone, so a dependency the tarball
        declares and the entry omits is never installed. The order here is
        the order the packument writes them in. */
    static function npmManifestKeys():Array<String>
        return [
            "dependencies",
            "optionalDependencies",
            "peerDependencies",
            "peerDependenciesMeta",
            "bin",
            "engines",
            "os",
            "cpu"
        ];

    /** The npm `manifest` object: the resolution fields of the packed
        package.json. A metadata file written before the field existed
        carries none, and the version entry then declares no dependencies.
        A key outside npmManifestKeys stops the generation. */
    static function readNpmManifest(j:JsonValue, pp:String):Null<JsonValue> {
        var v = get(j, "manifest");
        var k = jsonKind(v);
        if (k == 0)
            return null;
        if (k != 2)
            fail(pp + ": invalid manifest");
        var fs = jobject(v);
        for (fi in 0...fs.length) {
            var key = fs[fi].name;
            if (!npmManifestKeys().has(key))
                fail(pp + ": unknown manifest key " + key);
            if (!npmManifestValueOk(key, fs[fi].value))
                fail(pp + ": invalid manifest " + key);
        }
        return v;
    }

    /** Every value of an object is of JSON kind k. */
    static function objectOf(v:JsonValue, k:Int):Bool {
        if (jsonKind(v) != 2)
            return false;
        var fs = jobject(v);
        for (i in 0...fs.length)
            if (jsonKind(fs[i].value) != k)
                return false;
        return true;
    }

    static function stringList(v:JsonValue):Bool {
        if (jsonKind(v) != 3)
            return false;
        var xs = jarray(v);
        for (i in 0...xs.length)
            if (jsonKind(xs[i]) != 1)
                return false;
        return true;
    }

    /** The shape package.json gives each manifest key: dependency maps
        and engines map names to range strings, peerDependenciesMeta maps
        names to option objects, os and cpu list strings, and bin is one
        path or a map of command names to paths. A value of another shape
        would pass generation and fail at npm install. */
    static function npmManifestValueOk(key:String, v:JsonValue):Bool {
        if (key == "os" || key == "cpu")
            return stringList(v);
        if (key == "peerDependenciesMeta")
            return objectOf(v, 2);
        if (key == "bin")
            return jsonKind(v) == 1 || objectOf(v, 1);
        return objectOf(v, 1);
    }

    /** One npm name segment: lowercase letters, digits and -._~, not
        starting with . or _. This is the set npm accepts for new names,
        and it keeps the segment a single path component. */
    static function npmSegmentOk(s:String):Bool {
        if (s.length == 0)
            return false;
        var c0 = s.charCodeAt(0);
        if (c0 == 46 || c0 == 95)
            return false;
        for (i in 0...s.length) {
            var c = s.charCodeAt(i);
            if (!((c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c == 45 || c == 46 || c == 95 || c == 126))
                return false;
        }
        return true;
    }

    /** An npm name is `name` or `@scope/name`. The packument is written at
        npm/<name>, so a name outside this shape could leave the output
        directory or nest under another package. */
    static function npmNameOk(n:String):Bool {
        if (n.length > 214)
            return false;
        var ps = n.split("/");
        if (ps.length == 1)
            return npmSegmentOk(ps[0]);
        if (ps.length != 2 || !ps[0].startsWith("@"))
            return false;
        return npmSegmentOk(ps[0].substring(1, ps[0].length)) && npmSegmentOk(ps[1]);
    }

    static function readArtifacts(v:JsonValue, r:Release, pp:String):Bool {
        if (jsonKind(v) != 3) {
            fail(pp + ": artifacts must be array");
            return false;
        }
        return readArtifactArray(jarray(v), r, pp);
    }

    static function readArtifactArray(xs:Array<JsonValue>, r:Release, pp:String):Bool {
        for (xi in 0...xs.length)
            readArtifact(xs[xi], r, pp);
        return true;
    }

    /** The Maven artifactId one artifact entry declares. A metadata written
        before the field existed declares none, and the entry then belongs to
        the metadata's own name, which is the single artifactId of the old
        shape. */
    static function readArtifactId(entry:JsonValue, r:Release, pp:String):String {
        var declared = opt(entry, "artifactId");
        if (declared == null)
            return r.name;
        var id:String = declared;
        if (id == "" || id == "." || id == ".." || id.indexOf("/") >= 0)
            fail(pp + ": invalid artifactId");
        return id;
    }

    static function readArtifact(v:JsonValue, r:Release, pp:String):Bool {
        if (jsonKind(v) != 2) {
            fail(pp + ": invalid artifact");
            return false;
        }
        var fs = jobject(v);
        var entry = O(fs);
        r.artifacts.push(str(entry, "file"));
        r.artifactUrls.push(str(entry, "url"));
        r.artifactIds.push(readArtifactId(entry, r, pp));
        return true;
    }

    static function urlOk(u:String):Bool
        return u.startsWith("http://") || u.startsWith("https://");

    static function sortStrings(a:Array<String>):Void {
        for (i in 1...a.length) {
            var x = a[i], j = i - 1;
            while (j >= 0 && a[j] > x) {
                a[j + 1] = a[j];
                j = j - 1;
            }
            a[j + 1] = x;
        }
    }

    /** Semver comparison wrapped for the Rust lowering: catching the Semver
        fault keeps every Core function on the single CoreFault error enum. */
    static function compareVersions(a:String, b:String):Int {
        var out:Int = 0;
        try {
            out = Semver.compare(a, b);
        } catch (e:SemverException) {
            throw new CoreException(Config("invalid version in sort order"));
        }
        return out;
    }

    static function sortReleases(a:Array<Release>):Void {
        for (i in 1...a.length) {
            var x = a[i], j = i - 1;
            while (j >= 0 && compareVersions(a[j].version, x.version) > 0) {
                a[j + 1] = a[j];
                j = j - 1;
            }
            a[j + 1] = x;
        }
    }

    static function names(a:Array<Release>, p:String):Array<String> {
        var o:Array<String> = [];
        for (i in 0...a.length) {
            var r = a[i];
            if (r.platform == p && !o.has(r.name))
                o.push(r.name);
        }
        sortStrings(o);
        return o;
    }

    static function group(a:Array<Release>, p:String, n:String):Array<Release> {
        var o:Array<Release> = [];
        for (i in 0...a.length) {
            var r = a[i];
            if (r.platform == p && r.name == n)
                o.push(r);
        }
        sortReleases(o);
        return o;
    }

    static function latest(g:Array<Release>):String {
        var b:Null<Release> = null;
        for (i in 0...g.length) {
            var r = g[i];
            if (!Semver.isPrerelease(r.version) && (b == null || compareVersions(r.version, b.version) > 0))
                b = r;
        }
        if (b == null)
            b = g[g.length - 1];
        return b.version;
    }

    static function fields(r:Release):Array<JsonField> {
        var a:Array<JsonField> = [{name: "name", value: S(r.name)}, {name: "version", value: S(r.version)}];
        var lic = r.license;
        if (lic != null)
            a.push({name: "license", value: S(lic)});
        return a;
    }

    static function contentOf(records:Array<InputRecord>, path:String):String {
        var r = record(records, path);
        if (r != null)
            return r.content;
        fail(path + ": missing record");
        return "";
    }

    static function record(records:Array<InputRecord>, path:String):Null<InputRecord> {
        for (ri in 0...records.length) {
            var r = records[ri];
            if (r.path == path)
                return r;
        }
        return null;
    }

    static function children(records:Array<InputRecord>, path:String):Array<String> {
        var out:Array<String> = [];
        var prefix = path == "" ? "" : path + "/";
        for (ri in 0...records.length) {
            var r = records[ri];
            if (!r.path.startsWith(prefix))
                continue;
            var rest = r.path.substring(prefix.length),
                part = rest.split("/")[0];
            if (!out.has(part))
                out.push(part);
        }
        sortStrings(out);
        return out;
    }

    static function scan(tree:String, records:Array<InputRecord>):Array<Release> {
        var out:Array<Release> = [];
        if (records.length == 0)
            fail(tree + ": missing tree");
        var owners = children(records, "");
        for (oi in 0...owners.length) {
            var owner = owners[oi];
            var op = owner;
            if (record(records, op) != null)
                fail(tree + "/" + op + ": stray file");
            var repos = children(records, op);
            for (repi in 0...repos.length) {
                var repo = repos[repi];
                var rp = op + "/" + repo;
                if (record(records, rp) != null || record(records, rp + "/README.md") == null)
                    fail(tree + "/" + rp + ": missing README.md");
                var count = 0;
                var versions = children(records, rp);
                for (vi in 0...versions.length) {
                    var v = versions[vi];
                    if (v == "README.md")
                        continue;
                    count = count + 1;
                    var vp = rp + "/" + v;
                    if (record(records, vp) != null)
                        fail(tree + "/" + vp + ": stray file");
                    var platforms = children(records, vp);
                    for (pi in 0...platforms.length) {
                        var p = platforms[pi];
                        var pp = vp + "/" + p;
                        if (!["npm", "cargo", "pub", "swift", "maven"].has(p))
                            fail(tree + "/" + pp + ": unknown platform");
                        var files = children(records, pp);
                        if (record(records, pp) != null || files.length != 1 || files[0] != "metadata.json")
                            fail(tree + "/" + pp + ": expected metadata.json");
                        var j:JsonValue = readMetadata(contentOf(records, pp + "/metadata.json"), tree + "/" + pp);
                        var r = new Release(owner, repo, v, p, str(j, "name"), opt(j, "license"), contentOf(records, rp + "/README.md"));
                        r.repository = opt(j, "repository");
                        if (str(j, "version") != v)
                            fail(tree + "/" + pp + ": version disagreement");
                        if (Semver.parse(v) == null)
                            fail(tree + "/" + pp + ": invalid version");
                        if (p == "npm") {
                            r.url = str(j, "url");
                            r.digest = str(j, "sha512");
                            r.npmManifest = readNpmManifest(j, tree + "/" + pp);
                        } else if (p == "cargo" || p == "pub") {
                            r.url = str(j, "url");
                            r.digest = str(j, "sha256");
                            if (p == "pub")
                                r.pubspec = get(j, "pubspec");
                            else
                                r.features = readFeatures(j, tree + "/" + pp);
                        } else if (p == "swift") {
                            r.archive = str(j, "archive");
                            r.digest = str(j, "sha256");
                            r.packageSwift = str(j, "packageSwift");
                        } else {
                            r.groupId = str(j, "groupId");
                            readArtifacts(get(j, "artifacts"), r, tree + "/" + pp);
                        }
                        var ru2 = r.url;
                        if (ru2 != null && !urlOk(ru2))
                            fail(tree + "/" + pp + ": invalid URL");
                        out.push(r);
                    }
                }
                if (count == 0)
                    fail(tree + "/" + rp + ": repository has no versions");
            }
        }
        return out;
    }

    static function writeNpm(out:Array<OutputFile>, a:Array<Release>):Void {
        var ns = names(a, "npm");
        for (ni in 0...ns.length) {
            var n = ns[ni], g = group(a, "npm", n), vs:Array<JsonField> = [];
            for (i in 0...g.length) {
                var r = g[i], f = fields(r), ru = r.url, u:String = ru == null ? "" : ru, rm = r.npmManifest;
                if (rm != null) {
                    var keys = npmManifestKeys();
                    for (ki in 0...keys.length) {
                        var mv = get(rm, keys[ki]);
                        if (jsonKind(mv) != 0)
                            f.push({name: keys[ki], value: mv});
                    }
                }
                f.push({
                    name: "dist",
                    value: O([
                        {name: "tarball", value: S(u)},
                        {name: "integrity", value: S("sha512-" + r.digest)}
                    ])
                });
                vs.push({name: r.version, value: O(f)});
            }
            // npm requests a scoped package as @scope%2fname. The host
            // decodes %2f before the file lookup, so the file sits at the
            // decoded path @scope/name, which also serves clients that
            // send the slash unencoded.
            emit(out, "npm/" + n, Json.write(O([
                {name: "name", value: S(n)},
                {name: "dist-tags", value: O([{name: "latest", value: S(latest(g))}])},
                {name: "versions", value: O(vs)},
                {name: "readme", value: S(g[0].readme)}
            ])));
        }
    }

    static function writePub(out:Array<OutputFile>, a:Array<Release>):Void {
        var ns = names(a, "pub");
        for (ni in 0...ns.length) {
            var n = ns[ni], g = group(a, "pub", n), vs:Array<JsonValue> = [];
            for (i in 0...g.length) {
                var r = g[i], ru = r.url, u:String = ru == null ? "" : ru, rpp = r.pubspec;
                vs.push(O([
                    {name: "version", value: S(r.version)},
                    {name: "archive_url", value: S(u)},
                    {name: "archive_sha256", value: S(r.digest)},
                    {name: "pubspec", value: rpp == null ? JNull : rpp}
                ]));
            }
            var rev:Array<JsonValue> = [];
            var vi2 = g.length - 1;
            while (vi2 >= 0) {
                rev.push(vs[vi2]);
                vi2 = vi2 - 1;
            }
            emit(out, "pub/api/packages/" + n, Json.write(O([
                {name: "name", value: S(n)},
                // The hosted pub API expects the latest version entry here,
                // not its version string.
                {name: "latest", value: rev.length > 0 ? rev[0] : JNull},
                {name: "versions", value: A(rev)}
            ])));
        }
    }

    static function writeCargo(out:Array<OutputFile>, base:String, a:Array<Release>):Void {
        emit(out, "cargo/index/config.json", Json.write(O([{name: "dl", value: S(base + "/cargo/dl/{crate}-{version}.crate")}])));
        var ns = names(a, "cargo");
        for (ni in 0...ns.length) {
            var n = ns[ni];
            var g = group(a, "cargo", n), lines:Array<String> = [];
            for (ri in 0...g.length) {
                var r = g[ri], rf = r.features;
                lines.push(Json.writeCompact(O([
                    {name: "name", value: S(n)},
                    {name: "vers", value: S(r.version)},
                    {name: "deps", value: A([])},
                    {name: "cksum", value: S(r.digest)},
                    {name: "features", value: rf == null ? O([]) : rf},
                    {name: "yanked", value: JBool(false)},
                    {name: "v", value: JNumber(2.0)}
                ])));
            }
            emit(
                out,
                "cargo/index/"
                + (n.length == 1 ? "1/" : n.length == 2 ? "2/" : n.length == 3 ? "3/" + n.substring(0, 1) + "/" : n.substring(0, 2)
                    + "/"
                    + n.substring(2, 4)
                    + "/")
                + n,
                lines.join("\n")
                + "\n");
        }
    }

    static function writeSwift(out:Array<OutputFile>, scope:String, a:Array<Release>):Void {
        var ns = names(a, "swift");
        for (ni in 0...ns.length) {
            var n = ns[ni], g = group(a, "swift", n), rs:Array<JsonField> = [];
            for (i in 0...g.length)
                rs.push({name: g[i].version, value: O([])});
            emit(out, "swift/" + scope + "/" + n + ".json", Json.write(O([{name: "releases", value: O(rs)}])));
            for (i in 0...g.length) {
                var r = g[i], rps = r.packageSwift, ps:String = rps == null ? "" : rps;
                emit(out, "swift/" + scope + "/" + n + "/" + r.version + ".json", Json.write(O([
                    {name: "id", value: S(scope + "." + n)},
                    {name: "version", value: S(r.version)},
                    {
                        name: "resources",
                        value: A([
                            O([
                                {name: "name", value: S("source-archive")},
                                {name: "type", value: S("application/zip")},
                                {name: "checksum", value: S(r.digest)}
                            ])
                        ])
                    },
                    {name: "metadata", value: O([])}
                ])));
                emit(out, "swift/" + scope + "/" + n + "/" + r.version + "/Package.swift", ps);
            }
        }
    }

    /** The artifactId one artifact file of a release belongs to. The reader
        pushes one artifactId per artifact file in the same order. */
    static function mavenArtifactId(r:Release, i:Int):String {
        if (i < r.artifactIds.length)
            return r.artifactIds[i];
        return r.name;
    }

    /** The artifactIds one Maven package directory carries, one per Maven
        module, sorted. An entry with no artifact list falls back to the
        metadata name, which is the single artifactId of the old shape. */
    static function mavenArtifactIds(g:Array<Release>):Array<String> {
        var ids:Array<String> = [];
        for (ri in 0...g.length) {
            var r = g[ri];
            if (r.artifactIds.length == 0) {
                if (!ids.has(r.name))
                    ids.push(r.name);
            } else
                for (ai in 0...r.artifactIds.length)
                    if (!ids.has(r.artifactIds[ai]))
                        ids.push(r.artifactIds[ai]);
        }
        sortStrings(ids);
        return ids;
    }

    /** The releases of one package directory that publish one artifactId.
        An entry with no artifact list declares its name as its artifactId. */
    static function mavenReleases(g:Array<Release>, artifactId:String):Array<Release> {
        var out:Array<Release> = [];
        for (ri in 0...g.length) {
            var r = g[ri];
            if (r.artifactIds.length == 0 ? r.name == artifactId : r.artifactIds.has(artifactId))
                out.push(r);
        }
        return out;
    }

    /** One maven-metadata.xml per artifactId. The site path is the groupId
        path plus the artifactId, so the artifactIds of one package directory
        coexist under the same groupId directory. */
    static function writeMaven(out:Array<OutputFile>, a:Array<Release>):Void {
        var ns = names(a, "maven");
        for (ni in 0...ns.length) {
            var n = ns[ni], g = group(a, "maven", n), first = g[0], fg = first.groupId, groupId:String = fg == null ? "" : fg;
            var ids = mavenArtifactIds(g);
            for (ii in 0...ids.length) {
                var id = ids[ii], ig = mavenReleases(g, id), versions:Array<String> = [];
                for (ri in 0...ig.length) {
                    var ir = ig[ri];
                    if (!versions.has(ir.version))
                        versions.push(ir.version);
                }
                sortStrings(versions);
                var path = groupId.split(".").join("/") + "/" + id,
                    xml = "<metadata>\n  <groupId>" + groupId + "</groupId>\n  <artifactId>" + id + "</artifactId>\n  <versioning>\n    <latest>"
                        + latest(ig) + "</latest>\n    <release>" + latest(ig) + "</release>\n    <versions>\n";
                for (vi in 0...versions.length) {
                    var v = versions[vi];
                    xml += "      <version>" + v + "</version>\n";
                }
                xml += "    </versions>\n  </versioning>\n</metadata>\n";
                emit(out, "maven/" + path + "/maven-metadata.xml", xml);
                emit(out, "maven/" + path + "/maven-metadata.xml.sha1", Sha1.hex(xml) + "\n");
            }
        }
    }

    /** The groupId of a Maven release; the reader requires one. */
    static function mavenGroup(r:Release):String {
        var rg = r.groupId;
        var g:String = rg == null ? "" : rg;
        return g;
    }

    /** The GitHub repository whose releases hold a Maven release's files. */
    static function mavenTarget(r:Release):String {
        var rr = r.repository;
        var t:String = rr == null ? r.owner + "/" + r.repo : rr;
        return t;
    }

    static function mavenGroupIds(a:Array<Release>):Array<String> {
        var out:Array<String> = [];
        for (ai in 0...a.length) {
            var r = a[ai];
            if (r.platform == "maven" && !out.has(mavenGroup(r)))
                out.push(mavenGroup(r));
        }
        sortStrings(out);
        return out;
    }

    /** The artifactIds of one groupId that have files, sorted. */
    static function mavenFileArtifactIds(a:Array<Release>, gid:String):Array<String> {
        var out:Array<String> = [];
        for (ai in 0...a.length) {
            var r = a[ai];
            if (r.platform == "maven" && mavenGroup(r) == gid)
                for (fi in 0...r.artifacts.length)
                    if (!out.has(mavenArtifactId(r, fi)))
                        out.push(mavenArtifactId(r, fi));
        }
        sortStrings(out);
        return out;
    }

    /** The repositories that publish files of one coordinate, across every
        version. */
    static function mavenOwners(a:Array<Release>, gid:String, id:String):Array<String> {
        var out:Array<String> = [];
        for (ai in 0...a.length) {
            var r = a[ai];
            if (r.platform == "maven" && mavenGroup(r) == gid)
                for (fi in 0...r.artifacts.length)
                    if (mavenArtifactId(r, fi) == id && !out.has(mavenTarget(r)))
                        out.push(mavenTarget(r));
        }
        return out;
    }

    static function mavenRule(path:String, target:String, version:String):String
        return path + "/:file  https://github.com/" + target + "/releases/download/v" + version + "/:file  302";

    /** The Maven redirect rules. A file request is
        `<group path>/<artifactId>/<version>/<file>` and the release asset is
        `v<version>/<file>` in the publishing repository, so a rule names a
        version or a file only when it must. A groupId whose files all come
        from one repository, and under which no other registered groupId
        nests, gets one rule for every artifactId and version. Otherwise each
        artifactId published from one repository gets one rule, and an
        artifactId whose repository changed between versions gets one rule
        per version. Every rule matches exactly three segments below its
        group path. The nesting check keeps a parent rule from matching
        `<child path>/<artifactId>/maven-metadata.xml`, which sits three
        segments below the parent path. An artifactId that is also the next
        segment of a nested groupId (`sub` beside `<group>.sub`) gets one
        exact rule per file instead: `<group path>/sub/:version/:file` would
        match `<group path>/sub/<artifactId>/maven-metadata.xml`. */
    static function mavenRules(a:Array<Release>):Array<String> {
        var out:Array<String> = [];
        var gids = mavenGroupIds(a);
        for (gi in 0...gids.length) {
            var gid = gids[gi], gpath = "/maven/" + gid.split(".").join("/") + "/", ids = mavenFileArtifactIds(a, gid);
            var nested = false;
            for (oi in 0...gids.length)
                if (gids[oi].startsWith(gid + "."))
                    nested = true;
            var owners:Array<String> = [];
            for (ii in 0...ids.length) {
                var os = mavenOwners(a, gid, ids[ii]);
                for (oi in 0...os.length)
                    if (!owners.has(os[oi]))
                        owners.push(os[oi]);
            }
            if (!nested && owners.length == 1) {
                out.push(mavenRule(gpath + ":artifact/:version", owners[0], ":version"));
                continue;
            }
            for (ii in 0...ids.length) {
                var id = ids[ii], os = mavenOwners(a, gid, id);
                if (gids.has(gid + "." + id)) {
                    var exact:Array<String> = [];
                    for (ai in 0...a.length) {
                        var r = a[ai];
                        if (r.platform == "maven" && mavenGroup(r) == gid)
                            for (fi in 0...r.artifacts.length) {
                                var file = r.artifacts[fi], from = gpath + id + "/" + r.version + "/" + file;
                                if (mavenArtifactId(r, fi) == id && !exact.has(from)) {
                                    exact.push(from);
                                    out.push(from + "  https://github.com/" + mavenTarget(r) + "/releases/download/v" + r.version + "/" + file + "  302");
                                }
                            }
                    }
                    continue;
                }
                if (os.length == 1) {
                    out.push(mavenRule(gpath + id + "/:version", os[0], ":version"));
                    continue;
                }
                var versions:Array<String> = [];
                for (ai in 0...a.length) {
                    var r = a[ai];
                    if (r.platform == "maven" && mavenGroup(r) == gid && !versions.has(r.version))
                        for (fi in 0...r.artifacts.length)
                            if (mavenArtifactId(r, fi) == id && !versions.has(r.version)) {
                                versions.push(r.version);
                                out.push(mavenRule(gpath + id + "/" + r.version, mavenTarget(r), r.version));
                            }
                }
            }
        }
        return out;
    }

    static function redirects(scope:String, archiveBase:String, a:Array<Release>):String {
        var lines:Array<String> = [
            "/swift/:scope/:name/*.zip  " + archiveBase + "/swift/:scope/:name/:splat.zip  303"
        ];
        var sn = names(a, "swift");
        for (ni in 0...sn.length) {
            var n = sn[ni];
            lines.push("/swift/" + scope + "/" + n + "  /swift/" + scope + "/" + n + ".json  200");
            var sg = group(a, "swift", n);
            for (ri in 0...sg.length) {
                var r = sg[ri];
                lines.push("/swift/" + scope + "/" + n + "/" + r.version + "  /swift/" + scope + "/" + n + "/" + r.version + ".json  200");
            }
        }
        var cn = names(a, "cargo");
        for (ni in 0...cn.length) {
            var n = cn[ni];
            var r = group(a, "cargo", n)[0];
            final cargoTarget = r.repository == null ? r.owner + "/" + r.repo : r.repository;
        lines.push("/cargo/dl/" + n + "-:version.crate  https://github.com/" + cargoTarget + "/releases/download/v:version/" + n
                + "-:version.crate  302");
        }
        var mavenLines = mavenRules(a);
        for (mi in 0...mavenLines.length)
            lines.push(mavenLines[mi]);
        var moving = 0;
        var fixed = 0;
        for (li in 0...lines.length) {
            // Cloudflare counts a rule as dynamic when its source path has a
            // placeholder or a splat, whatever its status code.
            var source = lines[li].split("  ")[0];
            if (source.indexOf(":") >= 0 || source.indexOf("*") >= 0)
                moving = moving + 1;
            else
                fixed = fixed + 1;
        }
        if (moving > 100)
            fail("too many dynamic redirects (Cloudflare allows 100)");
        if (fixed > 2000)
            fail("too many static redirects (Cloudflare allows 2000)");
        return lines.join("\n") + "\n";
    }

    static function validate(a:Array<Release>, scope:String):Void {
        for (i in 0...a.length) {
            var x = a[i];
            if (x.platform == "cargo" && x.name != x.name.toLowerCase())
                fail(x.name + ": cargo name must be lowercase");
            if (x.platform == "npm" && !npmNameOk(x.name))
                fail(x.owner + "/" + x.repo + "/" + x.version + ": invalid npm name " + x.name);
        }
        for (i in 0...a.length) {
            var x = a[i];
            for (j in 0...i) {
                var y = a[j];
                if (x.owner == y.owner && x.repo == y.repo && x.version == y.version && (x.name != y.name || x.license != y.license))
                    fail(x.owner + "/" + x.repo + "/" + x.version + ": platform disagreement");
            }
        }
        for (i in 0...a.length) {
            var x = a[i];
            if (x.platform == "swift" && x.archive != "swift/" + scope + "/" + x.name + "/" + x.version + ".zip")
                fail(x.owner + "/" + x.repo + "/" + x.version + ": invalid Swift archive");
        }
        for (i in 0...a.length) {
            var x = a[i];
            for (j in 0...i) {
                var y = a[j];
                if (x.platform == y.platform && x.name == y.name && x.version == y.version && x.digest != y.digest)
                    fail(x.owner + "/" + x.repo + "/" + x.version + ": digest conflict with " + y.owner + "/" + y.repo);
            }
        }
    }

    static function headers():String
        return "/*\n  Content-Version: 1\n/swift/:scope/:name\n  Content-Type: application/json\n/swift/:scope/:name/:version\n  Content-Type: application/json\n/swift/:scope/:name/:version/Package.swift\n  Content-Type: text/x-swift\n/pub/api/packages/*\n  Content-Type: application/vnd.pub.v2+json\n/swift/identifiers\n  Content-Type: application/json\n";

    public static var files:Array<OutputFile> = [];

    static function emit(out:Array<OutputFile>, rel:String, data:String):Void {
        var file:OutputFile = {path: rel, content: data, outputFile: 1};
        out.push(file);
    }

    public static function parseArgs(argv:Array<String>):RegistryConfig {
        var t:Null<String> = null, o:Null<String> = null, b:Null<String> = null, s:Null<String> = null, ar:Null<String> = null, i = 0;
        while (i < argv.length) {
            if (i + 1 >= argv.length)
                configFail(USAGE);
            var flag = argv[i], value = argv[i + 1];
            if (value == "")
                configFail("empty value for " + flag);
            if (flag == "--tree")
                t = value;
            else if (flag == "--output")
                o = value;
            else if (flag == "--base-url")
                b = value;
            else if (flag == "--swift-scope")
                s = value;
            else if (flag == "--archive-base")
                ar = value;
            else if (flag == "--help" || flag == "-h")
                configFail(USAGE);
            else
                configFail("unknown flag " + flag);
            i += 2;
        }
        if (t == null || o == null || b == null)
            configFail("required flags missing\n" + USAGE);
        var treeStr:String = t == null ? "" : t,
            outputStr:String = o == null ? "" : o,
            baseUrlStr:String = b == null ? "" : b;
        if (!urlOk(baseUrlStr))
            configFail("invalid base URL (http or https required)");
        var swiftStr:String = s == null ? "" : s,
            archiveStr:String = ar == null ? "" : ar;
        if (ar != null && !urlOk(archiveStr))
            configFail("invalid archive-base URL (http or https required)");
        var config:RegistryConfig = {
            tree: treeStr,
            output: outputStr,
            baseUrl: baseUrlStr,
            swiftScope: swiftStr,
            archiveBase: archiveStr,
            configRecord: 1
        };
        return config;
    }

    public static function generate(records:Array<InputRecord>, config:RegistryConfig):Array<OutputFile> {
        final out:Array<OutputFile> = [];
        var all = scan(config.tree, records);
        if (names(all, "swift").length > 0 && config.swiftScope == "")
            fail("Swift requires --swift-scope");
        if (names(all, "swift").length > 0 && config.archiveBase == "")
            fail("Swift requires --archive-base");
        validate(all, config.swiftScope);
        writeNpm(out, all);
        writePub(out, all);
        writeCargo(out, config.baseUrl, all);
        if (names(all, "swift").length > 0)
            writeSwift(out, config.swiftScope, all);
        writeMaven(out, all);
        emit(out, "swift/identifiers", Json.write(A([])));
        emit(out, "_headers", headers());
        emit(out, "_redirects", redirects(config.swiftScope, config.archiveBase, all));
        files = out.copy();
        return out;
    }
}
