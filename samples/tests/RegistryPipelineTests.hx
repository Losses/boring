package tests;

import registry.Core;
import registry.CoreException;
import registry.Core.InputRecord;
import registry.Core.OutputFile;
import registry.Core.RegistryConfig;
import std.Test;

class RegistryPipelineTests {
    @:test("pipeline generates literal registry files")
    public static function generatesFiles():Void {
        var records:Array<InputRecord> = [
            {path: "alice/one/README.md", content: "One package\n", inputRecord: 1},
            {
                path: "alice/one/1.0.0/npm/metadata.json",
                content: '{"name":"one","version":"1.0.0","url":"https://example.test/one.tgz","sha512":"digest"}',
                inputRecord: 1
            },
            {path: "bob/two/README.md", content: "Two package\n", inputRecord: 1},
            {
                path: "bob/two/2.0.0/cargo/metadata.json",
                content: '{"name":"two","version":"2.0.0","url":"https://example.test/two.crate","sha256":"checksum","features":{"f32":[]}}',
                inputRecord: 1
            }
        ];
        var config:RegistryConfig = {
            tree: "tree",
            output: "site",
            baseUrl: "https://registry.test",
            swiftScope: "scope",
            archiveBase: "https://archive.test",
            configRecord: 1
        };
        var files:Array<OutputFile> = Core.generate(records, config);
        var expected:Array<OutputFile> = [
            {
                path: "npm/one",
                content: '{\n  "name": "one",\n  "dist-tags": {\n    "latest": "1.0.0"\n  },\n  "versions": {\n    "1.0.0": {\n      "name": "one",\n      "version": "1.0.0",\n      "dist": {\n        "tarball": "https://example.test/one.tgz",\n        "integrity": "sha512-digest"\n      }\n    }\n  },\n  "readme": "One package\\n"\n}\n',
                outputFile: 1
            },
            {path: "cargo/index/config.json", content: '{\n  "dl": "https://registry.test/cargo/dl/{crate}-{version}.crate"\n}\n', outputFile: 1},
            {
                path: "cargo/index/3/t/two",
                content: '{"name":"two","vers":"2.0.0","deps":[],"cksum":"checksum","features":{"f32":[]},"yanked":false,"v":2}\n',
                outputFile: 1
            },
            {path: "swift/identifiers", content: "[]\n", outputFile: 1},
            {
                path: "_headers",
                content: "/*\n  Content-Version: 1\n/swift/:scope/:name\n  Content-Type: application/json\n/swift/:scope/:name/:version\n  Content-Type: application/json\n/swift/:scope/:name/:version/Package.swift\n  Content-Type: text/x-swift\n/pub/api/packages/*\n  Content-Type: application/vnd.pub.v2+json\n/swift/identifiers\n  Content-Type: application/json\n",
                outputFile: 1
            },
            {
                path: "_redirects",
                content: "/swift/:scope/:name/*.zip  https://archive.test/swift/:scope/:name/:splat.zip  303\n/cargo/dl/two-:version.crate  https://github.com/bob/two/releases/download/v:version/two-:version.crate  302\n",
                outputFile: 1
            }
        ];
        Test.equals(expected.length, files.length);
        for (i in 0...expected.length) {
            Test.equals(expected[i].path, files[i].path);
            Test.equals(expected[i].content, files[i].content);
        }
    }

    @:test("cargo index declares an empty feature map when metadata omits it")
    public static function featuresFallBackToEmpty():Void {
        var records:Array<InputRecord> = [
            {path: "carol/plain/README.md", content: "Plain package\n", inputRecord: 1},
            {
                path: "carol/plain/1.0.0/cargo/metadata.json",
                content: '{"name":"plain","version":"1.0.0","url":"https://example.test/plain.crate","sha256":"checksum"}',
                inputRecord: 1
            }
        ];
        var config:RegistryConfig = {
            tree: "tree",
            output: "site",
            baseUrl: "https://registry.test",
            swiftScope: "scope",
            archiveBase: "https://archive.test",
            configRecord: 1
        };
        var files:Array<OutputFile> = Core.generate(records, config);
        var found = false;
        for (i in 0...files.length) {
            if (files[i].path == "cargo/index/pl/ai/plain") {
                found = true;
                Test.equals('{"name":"plain","vers":"1.0.0","deps":[],"cksum":"checksum","features":{},"yanked":false,"v":2}\n', files[i].content);
            }
        }
        Test.equals(true, found);
    }

