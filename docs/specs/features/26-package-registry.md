# Feature spec 26: Package registry generation

## Scope

Feature spec 25 made one compilation emit the install unit of its
target's ecosystem. This specification rules the next step: the
publish manager, a tool that scans the package metadata committed to
the registry repository, and generates one static,
read-only registry site serving all five ecosystems from one
deployment. The site holds registry documents only: npm packuments,
the cargo sparse index, the Swift package registry endpoints, the Pub
hosted repository documents, and Maven metadata. Artifact bytes are
served where they already live: every artifact a GitHub release can
serve is fetched from its release asset, and the one artifact GitHub
cannot serve (the Swift zip, whose asset responses carry
`application/octet-stream` regardless of upload settings) is uploaded
to object storage by the release pipeline and reached through a
redirect rule. No artifact byte is ever copied into the site.

The registry tool's numeric reader, where it reads numeric fields or applies
numeric validation, is governed first by
[`stdlib/14-number-parsing.md`](../stdlib/14-number-parsing.md). That
specification is the authority for all five target renderings and failure
values. This tool-specific reader retains the complete-token restriction:
whitespace is trimmed only as that specification permits, and a partial or
otherwise invalid token is rejected; a permissive native parser must not
accept it. The registry's semver parser remains separately governed by
the version rules below.

The tool is separate from the compiler because a registry aggregates
releases across compilations and across repositories: one compilation
holds one package at one version and cannot know which other releases
exist. The release pipeline owns publication. It uploads the release,
uploads the Swift zip to object storage with `Content-Type:
application/zip`, and commits the package's metadata file and README
into the registry repository under the ruling-2 layout; the
pipeline writes the commit only after publication succeeded, so a
draft or a failed release never enters the tree, and the site
rebuild is triggered by the metadata commit itself, so the site is
never staler than the tree. The publish manager only reads: it walks the committed tree,
reads the metadata files, and writes the site. The tool performs no
network access.

The tool itself is written in Haxe within boring's translatable subset
and compiled by boring: `tools/registry/src/` holds the source,
`tools/registry/compile.hxml` compiles it through boring's TypeScript
target, and the tool runs under bun through a two-line launcher that
imports the generated entry module and calls its `main`. Ruling 11
binds the shape. The repository ships no TypeScript implementation of
the generator; the TypeScript that remains is the launcher and the
tests under `tools/registry/tests/`, which spawn the compiled tool.

The registry is public and read-only. No ecosystem's publish or upload
endpoint exists on the site. The reference host is Cloudflare Pages:
the `_redirects` rules this specification relies on use the
within-segment suffix matching (`*.zip`, `:version.crate`) the
Cloudflare router implements, verified against `wrangler pages dev`.
Netlify documents state that an asterisk cannot appear in the middle
of a path segment and its `_redirects` supports no 303, so the cargo
and Swift rules of ruling 9 are not portable to it; a Netlify
deployment would need one exact rule per version for those two targets.
Porting to other hosts is out of scope. The tool makes no assumption
about the number of repositories, packages, versions, or consumers:
growth limits appear as the redirect rule-count guard, never as a
design ceiling.

## Command line

```
haxe tools/registry/compile.hxml
bun tools/registry/run.ts --tree <dir> --output <site> --base-url <url> [--swift-scope <scope>] [--archive-base <url>]
```

- `--tree`: the root of the committed metadata tree. Its layout is
  `<owner>/<repo>/<version>/<platform>/metadata.json` with one
  `README.md` per repository directory (ruling 2); the tool walks it
  directory by directory and accepts no other file.
- `--output`: the site directory. It must be absent or empty; the tool
  stops with an error otherwise, so a stale site can never mix with a
  fresh generation.
- `--base-url`: the public origin (scheme, host, optional path prefix)
  the clients use. A trailing slash is removed. The cargo `dl` template
  embeds it.
- `--swift-scope`: required when any scanned release ships a Swift
  target. Validated against the registry specification's scope pattern
  `\A[a-zA-Z0-9](?:[a-zA-Z0-9]|-(?=[a-zA-Z0-9])){0,38}\z`. The scope
  belongs to the registry; a release has no scope of its own.
