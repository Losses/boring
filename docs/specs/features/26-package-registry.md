# Feature spec 26: Package registry generation

## Scope

Feature spec 25 made one compilation emit the install unit of its
target's ecosystem. This specification rules the next step: a
generation tool that turns a directory of those artifacts into one
static, read-only registry site serving all five ecosystems from one
deployment. The site holds npm packuments and tarballs, the cargo
sparse index and crate files, the Swift package registry endpoints, the
Pub hosted repository API, and the Maven repository directory. Every
client tool configures one base URL and installs from the site.

The tool is separate from the compiler because a registry aggregates
releases across compilations: one compilation holds one package at one
version and cannot know which other releases exist. The compiler's
responsibility ended at the install unit; the registry is a property of
the release store, so the release store is the input.

The registry is public and read-only. No ecosystem's publish or upload
endpoint exists on the site; publication is adding artifacts to the
store, regenerating, and redeploying. The target host is a static file
server that applies a `_headers` file (Cloudflare Pages or Netlify).
GitHub Pages serves no custom response headers, so it can serve the
npm, cargo, and Maven namespaces, whose consumers check no media types,
but it cannot serve the Swift and Pub lanes: the Swift client validates
the response media type and API version on every endpoint, and the Pub
protocol assigns its JSON a media type no file extension produces.

## Command line

```
bun tools/registry/generate.ts --input <store> --output <site> --base-url <url> [--swift-scope <scope>]
```

- `--input`: the release store, a directory holding artifacts named as
  spec 25 writes them, at any depth. Discovery is by extension and
  directory name: `.tgz` is npm, `.crate` is cargo, `.zip` is Swift,
  `.tar.gz` is Pub, and a directory named `maven` is a Kotlin
  repository tree. The store belongs to this pipeline; the extensions
  are the type tags.
- `--output`: the site directory. It must be absent or empty; the tool
  stops with an error otherwise, so a stale site can never mix with a
  fresh generation.
- `--base-url`: the public origin (scheme, host, optional path prefix)
  the clients use. A trailing slash is removed. The npm `dist.tarball`
  URLs, the cargo `dl` template, and the Pub `archive_url` values embed
  it.
- `--swift-scope`: required when the store holds a `.zip`. Validated
  against the registry specification's scope pattern
  `\A[a-zA-Z0-9](?:[a-zA-Z0-9]|-(?=[a-zA-Z0-9])){0,38}\z`.

Every rejection names the input path and the reason, and the tool exits
nonzero: an identity conflict between two artifacts claiming the same
package and version with different bytes, a `pubspec.yaml` key outside
the spec 24 grammar, a version outside semver, an uppercase cargo name,
a base URL without an `http` or `https` scheme, an output directory
that holds files, and a `_headers` rule count over the host cap.

## Output layout

| Namespace | Contents | Client configuration |
| --- | --- | --- |
| `/npm/` | one packument per package at its request path; tarballs under `npm/files/` | `npm --registry=<base>/npm/` |
| `/cargo/` | `cargo/index/config.json`; index entries under the prefix tier; crates under `cargo/dl/` | a named registry in `.cargo/config.toml`: `index = "sparse+<base>/cargo/index/"` |
| `/swift/` | releases and metadata JSON, `Package.swift`, zips, `identifiers` | `swift package-registry set <base>/swift/` |
| `/pub/` | `pub/api/packages/<name>` JSON; archives under `pub/files/` | `PUB_HOSTED_URL=<base>/pub/` |
| `/maven/` | the repository directory of spec 25 plus `maven-metadata.xml` per artifact | Gradle `maven { url("<base>/maven/") }` |

The site root also carries the generated `_headers` file.

## Candidate translations

### Candidate 1: A generation tool in this repository

One command reads the release store and writes the complete site: all
five namespaces plus `_headers`, ready to deploy.

- performance: one process per generation; the site serves static
  files with no server code.
- ambiguity: every registry document derives from artifact bytes by
  fixed rules; two generations of one store produce identical sites.
- redundancy: one implementation serves every ecosystem's read
  protocol.
- readability: the site is an ordinary directory tree; each document
  is inspectable and diffable.

### Candidate 2: Run each ecosystem's registry server

 Verdaccio for npm, a sparse-index server for cargo, a Swift registry
 implementation, a Pub server, a repository manager for Maven.

- performance: five long-running services to operate.
- ambiguity: five stores to keep consistent with one artifact set.
- redundancy: five deployments for one release store.
- readability: five administrative configurations to learn.

