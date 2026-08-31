# Feature spec 26: Package registry generation

## Scope

Feature spec 25 made one compilation emit the install unit of its
target's ecosystem. This specification rules the next step: the
publish manager, a tool that holds a list of repositories, scans the
GitHub releases of every listed repository, and generates one static,
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

The tool is separate from the compiler because a registry aggregates
releases across compilations and across repositories: one compilation
holds one package at one version and cannot know which other releases
exist. The release pipeline owns publication. It uploads the release,
writes the release manifest into the release body, and uploads the
Swift zip to object storage with `Content-Type: application/zip`. The
publish manager only reads: it calls the GitHub release listing API,
reads the manifests, and writes the site.

The registry is public and read-only. No ecosystem's publish or upload
endpoint exists on the site. The reference host is Cloudflare Pages:
the `_redirects` rules this specification relies on use the
within-segment suffix matching (`*.zip`, `:version.crate`) the
Cloudflare router implements, verified against `wrangler pages dev`.
Netlify documents state that an asterisk cannot appear in the middle
of a path segment and its `_redirects` supports no 303, so the cargo
and Swift rules of ruling 9 are not portable to it; a Netlify
deployment would need one exact rule per version for those two lanes.
Porting to other hosts is out of scope. The tool makes no assumption
about the number of repositories, packages, versions, or consumers:
growth limits appear as the redirect rule-count guard, never as a
design ceiling.

## Command line

```
bun tools/registry/generate.ts --repos <file> --output <site> --base-url <url> [--swift-scope <scope>] [--archive-base <url>] [--api-base <url>] [--token <token>] [--cache <dir>]
```

- `--repos`: the repository list, a text file with one `owner/name`
  entry per line; blank lines and lines starting with `#` are ignored.
- `--output`: the site directory. It must be absent or empty; the tool
  stops with an error otherwise, so a stale site can never mix with a
  fresh generation.
- `--base-url`: the public origin (scheme, host, optional path prefix)
  the clients use. A trailing slash is removed. The cargo `dl` template
  embeds it.
- `--swift-scope`: required when any scanned release ships a Swift
  lane. Validated against the registry specification's scope pattern
  `\A[a-zA-Z0-9](?:[a-zA-Z0-9]|-(?=[a-zA-Z0-9])){0,38}\z`. The scope is
  a property of the registry, not of a release.
- `--archive-base`: required when any scanned release ships a Swift
  lane. The public origin of the object storage holding the Swift
  zips.
- `--api-base`: the GitHub REST origin, `https://api.github.com` by
  default. Tests point it at a fixture server.
- `--token`: the GitHub token, read from `--token` or `GITHUB_TOKEN`.
  The scan requires a token; without one the tool stops. Listing every
  repository's releases page by page exceeds the unauthenticated
  hourly limit once the list holds more than a handful of
  repositories.
- `--cache`: an optional directory holding conditional-request state
  (request URL to ETag and cached body). A cache hit changes no
  output; it only avoids refetching an unchanged page.

Every rejection names the offending repository, release tag, or path
and the reason, and the tool exits nonzero: a repository whose listing
returns an error status, a release body whose manifest block is
present but does not parse as JSON or does not conform to the field
table of ruling 2, an identity
conflict between two releases claiming the same ecosystem, name, and
version with different digests, a `pubspec` key outside the spec 24
grammar, a version outside semver, an uppercase cargo name, a base or
archive URL without an `http` or `https` scheme, an output directory
that holds files, a missing required token or scope argument, and a
redirect rule count over the host cap.

## Output layout

| Namespace | Contents | Client configuration |
| --- | --- | --- |
| `/npm/` | one packument per package at its request path | `npm --registry=<base>/npm/` |
| `/cargo/index/` | `config.json` and the prefix-tier entry files | a named registry in `.cargo/config.toml`: `index = "sparse+<base>/cargo/index/"` |
| `/cargo/dl/` | no files; one redirect rule per crate maps the request to the release asset | part of the `dl` template |
| `/swift/` | releases and metadata JSON, `Package.swift`, `identifiers`; the zip paths exist only as one universal redirect rule to the archive base | `swift package-registry set <base>/swift/` |
| `/pub/api/` | one hosted-repository document per package | `PUB_HOSTED_URL=<base>/pub/` |
| `/maven/` | `maven-metadata.xml` per artifact plus its `.sha1`; the version files exist only as redirect rules to the release assets | Gradle `maven { url("<base>/maven/") }` |

The site root also carries the generated `_headers` and `_redirects`
files.

## Candidate translations

### Candidate 1: The publish manager in this repository

One command scans the listed repositories and writes the complete
site: all five namespaces plus `_headers` and `_redirects`, ready to
deploy.

