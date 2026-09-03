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
   {path:"alice/one/README.md", content:"One package\n", inputRecord:1},
   {path:"alice/one/1.0.0/npm/metadata.json", content:'{"name":"one","version":"1.0.0","url":"https://example.test/one.tgz","sha512":"digest"}', inputRecord:1},
   {path:"bob/two/README.md", content:"Two package\n", inputRecord:1},
   {path:"bob/two/2.0.0/cargo/metadata.json", content:'{"name":"two","version":"2.0.0","url":"https://example.test/two.crate","sha256":"checksum"}', inputRecord:1}
  ];
  var config:RegistryConfig = {tree:"tree", output:"site", baseUrl:"https://registry.test", swiftScope:"scope", archiveBase:"https://archive.test", configRecord:1};
  var files:Array<OutputFile> = Core.generate(records, config);
  var expected:Array<OutputFile> = [
   {path:"npm/one", content:'{\n  "name": "one",\n  "dist-tags": {\n    "latest": "1.0.0"\n  },\n  "versions": {\n    "1.0.0": {\n      "name": "one",\n      "version": "1.0.0",\n      "dist": {\n        "tarball": "https://example.test/one.tgz",\n        "integrity": "sha512-digest"\n      }\n    }\n  },\n  "readme": "One package\\n"\n}\n', outputFile:1},
   {path:"cargo/index/config.json", content:'{\n  "dl": "https://registry.test/cargo/dl/{crate}-{version}.crate"\n}\n', outputFile:1},
   {path:"cargo/index/3/t/two", content:'{"name":"two","vers":"2.0.0","deps":[],"cksum":"checksum","features":{},"yanked":false,"v":2}\n', outputFile:1},
   {path:"swift/identifiers", content:"[]\n", outputFile:1},
   {path:"_headers", content:"/*\n  Content-Version: 1\n/swift/:scope/:name\n  Content-Type: application/json\n/swift/:scope/:name/:version\n  Content-Type: application/json\n/swift/:scope/:name/:version/Package.swift\n  Content-Type: text/x-swift\n/pub/api/packages/*\n  Content-Type: application/vnd.pub.v2+json\n/swift/identifiers\n  Content-Type: application/json\n", outputFile:1},
   {path:"_redirects", content:"/swift/:scope/:name/*.zip  https://archive.test/swift/:scope/:name/:splat.zip  303\n/cargo/dl/two-:version.crate  https://github.com/bob/two/releases/download/v:version/two-:version.crate  302\n", outputFile:1}
  ];
  Test.equals(expected.length, files.length);
  for(i in 0...expected.length) { Test.equals(expected[i].path, files[i].path); Test.equals(expected[i].content, files[i].content); }
 }
}