- `--archive-base`: required when any scanned release ships a Swift
  target. The public origin of the object storage holding the Swift
  zips.

Every rejection names the offending repository, release tag, or path
and the reason, and the tool exits nonzero: a metadata file that does not parse as
JSON or does not conform to the field table of ruling 2, a stray file
anywhere in the tree, a version directory whose platform files
disagree on name, version, license, or repository, an identity
conflict between two repositories claiming the same ecosystem, name,
and version with different digests, a `pubspec` key outside the spec 24
grammar, a version outside semver, an uppercase cargo name, a base or
archive URL without an `http` or `https` scheme, an output directory
that holds files, a missing required scope or
archive-base argument, and a redirect rule count over the host cap.

## Output layout

| Namespace | Contents | Client configuration |
| --- | --- | --- |
| `/npm/` | one packument per package at its request path | `npm --registry=<base>/npm/` |
| `/cargo/index/` | `config.json` and the prefix-tier entry files | a named registry in `.cargo/config.toml`: `index = "sparse+<base>/cargo/index/"` |
| `/cargo/dl/` | no files; one redirect rule per crate maps the request to the release asset | part of the `dl` template |
| `/swift/` | releases and metadata JSON stored with a `.json` extension and served at their extensionless protocol paths through exact rewrites, `Package.swift`, `identifiers`; the zip paths exist only as the universal redirect rule to the archive base | `swift package-registry set <base>/swift/` |
| `/pub/api/` | one hosted-repository document per package | `PUB_HOSTED_URL=<base>/pub/` |
| `/maven/` | `maven-metadata.xml` per artifact plus its `.sha1`; the version files exist only as redirect rules to the release assets | Gradle `maven { url("<base>/maven/") }` |

The site root also carries the generated `_headers` and `_redirects`
files.

## Candidate translations

### Candidate 1: The publish manager in this repository

One command scans the committed metadata tree and writes the complete
site: all five namespaces plus `_headers` and `_redirects`, ready to
deploy.

- performance: one process per generation; the site serves static
  files with no server code; artifact bytes are served by the release
  host and the object-storage host.
- ambiguity: every registry document derives from the committed
  metadata by fixed rules; two generations over the same tree
  produce identical sites.
- redundancy: one implementation serves every ecosystem's read
  protocol.
- readability: the site is an ordinary directory tree; each document
  is inspectable and diffable.

### Candidate 2: Run each ecosystem's registry server

 Verdaccio for npm, a sparse-index server for cargo, a Swift registry
 implementation, a Pub server, a repository manager for Maven.

- performance: five long-running services to operate.
- ambiguity: five stores to keep consistent with one release set.
- redundancy: five deployments for one release list.
- readability: five administrative configurations to learn.

### Candidate 3: Consume the artifacts with no registry

Every consumer installs from release URLs by hand: `npm install
<github-release-tarball>` and the per-ecosystem equivalents, wired per
consumer.

- performance: no generation step.
- ambiguity: version choice and latest-resolution live in every
  consumer's notes.
- redundancy: the wiring repeats per consumer.
- readability: no registry exists to read.

## Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| C1 publish manager | one scan per generation | documents derive from committed metadata | one implementation | inspectable tree |
| C2 registry servers | five services | five stores to synchronize | five deployments | five administrations |
| C3 no registry | none | resolution knowledge per consumer | wiring per consumer | nothing to read |

## Ruling

1. **A scan of the committed tree.** The site is a function of the
   metadata tree, the base URL, the Swift scope, and the archive
   base; of nothing else. Two runs over the same tree produce
   byte-identical documents. The scan walks the tree directory by
   directory, reads one `metadata.json` per platform directory and
   one `README.md` per repository directory, and touches no other
   input. Prerelease versions participate and semver orders them.
   The tool performs no network access and no artifact download:
   everything the documents need comes from the committed metadata
   and the README. The output directory is written fresh; the tool
   never merges into an existing site.