- performance: one process per generation; the site serves static
  files with no server code; artifact bytes are served by the release
  host and the object-storage host.
- ambiguity: every registry document derives from release listings and
  manifests by fixed rules; two generations over the same inputs
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
| C1 publish manager | one scan per generation | documents derive from listings and manifests | one implementation | inspectable tree |
| C2 registry servers | five services | five stores to synchronize | five deployments | five administrations |
| C3 no registry | none | resolution knowledge per consumer | wiring per consumer | nothing to read |

## Ruling

1. **A scan-based pure function.** The site is a function of the
   repository list, the release listing state of every listed
   repository, the base URL, the Swift scope, and the archive base; of
   nothing else. Two runs over the same inputs produce byte-identical
   trees, with and without a warm cache. The scan reads
   `GET /repos/{owner}/{name}/releases` with `per_page=100`, follows
   pagination to exhaustion, and sends conditional requests carrying
   the stored ETag; a `304` response reuses the cached body. Draft
   releases are skipped; prereleases participate and semver orders
   them. The tool performs no artifact download: everything the
   documents need comes from the listing (release body, asset names,
   asset URLs) and the manifest. The output directory is written
   fresh; the tool never merges into an existing site.
2. **The release manifest is the authority.** The release pipeline
   writes the manifest into the release body as the first fenced code
   block tagged `boring`, holding one JSON object. A release
   participates in the registry if and only if its body carries that
   block. The manifest is the authority for identity, digests, and
   document fields; the generator never opens an artifact. Fields:

   ```json
   {
     "name": "pkg", "version": "1.2.3", "license": "MIT",
     "npm":   { "artifact": "pkg-1.2.3.tgz", "sha512": "…" },
     "cargo": { "artifact": "pkg-1.2.3.crate", "sha256": "…" },
     "pub":   { "artifact": "pkg-1.2.3.tar.gz", "sha256": "…",
                "pubspec": { "name": "pkg", "version": "1.2.3", "license": "MIT",
                             "environment": { "sdk": "…" } } },
     "swift": { "archive": "swift/example/pkg/1.2.3.zip", "sha256": "…",
                "packageSwift": "…" },
     "maven": { "groupId": "dev.example", "artifacts": ["pkg-1.2.3.jar", "pkg-1.2.3.pom", "pkg-1.2.3.jar.sha1", "pkg-1.2.3.pom.sha1"] }
   }
   ```

   `name` and `version` are the spec 24 identity. Each lane key is
   present if and only if that release ships the lane; `license` is
   optional. `swift.archive` is the object key under the archive base
   and must equal `swift/<scope>/<name>/<version>.zip`, the one shape
   the universal rule of ruling 9 addresses; the generator validates
   it. Asset URLs are taken verbatim from the listing by asset name;
   the generator composes none. Two releases claiming the same ecosystem,
   name, and version with equal digests become one entry; with
   different digests the generation stops and names both repositories
   and tags.
3. **npm.** One packument per package: `name`, `dist-tags.latest`, and
   `versions`, each version entry carrying `name`, `version`,
   `license` when the manifest states one, and
   `dist: { tarball, integrity }`. `tarball` is the release asset URL
   from the listing; `integrity` is `sha512-` plus the manifest's
   base64 digest. The npm client follows the asset's own redirect
   chain and verifies the integrity (verified: npm 10 follows two
   cross-origin 302 hops to the bytes). `latest` is the highest semver
   without a prerelease, or the highest semver when every version
   carries one. The packument file name equals the request path npm
   sends: the unscoped name, or the scoped name with the slash
   percent-encoded (`@scope%2fname`; npm 22 emits lowercase hex, and
   the consumer test asserts the served path equals the requested
   bytes). The file has no extension; the npm client parses the body
   without checking the media type.
4. **cargo.** `cargo/index/config.json` holds
   `{"dl": "<base>/cargo/dl/{crate}-{version}.crate"}` and no `api`
   key: the registry is read-only, so search and publish are absent.
   Index entry files follow the sparse prefix tier computed on the
   lowercased name: one-character names under `1/`, two-character
   under `2/`, three-character under `3/{first}/`, all others under
   `{1-2}/{3-4}/`. Each entry file holds one JSON object per version
   per line, ascending semver, each
   `{"name","vers","deps":[],"cksum","features":{},"yanked":false,"v":2}`
   with `cksum` the manifest's sha256 hex. Crate names must be
   lowercase; an uppercase name stops the generation. The `dl` path
   carries no file, so every crate gets one redirect rule (ruling 9);
   the cargo client follows it and verifies `cksum` (verified: cargo
   1.98 follows two cross-origin 302 hops and accepts the bytes).