### Candidate 3: Consume the artifacts with no registry

Every consumer installs from file paths: `npm install <tgz>` and the
per-ecosystem equivalents, wired by hand per consumer.

- performance: no generation step.
- ambiguity: version choice and latest-resolution live in every
  consumer's notes.
- redundancy: the wiring repeats per consumer.
- readability: no registry exists to read.

## Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| C1 generation tool | one process per release | documents derive from bytes | one implementation | inspectable tree |
| C2 registry servers | five services | five stores to synchronize | five deployments | five administrations |
| C3 no registry | none | resolution knowledge per consumer | wiring per consumer | nothing to read |

## Ruling

1. **A tool, separate from the compiler, as a pure function.** The site
   is a function of the store bytes, the base URL, and the Swift scope,
   of nothing else. Two runs over the same inputs produce
   byte-identical trees. The output directory is written fresh; the
   tool never merges into an existing site. Version aggregation is the
   store's job: adding a release adds its artifacts, and the next
   generation lists every version the store holds.
2. **The artifact is the only authority for its identity.** npm reads
   `package/package.json` inside the tarball; cargo reads `Cargo.toml`
   inside the crate; Pub reads `pubspec.yaml` inside the archive;
   Maven reads the pom beside the jar. Swift name and version come
   from the artifact file name (`<name>-<version>.zip`, split at the
   final hyphen preceding a semver), the one place spec 25 records
   them. Two artifacts claiming the same ecosystem, name, and version
   with identical bytes become one entry; with different bytes the
   generation stops and names both paths.
3. **npm.** One packument per package: `name`, `dist-tags.latest`, and
   `versions`, each version entry carrying the fields of the artifact
   manifest read from inside the tarball plus
   `dist: { tarball, integrity }`; the integrity is `sha512-` plus the
   base64 digest of the exact tarball bytes, and latest is the highest
   semver. The packument file name equals the request path npm sends:
   the unscoped name, or the scoped name with the slash percent-encoded
   (`@scope%2fname`; npm 22 emits lowercase hex, and the consumer test
   asserts the served path equals the requested bytes). The file has no
   extension, hosts label it `application/octet-stream`, and the npm
   client parses the body without checking the media type. Tarballs are
   copied to `npm/files/` under their spec 25 file names.
4. **cargo.** `cargo/index/config.json` holds
   `{"dl": "<base>/cargo/dl/{crate}-{version}.crate"}` and no `api`
   key: the registry is read-only, so search and publish are absent.
   Index entry files follow the sparse prefix tier computed on the
   lowercased name: one-character names under `1/`, two-character
   under `2/`, three-character under `3/{first}/`, all others under
   `{1-2}/{3-4}/`. Each entry file holds one JSON object per version
   per line, ascending semver, each
   `{"name","vers","deps":[],"cksum","features":{},"yanked":false,"v":2}`
   with `cksum` the sha256 hex of the exact crate bytes. Crate names
   must be lowercase; an uppercase name stops the generation.
5. **Swift.** Per package: a releases JSON at `<scope>/<name>`. Per
   version: a metadata JSON at `<scope>/<name>/<version>`, the
   `Package.swift` extracted from the zip at
   `<scope>/<name>/<version>/Package.swift`, and the zip itself at
   `<scope>/<name>/<version>.zip`. The releases document lists every
   version with an empty object value: the `url` field is optional and
   the client expands the URI template on the originating host, so the
   document needs no base URL. The metadata document is
   `{"id": "<scope>.<name>", "version", "resources", "metadata": {}}`
   with one resource
   `{"name": "source-archive", "type": "application/zip", "checksum"}`
   where the checksum is the sha256 hex of the exact zip bytes;
   `publishedAt` is optional and stays out, keeping the document a
   function of the bytes. `/swift/identifiers` holds `[]`: this
   registry assigns identifiers itself and maps no repository URLs.
6. **Pub.** `pub/api/packages/<name>` holds the hosted repository
   document: `name`, `latest`, and `versions` newest first, each entry
   with `version`, `archive_url` pointing at
   `<base>/pub/files/<name>-<version>.tar.gz`, `archive_sha256` as the
   hex digest of the exact archive bytes, and `pubspec` converted from
   the archive's `pubspec.yaml`. The document omits `isDiscontinued`,
   `retracted`, `replacedBy`, and `advisoriesUpdated`, so clients never
   request the advisories endpoint. The conversion accepts exactly the
   field set spec 24 emits (name, version, license, `environment.sdk`)
   and rejects any other key: the emitter and the reader share one
   grammar, so drift between them stops the generation.