2. **The committed metadata is the authority.** The release
   pipeline commits one metadata file per published platform at
   `<owner>/<repo>/<version>/<platform>/metadata.json` and one
   `README.md` at `<owner>/<repo>/README.md`; `<platform>` is one of
   `npm`, `cargo`, `pub`, `swift`, `maven`. The pipeline writes
   the commit only after publication succeeded, so a draft or a
   failed release never enters the tree. A version participates in the registry if and
   only if its directory exists holding at least one platform
   subdirectory. The metadata is the authority for identity, digests,
   artifact URLs, and document fields; the generator never opens an
   artifact and composes no URL: every artifact URL in every
   generated document is copied verbatim from the committed metadata.
   The `npm` file:

   ```json
   {
     "name": "pkg", "version": "1.2.3", "license": "MIT",
     "url": "https://github.com/owner/repo/releases/download/v1.2.3/pkg-1.2.3.tgz",
     "sha512": "…"
   }
   ```

   `name` and `version` are the spec 24 identity. A platform
   directory is present if and only if that release ships the
   platform; `license` is optional. The `cargo`, `pub`, and `swift`
   files hold the same scalar fields with `sha256` in place of
   `sha512`; the `pub` file adds the `pubspec` object of the spec 24
   grammar; the `swift` file adds `packageSwift` (the `Package.swift` text)
   and replaces `url` with `archive`, the object key under the
   archive base, which must equal `swift/<scope>/<name>/<version>.zip`,
   the one shape the universal rule of ruling 9 addresses, and the
   generator validates it; the `maven` file holds `groupId` and
   `artifacts`, one `{ "file", "url" }` object per file, with no
   top-level `url`. The platform files of one version directory must
   agree on `name`, `version`, and `license`; a disagreement stops
   the generation naming the files. Two repository directories
   claiming the same ecosystem, name, and version with equal digests
   become one entry; with different digests the generation stops and
   names both paths.
3. **npm.** One packument per package: `name`, `dist-tags.latest`, and
   `versions`, each version entry carrying `name`, `version`,
   `license` when the metadata states one, and
   `dist: { tarball, integrity }`. `tarball` is the artifact URL copied
   verbatim from the committed metadata; `integrity` is `sha512-` plus the manifest's
   base64 digest. The npm client follows the asset's own redirect
   chain and verifies the integrity (verified: npm 10 follows two
   cross-origin 302 hops to the bytes). `latest` is the highest semver
   without a prerelease, or the highest semver when every version
   carries one. The packument file name equals the request path npm
   sends: the unscoped name, or the scoped name with the slash
   percent-encoded (`@scope%2fname`; npm 22 emits lowercase hex, and
   the consumer test asserts the served path equals the requested
   bytes). The file has no extension; the npm client parses the body
   without checking the media type. The packument carries `readme` at
   top level: the repository's committed `README.md` text, copied
   verbatim.
4. **cargo.** `cargo/index/config.json` holds
   `{"dl": "<base>/cargo/dl/{crate}-{version}.crate"}` and no `api`
   key: the registry is read-only, so search and publish are absent.
   Index entry files follow the sparse prefix tier computed on the
   lowercased name: one-character names under `1/`, two-character
   under `2/`, three-character under `3/{first}/`, all others under
   `{1-2}/{3-4}/`. Each entry file holds one JSON object per version
   per line, ascending semver, each
   `{"name","vers","deps":[],"cksum","features":{},"yanked":false,"v":2}`
   with `cksum` the metadata's sha256 hex. Crate names must be
   lowercase; an uppercase name stops the generation. The `dl` path
   carries no file, so every crate gets one redirect rule (ruling 9);
   the cargo client follows it and verifies `cksum` (verified: cargo
   1.98 follows two cross-origin 302 hops and accepts the bytes).