5. **Swift.** Per package: a releases JSON at `<scope>/<name>`. Per
   version: a metadata JSON at `<scope>/<name>/<version>` and the
   `Package.swift` text from the manifest at
   `<scope>/<name>/<version>/Package.swift`. The releases document
   lists every version with an empty object value: the client expands
   the URI template on the originating host, so the document needs no
   base URL. The metadata document is
   `{"id": "<scope>.<name>", "version", "resources", "metadata": {}}`
   with one resource
   `{"name": "source-archive", "type": "application/zip", "checksum"}`
   where the checksum is the manifest's sha256 hex. The zip itself is
   never on the site: the request for
   `<scope>/<name>/<version>.zip` matches the one universal redirect
   rule (ruling 9) and is served from the archive base, where the
   release pipeline uploaded the zip with `Content-Type:
   application/zip`. GitHub release assets answer
   `application/octet-stream` with the content type pinned in the
   signed asset URL, which the Swift client rejects, so the Swift lane
   is the one lane that cannot be served from a release asset.
   `/swift/identifiers` holds `[]`: this registry
   assigns identifiers itself and maps no repository URLs.
6. **Pub.** `pub/api/packages/<name>` holds the hosted repository
   document: `name`, `latest`, and `versions` newest first, each entry
   with `version`, `archive_url` taken verbatim from the listing,
   `archive_sha256` from the manifest, and `pubspec` copied from the
   manifest. `latest` follows the npm rule. The document omits
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
   property of the manifest, and the metadata stays deterministic
   without it. The version files (jar, pom, both sha1) live as release
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
   Three rule forms exist:

   - One universal Swift rule for the whole registry:

     ```
     /swift/:scope/:name/*.zip  <archive-base>/swift/:scope/:name/:splat.zip  303
     ```

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
   `v<version>` tag shape is validated against every release of the
   package before a dynamic rule is emitted: it applies only when
   every version of that crate or artifact lives in one repository
   and is tagged `v<version>`, and any deviation falls back to exact
   static rules, one per version of that package and, for Maven, one
   per file. Cargo rules are emitted in descending crate-name
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
    across runs and machines: release asset URLs are recorded verbatim
    from the listings and contain no volatile query strings.

## Test hooks

- `tests/ts/package-registry.test.ts` starts a fixture GitHub API and
  a fixture archive server with `Bun.serve`: the API serves
  `/repos/<owner>/<name>/releases` pages whose release bodies carry
  fenced `boring` manifests and whose assets list names plus
  `browser_download_url` values pointing back at the fixture; the
  archive server serves the Swift zips under their object keys. It
  runs the tool with `--api-base`, `--archive-base`, and a temp
  `--repos` file, then checks: the packument fields and an integrity
  that matches a sha512 recomputed from the artifact bytes; the scoped
  packument file name equals the request path npm sends; the cargo
  `config.json` template, the prefix-tier placement, and an entry
  `cksum` that matches the crate bytes; the Swift metadata `checksum`
  that matches the zip bytes and the `Package.swift` file that equals
  the manifest text; the Pub document's `pubspec` and
  `archive_sha256`; the Maven metadata version list; the `_headers`
  and `_redirects` content equal to the expected bytes for the input
  set; and two runs producing byte-identical trees, the second with a
  warm cache over `304` responses.
- Consumer checks run against a localhost server that serves the site
  with the `_headers` rules applied and a `_redirects` matcher
  implementing the generated forms (exact, whole-segment placeholder,
  placeholder with literal suffix, suffixed splat), first-match-wins
  in file order: `npm install` through `--registry` installs the
  package through the asset URL and a plain `node` process imports it;
  cargo resolves through a temporary `CARGO_HOME` whose
  `.cargo/config.toml` names
  `sparse+http://127.0.0.1:<port>/cargo/index/`, and `cargo fetch`
  follows the `dl` redirect to the asset. The Swift, Pub, and Gradle
  consumers need toolchains absent from this repository's CI, so
  their invocations are documented commands verified per release: a
  consumer `Package.swift` with `.package(id:)`, `PUB_HOSTED_URL`
  with `dart pub get`, and a Gradle build with the `maven` repository.
- The rejection paths have one test each: a repository listing that
  answers an error status, a malformed manifest block, an unknown
  pubspec key, a non-semver version, an uppercase cargo name, a
  non-empty output directory, the missing token, the missing Swift
  scope or archive base, a base or archive URL without an `http` or
  `https` scheme, the identity digest conflict, and the rule
  caps (exercised through the counting function directly).
- The tag fallback has one test: a fixture release tagged other than
  `v<version>` makes its package's rules per-version exact rules.