7. **Maven.** Each `maven` tree in the store is copied unchanged. The
   tool adds one `maven-metadata.xml` per artifact beside the version
   directory's parent: `groupId`, `artifactId`, and `versioning` with
   `latest`, `release`, and `versions` in ascending semver, plus the
   file's `.sha1`. No `lastUpdated` element is written: a release
   timestamp is no property of the artifact bytes, and the metadata
   stays deterministic without it.
8. **`_headers` is a generated artifact.** The file opens with four
   fixed rules and continues with one exact rule per Swift JSON path:

   ```
   /*
     Content-Version: 1
   /swift/:scope/:name/:version/Package.swift
     Content-Type: text/x-swift
   /pub/api/packages/*
     Content-Type: application/vnd.pub.v2+json
   /swift/identifiers
     Content-Type: application/json
   ```

   `Content-Version: 1` applies site-wide: the Swift client enforces it
   on the JSON endpoints, the manifest and archive endpoints may carry
   it, and the other ecosystems ignore the unknown header. The Swift
   JSON endpoints use exact rules (`/swift/<scope>/<name>` and
   `/swift/<scope>/<name>/<version>`) because a placeholder rule for
   the three-segment path would also match
   `/{scope}/{name}/{version}.zip` (a placeholder matches one whole
   path segment, and dots do not split a segment), labeling the archive
   `application/json`, which the Swift client rejects. The
   `Package.swift` rule uses placeholders safely: it is the only
   five-segment pattern. The tool counts rules and stops with an error
   naming the count when the registry would exceed the host cap
   (Cloudflare Pages applies 100 rules per `_headers` file). Hosts
   without `_headers` support can serve the npm, cargo, and Maven
   namespaces only.
9. **Serialization, ordering, byte identity.** Every generated JSON
   document uses two-space indentation, LF endings, one trailing
   newline, and the key order of this specification's rules. Version
   ordering is semver precedence (major, minor, patch, then the
   prerelease comparison); a version outside semver stops the
   generation naming it. Byte identity holds for the same store, base
   URL, and Swift scope across runs and machines.
10. **Archive readers.** The tar reader is in this repository: the
    format is a fixed 512-byte header per member, and gzip runs through
    `node:zlib`. The zip member reader handles the stored and deflated
    entry forms through `DecompressionStream`. The tool adds no npm
    dependency; the pubspec grammar reader substitutes for a YAML
    library by accepting the compiler-emitted field set only.

## Test hooks

- `tests/ts/package-registry.test.ts` generates the five lanes'
  artifacts into a temporary store (the rewritten-hxml technique of
  `tests/ts/package-artifacts.test.ts`, the same defines including
  `package-tsc` and `package-kotlinc`, plus a scoped `-D package-name`
  for the npm path test), runs the tool, and checks: the packument
  fields and an integrity that matches a sha512 recomputed from the
  tarball bytes; the scoped packument file name equals the request
  path npm sends (the test serves the site with `Bun.serve`, records
  the path of `npm view @scope/name`, and compares the two byte for
  byte); the cargo `config.json` template, the prefix-tier placement,
  and an entry `cksum` that matches the crate bytes; the Swift metadata
  `checksum` that matches the zip bytes and the extracted
  `Package.swift` that matches the archive member; the Pub document's
  converted `pubspec` and `archive_sha256`; the Maven metadata version
  list; the `_headers` content equal to the expected bytes for the
  input set; and two runs producing byte-identical trees.
- Consumer checks in the same file run against a localhost server that
  serves the site with the `_headers` rules applied: `npm install`
  through `--registry` installs the package and a plain `node` process
  imports it; cargo resolves through a temporary `CARGO_HOME` whose
  `.cargo/config.toml` names `sparse+http://127.0.0.1:<port>/cargo/index/`
  (`cargo fetch` in a consumer crate). The Swift, Pub, and Gradle
  consumers need toolchains absent from this repository's CI, so their
  invocations are documented commands verified per release: a consumer
  `Package.swift` with `.package(id:)`, `PUB_HOSTED_URL` with
  `dart pub get`, and a Gradle build with the `maven` repository.
- The rejection paths have one test each: conflicting bytes for one
  identity, an unknown pubspec key, a non-semver version, an uppercase
  cargo name, a non-empty output directory, and the rule-count cap
  (exercised through the counting function directly, with a store size
  the host cap can reach).