5. **Swift.** Per package: a releases JSON served at `<scope>/<name>`
   and stored at `<scope>/<name>.json`; per version: a metadata JSON
   served at `<scope>/<name>/<version>` and stored at
   `<scope>/<name>/<version>.json` (ruling 9 explains the exact
   rewrites that bridge the two path pairs). The
   `Package.swift` text from the committed metadata is a stored file at
   `<scope>/<name>/<version>/Package.swift`; its path conflicts with
   no other document. The releases document is
   `{"releases": {"<version>": {}, ...}}` with every version carrying
   an empty object value: the service specification requires the
   top-level `releases` key and makes the per-version `url` optional,
   and the client expands the URI template on the originating host,
   so the document needs no base URL. The metadata document is
   `{"id": "<scope>.<name>", "version", "resources", "metadata": {}}`
   with one resource
   `{"name": "source-archive", "type": "application/zip", "checksum"}`
   where the checksum is the metadata's sha256 hex. The zip itself is
   never on the site: the request for
   `<scope>/<name>/<version>.zip` matches the one universal redirect
   rule (ruling 9) and is served from the archive base, where the
   release pipeline uploaded the zip with `Content-Type:
   application/zip`. GitHub release assets answer
   `application/octet-stream` with the content type pinned in the
   signed asset URL, which the Swift client rejects, so the Swift target
   is the one target that cannot be served from a release asset.
   `/swift/identifiers` holds `[]`: this registry
   assigns identifiers itself and maps no repository URLs.
6. **Pub.** `pub/api/packages/<name>` holds the hosted repository
   document: `name`, `latest`, and `versions` newest first, each entry
   with `version`, `archive_url` taken verbatim from the
   committed metadata, `archive_sha256` from the metadata, and
   `pubspec` copied from the metadata. `latest` follows the npm rule. The document omits
   `isDiscontinued`, `retracted`, `replacedBy`, and
   `advisoriesUpdated`, so clients never request the advisories
   endpoint. The `pubspec` object accepts exactly the field set spec
   24 emits (name, version, license, `environment.sdk`) and rejects
   any other key: the emitter and the reader share one grammar, so
   drift between them stops the generation.
7. **Maven.** No repository tree is copied; the site holds only
   `maven-metadata.xml` and its `.sha1` per artifact, beside the
   version directories' parent: `groupId`, `artifactId`, and
   `versioning` with `latest` (highest semver), `release` (highest
   semver without a prerelease), and `versions` in ascending semver.
   No `lastUpdated` element is written: a release timestamp is no
   property of the committed metadata, and the document stays
   deterministic without it. The version files (jar, pom, both sha1) live as release
   assets and are reached through one redirect rule per artifact
   (ruling 9). Gradle follows the redirect chain, including the GitHub
   asset's own second hop, stores the bytes without checking the media
   type, and tolerates a missing sha1 (verified: Gradle 9.6 resolves
   through 200, 302, 303, 307, and the GitHub double hop).
8. **`_headers` is a generated artifact of constant size.** The file
   holds six rules and never grows with the registry:

   ```
   /*
     Content-Version: 1
   /swift/:scope/:name
     Content-Type: application/json
   /swift/:scope/:name/:version
     Content-Type: application/json
   /swift/:scope/:name/:version/Package.swift
     Content-Type: text/x-swift
   /pub/api/packages/*
     Content-Type: application/vnd.pub.v2+json
   /swift/identifiers
     Content-Type: application/json
   ```

   `Content-Version: 1` applies site-wide: the Swift client enforces
   it on the JSON endpoints, and the other ecosystems ignore the
   unknown header. The Swift JSON endpoints can use placeholder rules
   because the zip path never reaches `_headers`: redirects are
   applied first, regardless of whether an asset matches, so
   `<version>.zip` requests are redirected away before headers apply,
   and the four-segment placeholder rule cannot match the
   five-segment `Package.swift` path.