    @:test("maven metadata carries one artifactId per maven module")
    public static function mavenArtifactIdsCoexist():Void {
        var records:Array<InputRecord> = [
            {path: "dana/engine/README.md", content: "Engine package\n", inputRecord: 1},
            {
                path: "dana/engine/1.0.0/maven/metadata.json",
                content: '{"name":"engine","version":"1.0.0","groupId":"dev.dana","license":"MIT","repository":"dana/engine","tag":"v1.0.0","artifacts":['
                    + '{"file":"engine-1.0.0.pom","url":"https://example.test/engine-1.0.0.pom","artifactId":"engine"},'
                    + '{"file":"engine-jvm-1.0.0.pom","url":"https://example.test/engine-jvm-1.0.0.pom","artifactId":"engine-jvm"},'
                    + '{"file":"engine-jvm-1.0.0.module","url":"https://example.test/engine-jvm-1.0.0.module","artifactId":"engine-jvm"}]}',
                inputRecord: 1
            }
        ];
        var config:RegistryConfig = {
            tree: "tree",
            output: "site",
            baseUrl: "https://registry.test",
            swiftScope: "scope",
            archiveBase: "https://archive.test",
            configRecord: 1
        };
        var files:Array<OutputFile> = Core.generate(records, config);
        var rootXml = "<metadata>\n  <groupId>dev.dana</groupId>\n  <artifactId>engine</artifactId>\n  <versioning>\n    <latest>1.0.0</latest>\n    <release>1.0.0</release>\n    <versions>\n      <version>1.0.0</version>\n    </versions>\n  </versioning>\n</metadata>\n";
        var jvmXml = "<metadata>\n  <groupId>dev.dana</groupId>\n  <artifactId>engine-jvm</artifactId>\n  <versioning>\n    <latest>1.0.0</latest>\n    <release>1.0.0</release>\n    <versions>\n      <version>1.0.0</version>\n    </versions>\n  </versioning>\n</metadata>\n";
        var rootFound = false, jvmFound = false;
        for (i in 0...files.length) {
            if (files[i].path == "maven/dev/dana/engine/maven-metadata.xml") {
                rootFound = true;
                Test.equals(rootXml, files[i].content);
            } else if (files[i].path == "maven/dev/dana/engine-jvm/maven-metadata.xml") {
                jvmFound = true;
                Test.equals(jvmXml, files[i].content);
            } else if (files[i].path == "_redirects") {
                Test.ok(files[i].content.indexOf("/maven/dev/dana/engine/:version/engine-1.0.0.pom") >= 0, "root redirect");
                Test.ok(files[i].content.indexOf("/maven/dev/dana/engine-jvm/:version/engine-jvm-1.0.0.pom") >= 0, "jvm pom redirect");
                Test.ok(files[i].content.indexOf("/maven/dev/dana/engine-jvm/:version/engine-jvm-1.0.0.module") >= 0, "jvm module redirect");
            }
        }
        Test.equals(true, rootFound);
        Test.equals(true, jvmFound);
    }

    @:test("maven metadata without artifactId falls back to the package name")
    public static function mavenSingleArtifactIdFallback():Void {
        var records:Array<InputRecord> = [
            {path: "dana/legacy/README.md", content: "Legacy package\n", inputRecord: 1},
            {
                path: "dana/legacy/1.0.0/maven/metadata.json",
                content: '{"name":"legacy","version":"1.0.0","groupId":"dev.dana","license":"MIT","repository":"dana/legacy","tag":"v1.0.0","artifacts":[{"file":"legacy-1.0.0.pom","url":"https://example.test/legacy-1.0.0.pom"}]}',
                inputRecord: 1
            }
        ];
        var config:RegistryConfig = {
            tree: "tree",
            output: "site",
            baseUrl: "https://registry.test",
            swiftScope: "scope",
            archiveBase: "https://archive.test",
            configRecord: 1
        };
        var files:Array<OutputFile> = Core.generate(records, config);
        var legacyXml = "<metadata>\n  <groupId>dev.dana</groupId>\n  <artifactId>legacy</artifactId>\n  <versioning>\n    <latest>1.0.0</latest>\n    <release>1.0.0</release>\n    <versions>\n      <version>1.0.0</version>\n    </versions>\n  </versioning>\n</metadata>\n";
        var legacyFound = false;
        for (i in 0...files.length) {
            if (files[i].path == "maven/dev/dana/legacy/maven-metadata.xml") {
                legacyFound = true;
                Test.equals(legacyXml, files[i].content);
            } else if (files[i].path == "_redirects")
                Test.ok(files[i].content.indexOf("/maven/dev/dana/legacy/:version/legacy-1.0.0.pom") >= 0, "legacy redirect");
        }
        Test.equals(true, legacyFound);
    }
}