9. **`_redirects` is a generated artifact with a rule-count guard.**
   Four rule forms exist:

   - One universal Swift rule for the whole registry:

     ```
     /swift/:scope/:name/*.zip  <archive-base>/swift/:scope/:name/:splat.zip  303
     ```

   - One exact rewrite per Swift package and one per version:

     ```
     /swift/<scope>/<name>  /swift/<scope>/<name>.json  200
     /swift/<scope>/<name>/<version>  /swift/<scope>/<name>/<version>.json  200
     ```

     The service specification serves the releases document at
     `<scope>/<name>`, the version documents at
     `<scope>/<name>/<version>`, and the manifests under
     `<scope>/<name>/<version>/Package.swift`; a static site cannot
     hold a file and a directory at one path, so the two JSON
     documents are stored with the `.json` extension and the rewrites
     serve them at the protocol paths. Each rewrite is an exact rule;
     a placeholder rule would be wrong here, for a reason the host
     documents: redirect
     rules apply regardless of whether an asset matches, and a
     placeholder rule would also match the `.json` request the
     service specification lets clients send, rewriting it to a
     nonexistent `.json.json`; as an exact rule it leaves that
     request alone, and the request reaches the stored file directly.
     The rewrites are `200` (proxying): the URL stays the protocol
     path and the target is relative, which the host requires of
     rewrites.

   - One dynamic rule per crate:

     ```
     /cargo/dl/<crate>-:version.crate  https://github.com/<owner>/<repo>/releases/download/v:version/<crate>-:version.crate  302
     ```

   - One dynamic rule per Maven artifact:

     ```
     /maven/<groupPath>/<name>/:version/:file  https://github.com/<owner>/<repo>/releases/download/v:version/:file  302
     ```

   The Cloudflare router matches a placeholder followed by a literal
   suffix inside one segment (`:version.crate`, `*.zip`) and a splat
   that crosses slashes, and one rule may mix whole-segment
   placeholders with a suffixed splat (verified against
   `wrangler pages dev`, which runs the same router as production;
   the first production deployment repeats the check). The
   `v<version>` tag shape is validated against every recorded
   version's committed URLs before a dynamic rule is emitted: the
   rule applies only when every version of that crate or artifact
   publishes from one repository under a `v<version>` tag, and any
   deviation falls back to exact static rules, one per version of
   that package and, for Maven, one per file. Cargo rules are emitted in descending crate-name
   length order: matching is first-match-wins and
   `/cargo/dl/my-:version.crate` would otherwise capture requests for
   a crate named `my-crate`. The tool counts dynamic and static rules
   and stops with an error naming both counts when the registry would
   exceed the host cap (Cloudflare Pages: 100 dynamic, 2000 static,
   2100 total); the documented overflow path is Bulk Redirects or
   moving that namespace to object storage.
10. **Serialization, ordering, byte identity.** Every generated JSON
    document uses two-space indentation, LF endings, one trailing
    newline, and the key order of this specification's rules. Version
    ordering is semver precedence (major, minor, patch, then the
    prerelease comparison); a version outside semver stops the
    generation naming it. Byte identity holds for the same inputs
    across runs and machines: artifact URLs are committed verbatim in the
    metadata and contain no volatile query strings.
11. **Written in boring, compiled by boring.** The generator source is
    Haxe in the translatable subset, under `tools/registry/src/`, and
    `tools/registry/compile.hxml` compiles it through boring's
    TypeScript target the way `examples/ts.hxml` compiles the codec:
    the same reflaxe libraries, the same interception gate, an output
    define placing the generated tree under `tools/registry/gen/`
    (a gitignored generated tree, like `reference/ts/gen`), no plain
    Haxe `-js` output anywhere, and a relative `runtime-import` with
    `runtime-emit`, which leaves the tree self-contained: it runs
    under bun from the repository root with no build step and without
    resolving anything through `tsconfig.json` paths. The generated
    entry module exposes a public static `main`; the committed
    launcher `tools/registry/run.ts` is two lines, importing that
    module and calling `main`, and holds no generator logic. The tool
    reaches the platform only through typed extern modules over the
    bun runtime, following the `std.Process` and `std.Console`
    precedent in `samples/std/`: text file read; file write; directory
    creation; directory listing; command-line arguments; and process
    exit. Every extern declares real types; no
    extern parameter or return carries `Dynamic`. Compiling the tool
    through the other four targets is out of scope. JSON parsing and
    serialization, the sha1 of the Maven metadata, and the semver
    comparison are pure Haxe modules of the tool: the JSON reader
    builds an ordered value tree (objects keep their field order), the
    JSON writer takes the field order explicitly, and no module uses
    reflection. The reader's numeric scans use `Std.parseFloat`,
    `Std.parseInt` (hex-prefixed literals), and `Math.isNaN`, and the
    TypeScript target lowers them onto `Number.parseFloat`,
    `Number.parseInt`, and `Number.isNaN`. The reader only ever passes
    complete numeric tokens, bounded by delimiters it scans to itself,
    and the hex parse takes four verified hex digits, so the
    parse-failure returns of the Haxe functions (`NaN` and a null
    `Int`) never occur. The tool is the first consumer of the two
    parse functions: no other target holds a lowering for them, and
    promoting either into the business subset requires a five-target
    standard-library specification first, ruling the failure domain
    before any target emits them. The tests stay TypeScript under
    `bun test` and spawn the compiled tool, so the tests exercise
    exactly the artifact a deployment runs.

## Test hooks

- The tests run `haxe tools/registry/compile.hxml` first, so every
  test spawns `bun tools/registry/run.ts`, the artifact a deployment
  runs, and a stale compiled tool fails the run at its first command.
- `tools/registry/tests/package-registry.test.ts` builds a fixture metadata tree
  in a temp directory: one owner holding two repositories, a
  five-platform repository at two versions and a single-platform
  repository at one version, each repository with a `README.md`, the
  artifact URLs pointing at a fixture asset server with `Bun.serve`
  that also serves the Swift zips under their object keys. It runs
  the tool with `--tree`, `--archive-base`, and a temp `--output`,
  then checks: the packument fields, its `readme` equal to the
  committed README text, and an integrity that matches a sha512
  recomputed from the artifact bytes; the scoped packument file name
  equals the request path npm sends; the cargo `config.json` template,
  the prefix-tier placement, and an entry `cksum` that matches the
  crate bytes; the Swift releases document nesting under the
  `releases` key, the metadata document, and their exact rewrite
  rules in `_redirects`; the Swift metadata `checksum` that matches
  the zip bytes and the `Package.swift` file that equals the metadata
  text; the Pub document's `pubspec` and `archive_sha256`; the Maven
  metadata version list; the `_headers` and `_redirects` content
  equal to the expected bytes for the input set; and two runs
  producing byte-identical trees.
- Consumer checks run against a localhost server that serves the site
  with the `_headers` rules applied and a `_redirects` matcher
  implementing the generated forms (exact, whole-segment placeholder,
  placeholder with literal suffix, suffixed splat, exact `200`
  rewrite), first-match-wins in file order, rules applied regardless
  of matching assets: `npm install` through `--registry` installs the
  package through the asset URL and a plain `node` process imports it;
  cargo resolves through a temporary `CARGO_HOME` whose
  `.cargo/config.toml` names
  `sparse+http://127.0.0.1:<port>/cargo/index/`, and `cargo fetch`
  follows the `dl` redirect to the asset. The Swift rewrites are
  checked at the matcher level, which needs no Swift toolchain: the
  requests `<base>/swift/<scope>/<name>` and
  `<base>/swift/<scope>/<name>/<version>` return their documents'
  bytes, and the `.json` requests return the same bytes. The Swift,
  Pub, and Gradle
  consumers need toolchains absent from this repository's CI, so
  their invocations are documented commands verified per release: a
  consumer `Package.swift` with `.package(id:)`, `PUB_HOSTED_URL`
  with `dart pub get`, and a Gradle build with the `maven` repository.
- The rejection paths have one test each: a metadata file that does
  not parse as JSON, a field outside the ruling-2 grammar, a stray
  file in the tree, a repository directory holding no version
  directory, a platform disagreement inside one version directory, an
  unknown pubspec key, a non-semver version, an uppercase cargo name,
  a non-empty output directory, the missing Swift scope or archive
  base, a base or archive URL without an `http` or `https` scheme,
  the identity digest conflict, and the rule caps (exercised through
  the counting function directly).
- The tag fallback has one test: a fixture version whose committed
  artifact URLs deviate from the `v<version>` tag shape makes its
  package's rules per-version exact rules.
