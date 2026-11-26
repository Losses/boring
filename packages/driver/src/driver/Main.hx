package driver;

#if js
import driver.ChildEvidence.ChildEnvironment;
import driver.ChildEvidence.ChildEvidenceError;
import js.Syntax;
#end
import driver.Host.HostResult;

/** Host entry for the driver package. Configuration and command arguments are
    computed by Config and Plan; this class executes target toolchains. */
class Main {
    /** Registry metadata parameters of one pack run; null when the pack writes no tree. */
    static var packRegistry:Null<RegistryMetadata.PackRegistryConfig> = null;

    // ------------------------------------------------------------------
    // Host operations
    // ------------------------------------------------------------------

    static function exists(path:String):Bool {
        return Host.exists(path);
    }

    static function readText(path:String):String {
        return Host.readText(path);
    }

    static function makeDirs(path:String):Void {
        Host.makeDirs(path);
    }

    static function deleteFile(path:String):Void {
        Host.deleteFile(path);
    }

    static function joinPath(a:String, b:String):String {
        return Host.join(a, b);
    }

    static function resolveAgainst(base:String, rel:String):String {
        return Host.resolve(base, rel);
    }

    static function print(s:String):Void {
        Host.outputLine(s);
    }

    static function printErr(s:String):Void {
        Host.printError(s);
    }

    static function exit(code:Int):Void {
        Host.exit(code);
    }

    static function fail(message:String):Void {
        printErr("Error: " + message);
        exit(1);
    }

    /** The regular files under one directory, relative to it, sorted. */
    static function walkFiles(dir:String, suffix:String):Array<String> {
        final out:Array<String> = [];
        walkFilesInner(dir, "", suffix, out);
        var i = 1;
        while (i < out.length) {
            final value = out[i];
            var j = i;
            while (j > 0 && out[j - 1] > value) {
                out[j] = out[j - 1];
                j--;
            }
            out[j] = value;
            i++;
        }
        return out;
    }

    static function walkFilesInner(dir:String, prefix:String, suffix:String, out:Array<String>):Void {
        final listDir = prefix.length == 0 ? dir : joinPath(dir, prefix);
        if (!exists(listDir)) {
            return;
        }
        final entries = Host.readDir(listDir);
        for (entry in entries) {
            final full = prefix.length == 0 ? entry : prefix + "/" + entry;
            final absolute = joinPath(dir, full);
            final isDir = Host.isDirectory(absolute);
            if (isDir) {
                walkFilesInner(dir, full, suffix, out);
            } else if (StringTools.endsWith(full, suffix)) {
                out.push(full);
            }
        }
    }

    /**
        One command through the host shell API. Output is captured and
        returned with the exit code; the caller decides what to show.
    **/
    static function runCommand(cmd:String, args:Array<String>, cwd:String, envExtra:Array<EnvVar>):HostResult {
        return Host.run(cmd, args, cwd, envExtra);
    }

    // ------------------------------------------------------------------
    // The project file
    // ------------------------------------------------------------------

    static function loadProject(projectPath:String):Project {
        if (!exists(projectPath)) {
            fail('project file not found: $projectPath (pass --project <file>)');
        }
        final root = Host.dirname(Host.resolve(Host.cwd(), projectPath));
        var projectText:String = "";
        try {
            projectText = Main.readText(projectPath);
        } catch (e:std.FsException) {
            throw new DriverException(InvalidConfig(
                'project file read error: ${e.message}'));
        }
        var parsed:Null<Project> = null;
        try {
            parsed = Config.parse(projectText, projectPath, root);
        } catch (error:DriverException) {
            fail(Diagnostic.describe(error.fault));
        }
        if (parsed == null) throw new DriverException(InvalidConfig('project file could not be read: $projectPath'));
        return parsed;
    }

    // ------------------------------------------------------------------
    // Derivation
    // ------------------------------------------------------------------

    /**
        The derived paths resolve against the project root (the
        driver's working directory is unused): a driver compiled in one checkout
        runs a project file that names another (the generation step
        already runs there, through the step command's working
        directory), so every consumer of these paths agrees on where
        the trees live.
    **/
    static function genDir(project:Project, bundle:BundleSpec):String {
        return resolveAgainst(project.root, joinPath(joinPath(project.outRoot, bundle.id), "gen"));
    }

    static function genTestsDir(project:Project, bundle:BundleSpec):String {
        return resolveAgainst(project.root, joinPath(joinPath(project.outRoot, bundle.id), "gen-tests"));
    }

    static function buildDir(project:Project, bundle:BundleSpec):String {
        return resolveAgainst(project.root, joinPath(joinPath(project.outRoot, bundle.id), "build"));
    }

    static function resultsPath(project:Project, bundle:BundleSpec):String {
        return resolveAgainst(project.root, joinPath(project.resultsDir, bundle.id + ".jsonl"));
    }

    /**
        The publication arguments with the {maven} and {version} placeholders
        replaced by the bundle's Maven directory and package version.
    **/
    static function publicationArguments(args:Array<String>, mavenDir:String, version:String):Array<String> {
        return [for (arg in args) publicationValue(arg, mavenDir, version)];
    }

    static function publicationValue(value:String, mavenDir:String, version:String):String {
        final withMaven = StringTools.replace(value, "{maven}", mavenDir);
        return StringTools.replace(withMaven, "{version}", version);
    }

    static function genArgs(project:Project, bundle:BundleSpec, pack:Bool):Array<String> {
        final packageTsc = pack && bundle.target == "ts" ? resolvePackTool("BORING_PACKAGE_TSC", "tsc", bundle) : null;
        final packageKotlinc = pack && bundle.target == "kotlin" && bundle.mavenPublication == null && !bundle.kmpPublication
            ? resolvePackTool("BORING_PACKAGE_KOTLINC", "kotlinc", bundle) : null;
        final args = Plan.genArgs(project, bundle, pack, genDir(project, bundle), genTestsDir(project, bundle), packageTsc, packageKotlinc,
            discoverSourceTypes(project, bundle.sourceSet));
        args.push("-D");
        args.push("package-modules-file=" + moduleManifestPath(project, bundle));
        if (bundle.dependsOn.length > 0) {
            args.push("-D");
            args.push("package-dependency-file=" + writeDependencyFile(project, bundle));
            // A packed artifact is installed from the registry, so a path
            // dependency becomes a versioned one at pack time. Local
            // generation keeps the bundle's mode.
            final dependencyMode = pack && bundle.dependencyMode == "path" ? "registry" : bundle.dependencyMode;
            if (dependencyMode != "registry") {
                args.push("-D");
                args.push("package-dependency-mode=" + dependencyMode);
            }
            // Each dependency's registry-side name and version, so the
            // compiler writes them into the manifest it generates.
            for (depId in bundle.dependsOn) {
                final dep = dependencyBundle(project, depId);
                if (dep.packageName == "" || dep.packageVersion == "") {
                    continue;
                }
                final declared = packageNameOf(dep);
                final ecosystem = declared != "" ? declared : Config.ecosystemName(bundle.target, dep.packageName,
                    dep.packageNpmName, dep.packageCargoName, dep.packagePubName, dep.packageMavenName);
                args.push("-D");
                args.push('package-dependency-' + depId + '=' + ecosystem + '@' + dep.packageVersion);
                args.push("-D");
                args.push('package-dependency-dir-' + depId + '='
                    + resolveAgainst(project.root, joinPath(project.outRoot, dep.id)));
                for (entry in bundle.dependencyPaths) {
                    if (entry.id == depId) {
                        args.push("-D");
                        args.push('package-dependency-path-' + depId + '=' + entry.path);
                    }
                }
                if (dep.packageMavenGroup != "") {
                    args.push("-D");
                    args.push('package-dependency-group-' + depId + '=' + dep.packageMavenGroup);
                }
                if (dep.packageSwiftUrl != "") {
                    args.push("-D");
                    args.push('package-dependency-swift-url-' + depId + '=' + dep.packageSwiftUrl);
                }
                if (dep.packageSwiftPath != "") {
                    args.push("-D");
                    args.push('package-dependency-swift-path-' + depId + '=' + dep.packageSwiftPath);
                }
            }
        }
        return args;
    }

    static function packageNameOf(bundle:BundleSpec):String {
        var index = 0;
        while (index < bundle.haxeArgs.length) {
            final arg = bundle.haxeArgs[index];
            if (arg == "-D" && index + 1 < bundle.haxeArgs.length) {
                final value = bundle.haxeArgs[index + 1];
                if (StringTools.startsWith(value, "package-name=")) {
                    return value.substr("package-name=".length);
                }
                index += 2;
                continue;
            }
            if (StringTools.startsWith(arg, "-Dpackage-name=")) {
                return arg.substr("-Dpackage-name=".length);
            }
            index++;
        }
        return "";
    }

    static function moduleManifestPath(project:Project, bundle:BundleSpec):String {
        return resolveAgainst(project.root, joinPath(joinPath(project.outRoot, bundle.id), "modules.txt"));
    }

    static function dependencyFilePath(project:Project, bundle:BundleSpec):String {
        return resolveAgainst(project.root, joinPath(joinPath(project.outRoot, bundle.id), "dependencies.tsv"));
    }

    static function dependencyBundle(project:Project, id:String):BundleSpec {
        for (item in project.bundles) if (item.id == id) return item;
        fail('bundle dependsOn names unknown bundle "$id"');
        return null;
    }

    /** Writes <module> TAB <package name> for every module the dependencies provide. **/
    static function writeDependencyFile(project:Project, bundle:BundleSpec):String {
        final path = dependencyFilePath(project, bundle);
        final lines:Array<String> = [];
        for (depId in bundle.dependsOn) {
            final dep = dependencyBundle(project, depId);
            final manifest = moduleManifestPath(project, dep);
            if (!exists(manifest)) {
                fail('bundle "${bundle.id}": dependsOn "${depId}" has no module manifest; run gen for "${depId}" first');
            }
            for (line in Host.readText(manifest).split("\n")) {
                final module = StringTools.trim(line);
                if (module == "") continue;
                lines.push(module + "\t" + dep.packageName);
            }
        }
        lines.sort(Reflect.compare);
        Host.writeText(path, lines.length == 0 ? "" : lines.join("\n") + "\n");
        return path;
    }

    /** Records the modules a generated tree provides for dependants. **/
    static function writeModuleManifest(project:Project, bundle:BundleSpec, root:String):Void {
        final modules:Array<String> = [];
        collectModules(root, "", modules);
        modules.sort(Reflect.compare);
        Host.writeText(moduleManifestPath(project, bundle), modules.length == 0 ? "" : modules.join("\n") + "\n");
    }

    static function collectModules(root:String, dir:String, out:Array<String>):Void {
        final base = dir == "" ? root : joinPath(root, dir);
        for (entry in Host.readDir(base)) {
            final relative = dir == "" ? entry : dir + "/" + entry;
            if (Host.isDirectory(joinPath(root, relative))) {
                collectModules(root, relative, out);
                continue;
            }
            final dot = relative.lastIndexOf(".");
            if (dot < 0) continue;
            final extension = relative.substr(dot + 1);
            if (["ts", "rs", "kt", "swift", "dart", "hx"].indexOf(extension) < 0) continue;
            final module = relative.substr(0, dot).split("/").join(".");
            // The runtime module is emitted by every bundle; a dependant
            // imports its own runtime, not the dependency's.
            if (module == "runtime" || module == "runtime.test") continue;
            out.push(module);
        }
    }

    static function discoverSourceTypes(project:Project, setName:String):Array<String> {
        final selected = Plan.sourceSet(project, setName);
        if (selected == null) return [];
        final found:Array<String> = [];
        for (rule in selected.discover) {
            for (pack in rule.packages) {
                final directory = resolveAgainst(project.root, joinPath(rule.root, pack.split(".").join("/")));
                if (!exists(directory) || !Host.isDirectory(directory)) {
                    fail('source set "$setName": discover directory does not exist: $directory');
                    return [];
                }
                final entries:Array<String> = [];
                for (entry in Host.readDir(directory)) {
                    if (!Host.isDirectory(joinPath(directory, entry))) entries.push(entry);
                }
                final matches = Plan.discoverTypes(pack, rule.suffix, entries);
                if (matches.length == 0) {
                    fail('source set "$setName": no modules ending in "${rule.suffix}" under $directory');
                    return [];
                }
                for (typePath in matches) found.push(typePath);
            }
        }
        return Plan.sortedUnique(found);
    }

    static function actionRoots(project:Project, setName:String, outputPath:String):Void {
        final selected = Plan.sourceSet(project, setName);
        if (selected == null) {
            fail('unknown source set "$setName"');
            return;
        }
        final output = resolveAgainst(project.root, outputPath);
        makeDirs(Host.dirname(output));
        final contents = Plan.rootsContents(selected, discoverSourceTypes(project, setName));
        var suffix = 0;
        var temporary = output + ".tmp-" + suffix;
        while (exists(temporary)) {
            suffix++;
            temporary = output + ".tmp-" + suffix;
        }
        Host.writeText(temporary, contents);
        Host.rename(temporary, output);
        print('[roots] $setName -> $output');
    }

    /**
        The host compiler one compiled target packs through, from the
        environment or from `PATH` (spec 59).
    **/
    static function resolvePackTool(envVar:String, name:String, bundle:BundleSpec):String {
        final configured = Host.env(envVar);
        final fromEnv:String = configured == null ? "" : configured;
        if (fromEnv.length > 0) {
            return fromEnv;
        }
        final pathValue = Host.env("PATH");
        for (dir in (pathValue == null ? "" : pathValue).split(":")) {
            if (dir.length == 0) {
                continue;
            }
            final candidate = joinPath(dir, name);
            if (exists(candidate)) {
                return candidate;
            }
        }
        fail('bundle "${bundle.id}": pack on the ${bundle.target} target needs $name; set $envVar or put $name on PATH');
        return "";
    }

    // ------------------------------------------------------------------
    // Actions
    // ------------------------------------------------------------------

    static function step(project:Project, bundle:BundleSpec, action:String, stepName:String, cmd:String, args:Array<String>, env:Array<EnvVar>, cwd:Null<String>):Null<BundleStepFailure> {
        final workDir = cwd == null ? project.root : cwd;
        print('  $ ' + cmd + " " + args.join(" "));
        #if js
        if (ChildEvidence.enabled()) {
            // The captured spawn requests buffer output and retains the raw
            // streams; the text below is a decoded copy for the console
            // tail, which stays identical to the uncaptured presentation.
            try {
                final execution = ChildEvidence.execute({bundle: bundle.id, action: action, step: stepName}, cmd, args, workDir, declaredOverrides(env));
                if (!execution.succeeded()) {
                    reportStepFailure(bundle.id, action, stepName, cmd, args, execution.combinedText(), execution.reportedCode());
                    return new BundleStepFailure(bundle.id, action, stepName, cmd, args, execution.combinedText(), execution.reportedCode());
                }
            } catch (problem:ChildEvidenceError) {
                reportEvidenceFailure(problem);
            }
            return null;
        }
        #end
        final result = runCommand(cmd, args, workDir, env);
        if (result.code != 0) {
            reportStepFailure(bundle.id, action, stepName, cmd, args, result.output, result.code);
            return new BundleStepFailure(bundle.id, action, stepName, cmd, args, result.output, result.code);
        }
        return null;
    }

    #if js
    /**
        The declared environment override form of the project step, translated
        at this boundary into the typed form the capture module takes. The
        module never sees the untyped bag.
    **/
    static function declaredOverrides(env:Array<EnvVar>):ChildEnvironment {
        var environment = ChildEnvironment.inherited();
        for (entry in env) {
            environment = environment.withOverride(entry.key, entry.value);
        }
        return environment;
    }
    #end

    #if js
    /** The failure the driver reports when evidence capture itself fails. */
    static function reportEvidenceFailure(problem:ChildEvidenceError):Void {
        printErr("Error: child evidence: " + problem.message);
        if (problem.detail.length > 0) {
            printErr("  detail: " + problem.detail);
        }
        exit(1);
    }
    #end

    /** The failure tail the driver has always shown for a failed step. */
    static function reportStepFailure(bundleId:String, action:String, stepName:String, cmd:String, args:Array<String>, output:String, code:Int):Void {
        printErr('Error: bundle "$bundleId", action "$action", step "$stepName" failed with exit code $code.');
        printErr('  command: $cmd ${args.join(" ")}');
        printErr("  --- output (tail) ---");
        final lines = output.split("\n");
        final tail = lines.length > 40 ? lines.slice(lines.length - 40) : lines;
        for (line in tail) {
            printErr("  " + line);
        }
    }

    static function selectBundles(project:Project, ids:Array<String>):Array<BundleSpec> {
        final out:Array<BundleSpec> = [];
        for (id in ids) {
            var found = false;
            for (bundle in project.bundles) {
                if (bundle.id == id) {
                    out.push(bundle);
                    found = true;
                    break;
                }
            }
            if (!found) {
                final known:Array<String> = [];
                for (bundle in project.bundles) known.push(bundle.id);
                fail('unknown bundle id "$id"; this project declares ${known.join(", ")}');
            }
        }
        return out;
    }

    /**
        The Gradle project that produces the Kotlin Multiplatform publication of
        a kmpPublication bundle. The flake installs it beside the driver and the
        wrapper exports its path; the path is read-only, so the step redirects
        every Gradle output under the bundle's outRoot directory.
    **/
    static function isPublicationProject(path:String):Bool {
        return path.length > 0 && exists(path) && Host.isDirectory(path);
    }

    static function publicationProject():String {
        // The driver package installs the project and its wrapper exports this
        // path, so a published driver always finds its own copy. A driver run
        // outside its wrapper falls back to the flake source tree a caller
        // exports, then to the haxelib checkout a tiqian devShell stages beside
        // its project file.
        final configured = Host.env("BORING_PUBLICATION_PROJECT");
        if (configured != null) {
            final value:String = configured;
            if (isPublicationProject(value)) return value;
        }
        final source = Host.env("BORING_SOURCE");
        if (source != null) {
            final fromSource = joinPath(joinPath(source, "tools"), "kotlin-publication");
            if (isPublicationProject(fromSource)) return fromSource;
        }
        final fromHaxelib = joinPath(joinPath(joinPath(Host.cwd(), ".haxelib"), "boring"), joinPath(joinPath("git", "tools"), "kotlin-publication"));
        if (isPublicationProject(fromHaxelib)) return fromHaxelib;
        fail("bundle driver: kmpPublication found no publication project; tried BORING_PUBLICATION_PROJECT, $BORING_SOURCE/tools/kotlin-publication and <cwd>/.haxelib/boring/git/tools/kotlin-publication");
        return "";
    }

    /**
        How many times one kmpPublication step runs before its failure is final.
        A release runner starts with an empty Gradle home, so the first
        invocation resolves the Kotlin plugin and the Android Gradle plugin from
        the network. Gradle reports a repository it could not reach with the
        same "was not found in any of the following sources" text it uses for a
        missing artifact, and that aborted a release whose staging run of the
        identical project had passed on another runner minutes earlier.
    **/
    static final PUBLICATION_ATTEMPTS = 3;

    /** Pause between two publication attempts, long enough for a transient
        repository failure to clear before the same metadata is requested again. */
    static final PUBLICATION_RETRY_DELAY_MS = 5000;

    /** The Gradle output that names a repository resolution failure. Gradle
        prints these strings for an unreachable, a forbidden and a missing
        artifact alike, which is the only distinction the driver can make. */
    static final REPOSITORY_FAILURE_MARKERS = [
        "was not found in any of the following sources",
        "Could not resolve plugin artifact",
        "Could not resolve all dependencies",
        "Could not resolve all files",
        "Could not resolve all artifacts",
        "Could not GET ",
        "Could not HEAD "
    ];

    static function isRepositoryResolutionFailure(output:String):Bool {
        for (marker in REPOSITORY_FAILURE_MARKERS) {
            if (output.indexOf(marker) >= 0) return true;
        }
        return false;
    }

    /** A synchronous pause between attempts. The publication step runs on the
        JavaScript driver, where Atomics.wait is the only blocking sleep. */
    static function sleepMs(ms:Int):Void {
        #if js
        Syntax.code("Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, {0})", ms);
        #end
    }

    /**
        One publication attempt that returns the command result and leaves
        failure reporting to publishKotlinBundle, which retries a repository
        failure before it becomes the step's final outcome. Mirrors step()'s
        child evidence path.
    **/
    static function runPublicationAttempt(bundle:BundleSpec, cmd:String, args:Array<String>, cwd:String):HostResult {
        #if js
        if (ChildEvidence.enabled()) {
            try {
                final execution = ChildEvidence.execute({bundle: bundle.id, action: "pack", step: "kmpPublication"}, cmd, args, cwd, ChildEnvironment.inherited());
                return {code: execution.reportedCode(), output: execution.combinedText()};
            } catch (problem:ChildEvidenceError) {
                reportEvidenceFailure(problem);
                return {code: 0, output: ""};
            }
        }
        #end
        return runCommand(cmd, args, cwd, []);
    }

    /**
        The built-in Kotlin Multiplatform publication of one pack run: the same
        <outRoot>/<id>/maven directory the bundled command used, filled by the
        publication project that ships with the driver (bundle driver spec 59).

        Every attempt starts from a fresh copy of the installed project and an
        empty bundle Maven directory, so a retried attempt cannot publish from
        the previous attempt's half-written tree. A resolution failure keeps
        the step's standard report only after the last attempt.
    **/
    static function publishKotlinBundle(project:Project, bundle:BundleSpec):Null<BundleStepFailure> {
        final bundleRoot = joinPath(resolveAgainst(project.root, project.outRoot), bundle.id);
        final mavenDir = joinPath(bundleRoot, "maven");
        final projectDir = publicationProject();
        final sourceWrapper = joinPath(projectDir, "gradlew");
        if (!exists(sourceWrapper)) {
            fail('bundle "${bundle.id}": the publication project has no gradlew: $sourceWrapper');
        }
        // Gradle 9 refuses to configure a project whose root directory cannot
        // be written (it writes build/reports/problems there), so the installed
        // project is copied per run. The installed tree stays the source of
        // record and is never written; every output lives under outRoot.
        final workDir = joinPath(bundleRoot, "gradle");
        final runDir = joinPath(workDir, "project");
        final wrapper = joinPath(runDir, "gradlew");
        final buildDir = joinPath(workDir, "build");
        final cacheDir = joinPath(workDir, "project-cache");
        final args:Array<String> = [
            "-p", runDir,
            "publishToMavenLocal",
            "-PmavenDir=" + mavenDir,
            "-PpublicationVersion=" + bundle.packageVersion,
            "-PkotlinGenDir=" + genDir(project, bundle),
            "-PkotlinGenTestsDir=" + genTestsDir(project, bundle),
            "-PbuildRoot=" + buildDir,
            "--project-cache-dir=" + cacheDir,
            "--no-daemon"
        ];
        var attempt = 1;
        while (true) {
            Host.deleteTree(mavenDir);
            makeDirs(mavenDir);
            Host.deleteTree(runDir);
            Host.copyTree(projectDir, runDir);
            makeDirs(buildDir);
            makeDirs(cacheDir);
            print("  $ " + wrapper + " " + args.join(" "));
            final result = runPublicationAttempt(bundle, wrapper, args, workDir);
            if (result.code == 0) {
                if (attempt > 1) print('[pack] ${bundle.id}: kmpPublication passed on attempt $attempt of $PUBLICATION_ATTEMPTS');
                return null;
            }
            if (attempt < PUBLICATION_ATTEMPTS && isRepositoryResolutionFailure(result.output)) {
                printErr('Warning: bundle "${bundle.id}": kmpPublication attempt $attempt of $PUBLICATION_ATTEMPTS could not resolve the build plugins or dependencies from its repositories; retrying in ${Std.int(PUBLICATION_RETRY_DELAY_MS / 1000)}s.');
                sleepMs(PUBLICATION_RETRY_DELAY_MS);
                attempt++;
                continue;
            }
            reportStepFailure(bundle.id, "pack", "kmpPublication", wrapper, args, result.output, result.code);
            return new BundleStepFailure(bundle.id, "pack", "kmpPublication", wrapper, args, result.output, result.code);
        }
        return null;
    }

    static function actionGen(project:Project, bundles:Array<BundleSpec>, pack:Bool):Void {
        for (bundle in bundles) {
            if (pack && bundle.packageName == "") {
                fail('bundle "${bundle.id}": the pack action requires a package (name and version) on every named bundle');
            }
        }
        for (bundle in bundles) {
            final generated = genDir(project, bundle);
            final genTests = genTestsDir(project, bundle);
            makeDirs(generated);
            makeDirs(genTests);
            print('[${pack ? "pack" : "gen"}] ${bundle.id} -> $generated, $genTests');
            final genFailure = step(project, bundle, pack ? "pack" : "gen", "generate", "haxe", genArgs(project, bundle, pack), [], null);
            if (genFailure != null) exit(1);
            // The TypeScript and Rust compilers write the authoritative module
            // names (they know declaration case); other targets keep the scan.
            if (bundle.target != "ts" && bundle.target != "rust" && bundle.target != "dart") writeModuleManifest(project, bundle, generated);
            final afterGen = bundle.afterGen;
            if (afterGen != null) {
                final afterFailure = step(project, bundle, pack ? "pack" : "gen", "afterGen", afterGen.command,
                    afterGen.args, afterGen.env, null);
                if (afterFailure != null) exit(1);
            }
            final publication = bundle.mavenPublication;
            if (pack && publication == null && bundle.kmpPublication) {
                final kmpFailure = publishKotlinBundle(project, bundle);
                if (kmpFailure != null) exit(1);
            }
            if (pack && publication != null) {
                final mavenDir = joinPath(joinPath(resolveAgainst(project.root, project.outRoot), bundle.id), "maven");
                Host.deleteTree(mavenDir);
                makeDirs(mavenDir);
                final publicationEnv:Array<EnvVar> = [];
                for (variable in publication.env) {
                    publicationEnv.push({key: variable.key, value: publicationValue(variable.value, mavenDir, bundle.packageVersion)});
                }
                final publicationFailure = step(project, bundle, "pack", "mavenPublication", publication.command,
                    publicationArguments(publication.args, mavenDir, bundle.packageVersion), publicationEnv, null);
                if (publicationFailure != null) exit(1);
            }
        }
        if (pack && packRegistry != null) {
            RegistryMetadata.emitAll(project, bundles, packRegistry);
        }
    }

    static function actionTest(project:Project, bundles:Array<BundleSpec>):Array<BundleStepFailure> {
        final failures:Array<BundleStepFailure> = [];
        makeDirs(resolveAgainst(project.root, project.resultsDir));
        for (bundle in bundles) {
            if (!bundle.hasTests) {
                fail('bundle "${bundle.id}": this target configuration has test=false and cannot run the test action');
            }
            print('[test] ${bundle.id}');
            final generated = genDir(project, bundle);
            final genTests = genTestsDir(project, bundle);
            final build = buildDir(project, bundle);
            final results = resultsPath(project, bundle);
            deleteFile(results);
            makeDirs(build);
            final suffix = bundle.target == "kotlin" ? ".kt" : ".swift";
            final genFiles:Array<String> = [];
            final testFiles:Array<String> = [];
            if (bundle.target == "kotlin" || bundle.target == "swift") {
                for (file in walkFiles(generated, suffix)) genFiles.push(joinPath(generated, file));
                for (file in walkFiles(genTests, suffix)) testFiles.push(joinPath(genTests, file));
            }
            final swiftModule = bundle.target == "swift" ? swiftTestImport(project, bundle) : null;
            final systemPackage = bundle.target == "swift" ? swiftSystemPackageDir(bundle, genFiles, testFiles) : null;
            final host = Host.platform();
            final variable = Plan.swiftLibraryPathVariable(host);
            final previousPath = Host.env(variable);
            final existingPath = previousPath == null ? "" : previousPath;
            // The development shell exports the loader that matches the glibc
            // it links and the library directories the pinned loader can no
            // longer take from the host. Both reach the Swift test recipe.
            final swiftLoader = bundle.target == "swift" ? Host.env("BORING_SWIFT_DYNAMIC_LINKER") : null;
            final swiftHostLibraries = bundle.target == "swift" ? Host.env("BORING_SWIFT_LIBDISPATCH") : null;
            try {
                final steps = Plan.testSteps(project, bundle, generated, genTests, build, results,
                    genFiles, testFiles, haxeTestMain(project, bundle), swiftModule, systemPackage, host, existingPath,
                    swiftLoader, swiftHostLibraries);
                for (planned in steps) {
                    final stepFailure = step(project, bundle, "test", planned.name, planned.command, planned.args, planned.env, planned.cwd);
                    if (stepFailure != null) {
                        failures.push(stepFailure);
                        break;
                    }
                }
            } catch (error:DriverException) {
                fail(Diagnostic.describe(error.fault));
            }
        }
        return failures;
    }

    /**
        The directory holding a prebuilt SystemPackage swiftmodule, when
        the bundle's generated tree imports it. swiftc carries no package
        graph: the SwiftPM-only module a std.Fs host edge imports is not
        derivable from the compilation, so the environment names a built
        module directory (BORING_SWIFT_SYSTEM_PACKAGE). Without it the
        run stops with the variable named and without a bare compiler
        error. (SwiftModuleDependencies)
    **/
    static function swiftSystemPackageDir(bundle:BundleSpec, genFiles:Array<String>, testFiles:Array<String>):Null<String> {
        var imports = false;
        for (file in genFiles.concat(testFiles)) {
            if (readText(file).indexOf("import SystemPackage") >= 0) {
                imports = true;
                break;
            }
        }
        if (!imports) {
            return null;
        }
        final configured = Host.env("BORING_SWIFT_SYSTEM_PACKAGE");
        final fromEnv:String = configured == null ? "" : configured;
        if (fromEnv.length == 0) {
            fail('bundle "${bundle.id}": the generated tree imports SystemPackage, which the swift toolchain does not ship; build the module (e.g. from the apple/swift-system sources pinned by Package.resolved) and point BORING_SWIFT_SYSTEM_PACKAGE at the directory holding SystemPackage.swiftmodule and its shared library');
        }
        if (!exists(joinPath(fromEnv, "SystemPackage.swiftmodule"))) {
            fail('bundle "${bundle.id}": BORING_SWIFT_SYSTEM_PACKAGE names $fromEnv, which holds no SystemPackage.swiftmodule');
        }
        return fromEnv;
    }

    /**
        The value of one `-D <name>=<value>` pair of an argument list,
        when the list carries it.
    **/
    static function defineValue(args:Array<String>, name:String):Null<String> {
        var i = 0;
        while (i + 1 < args.length) {
            if (args[i] == "-D" && StringTools.startsWith(args[i + 1], name + "=")) {
                return args[i + 1].substr(name.length + 1);
            }
            i++;
        }
        return null;
    }

    /**
        The value of one `-D <name>=<value>` pair on the bundle's
        roots file include chain, when the chain carries it. The roots
        file is what the generation command feeds haxe, so a define it
        pulls in is as effective as one in `haxeArgs`; a project whose
        target entries already state `swift-test-import` needs no
        copy in the project file. Include lines resolve against the
        project root, where the generation command runs, with the
        including file's own directory as fallback; a later define
        wins, matching haxe's own last-value rule.
    **/
    static function rootsFileDefine(project:Project, bundle:BundleSpec, name:String):Null<String> {
        final rootsFile = bundle.rootsFile != "" ? bundle.rootsFile : project.rootsFile;
        if (rootsFile == "") {
            return null;
        }
        return hxmlDefineValue(resolveAgainst(project.root, rootsFile), name, [], project.root);
    }

    static function hxmlDefineValue(path:String, name:String, seen:Array<String>, base:String):Null<String> {
        if (seen.indexOf(path) >= 0 || !exists(path)) {
            return null;
        }
        seen.push(path);
        var found:Null<String> = null;
        for (rawLine in readText(path).split("\n")) {
            final line = hxmlStripComment(rawLine);
            final tokens = splitWhitespace(line);
            if (tokens.length == 0) {
                continue;
            }
            if (tokens[0] == "-D" || tokens[0] == "--define") {
                // One hxml line carries the pair haxe sees: -D plus one
                // name=value token; the JSON haxeArgs form splits them.
                if (StringTools.startsWith(tokens[1], name + "=")) {
                    found = tokens[1].substr(name.length + 1);
                } else if (tokens[1] == name && tokens.length >= 3) {
                    found = tokens.slice(2).join(" ");
                }
                continue;
            }
            if (tokens.length == 1 && !StringTools.startsWith(tokens[0], "-")) {
                // haxe resolves an include against its working
                // directory, which is the project root here; the
                // including file's own directory is the fallback for
                // entries written the other way.
                var included = hxmlDefineValue(resolveAgainst(base, tokens[0]), name, seen, base);
                if (included == null) {
                    included = hxmlDefineValue(resolveAgainst(directoryOf(path), tokens[0]), name, seen, base);
                }
                if (included != null) {
                    found = included + "";
                }
            }
        }
        return found;
    }

    static function hxmlStripComment(line:String):String {
        final cut = line.indexOf("#");
        return StringTools.trim(cut < 0 ? line : line.substr(0, cut));
    }

    static function splitWhitespace(line:String):Array<String> {
        final tokens:Array<String> = [];
        var start = -1;
        var i = 0;
        while (i < line.length) {
            final c = line.charAt(i);
            final space = c == " " || c == "\t" || c == "\r" || c == "\n";
            if (space && start >= 0) {
                tokens.push(line.substr(start, i - start));
                start = -1;
            } else if (!space && start < 0) {
                start = i;
            }
            i++;
        }
        if (start >= 0) tokens.push(line.substr(start));
        return tokens;
    }

    static function directoryOf(path:String):String {
        final cut = path.lastIndexOf("/");
        return cut < 0 ? "." : path.substr(0, cut);
    }

    /**
        The library module name of the swift recipe, read from the
        `swift-test-import` define of the bundle's effective
        arguments, or of the roots file include chain that the same
        command compiles through.
    **/
    static function swiftTestImport(project:Project, bundle:BundleSpec):String {
        final module = defineValue(genArgs(project, bundle, false), "swift-test-import");
        if (module == null) {
            final fromRoots = rootsFileDefine(project, bundle, "swift-test-import");
            if (fromRoots != null) {
                return fromRoots;
            }
            fail('bundle "${bundle.id}": the swift recipe needs the library module name; put -D swift-test-import=<module> in the bundle haxeArgs, or in the roots file chain that the bundle compiles through');
            return "";
        }
        return module;
    }

    /**
        The main class of the haxe recipe's test build, read from the
        `haxe-test-main` define of the bundle's effective arguments.
        The binary64 reference entry is TestMain; the f32 oracle runner
        (features/44) is generated as TestMainF32 into the bundle's
        derived gen-tests directory, so the f32 bundle states the
        entry.
    **/
    static function haxeTestMain(project:Project, bundle:BundleSpec):String {
        var main:Null<String> = null;
        try {
            main = defineValue(genArgs(project, bundle, false), "haxe-test-main");
        } catch (e:std.FsException) {
            throw new DriverException(InvalidConfig(
                'bundle "${bundle.id}": cannot read haxe-test-main define: ${e.message}'));
        }
        return main == null ? "TestMain" : main;
    }

    static function actionCompare(project:Project):Void {
        final ids:Array<String> = [];
        for (bundle in Plan.comparable(project.bundles)) ids.push(bundle.id);
        print('[compare] baseline ${project.baseline} over ${ids.copy().join(",")}');
        Compare.run(resolveAgainst(project.root, project.resultsDir), ids, project.baseline);
    }

    /** Return the first non-empty line, or null when there is none. */
    static function firstErrorLine(output:String):Null<String> {
        final lines = output.split("\n");
        for (line in lines) {
            if (line.length > 0) return line;
        }
        return null;
    }

    /**
        Prints an aggregate failure report after continuing past per-bundle
        test failures, so every failing bundle appears in one report.
    **/
    static function reportAggregate(failures:Array<BundleStepFailure>):Void {
        printErr("");
        printErr("--- aggregate report: " + failures.length + " bundle(s) failed ---");
        for (failure in failures) {
            printErr('  ${failure.bundleId}: exit code ${failure.code} (step "${failure.stepName}")');
            final firstError = firstErrorLine(failure.output);
            if (firstError != null) {
                printErr('    first error: ${firstError}');
            }
        }
        printErr("");
    }

    static function actionVerify(project:Project, withPack:Bool):Void {
        actionGen(project, project.bundles, false);
        final failures = actionTest(project, Plan.testable(project.bundles));
        if (failures.length > 0) {
            reportAggregate(failures);
            exit(1);
        }
        actionCompare(project);
        if (withPack) {
            actionGen(project, Plan.packable(project.bundles), true);
        }
    }

    // ------------------------------------------------------------------
    // Entry
    // ------------------------------------------------------------------

    public static function main():Void {
        final rawArgs = Host.args();
        var projectPath = "boring.json";
        var withPack = false;
        var outputPath = "";
        var baseRev = "HEAD";
        var registryOut = "";
        var registryOwner = "";
        var registryRepo = "";
        var registryAssetBase = "";
        final rest:Array<String> = [];
        var i = 0;
        while (i < rawArgs.length) {
            final arg = rawArgs[i];
            if (arg == "--project") {
                if (i + 1 >= rawArgs.length) {
                    fail("--project needs a file path");
                }
                projectPath = rawArgs[i + 1];
                i += 2;
                continue;
            }
            if (StringTools.startsWith(arg, "--project=")) {
                projectPath = arg.substr("--project=".length);
                i++;
                continue;
            }
            if (arg == "--with-pack") {
                withPack = true;
                i++;
                continue;
            }
            if (arg == "--output") {
                if (i + 1 >= rawArgs.length) fail("--output needs a file path");
                outputPath = rawArgs[i + 1];
                i += 2;
                continue;
            }
            if (StringTools.startsWith(arg, "--output=")) {
                outputPath = arg.substr("--output=".length);
                i++;
                continue;
            }
            if (arg == "--base") {
                if (i + 1 >= rawArgs.length) fail("--base needs a revision");
                baseRev = rawArgs[i + 1];
                i += 2;
                continue;
            }
            if (StringTools.startsWith(arg, "--base=")) {
                baseRev = arg.substr("--base=".length);
                i++;
                continue;
            }
            if (arg == "--registry-out") {
                if (i + 1 >= rawArgs.length) fail("--registry-out needs a directory");
                registryOut = rawArgs[i + 1];
                i += 2;
                continue;
            }
            if (StringTools.startsWith(arg, "--registry-out=")) {
                registryOut = arg.substr("--registry-out=".length);
                i++;
                continue;
            }
            if (arg == "--owner") {
                if (i + 1 >= rawArgs.length) fail("--owner needs a name");
                registryOwner = rawArgs[i + 1];
                i += 2;
                continue;
            }
            if (StringTools.startsWith(arg, "--owner=")) {
                registryOwner = arg.substr("--owner=".length);
                i++;
                continue;
            }
            if (arg == "--repo") {
                if (i + 1 >= rawArgs.length) fail("--repo needs a name");
                registryRepo = rawArgs[i + 1];
                i += 2;
                continue;
            }
            if (StringTools.startsWith(arg, "--repo=")) {
                registryRepo = arg.substr("--repo=".length);
                i++;
                continue;
            }
            if (arg == "--asset-base") {
                if (i + 1 >= rawArgs.length) fail("--asset-base needs a URL");
                registryAssetBase = rawArgs[i + 1];
                i += 2;
                continue;
            }
            if (StringTools.startsWith(arg, "--asset-base=")) {
                registryAssetBase = arg.substr("--asset-base=".length);
                i++;
                continue;
            }
            rest.push(arg);
            i++;
        }
        if (rest.length == 0) {
            printErr("Usage: boring <gen|test|pack|compare|verify|roots|gp-diff|gp-ablate> [<id>...] [--project <file>] [--with-pack] [--output <file>] [--base <rev>] [--registry-out <dir> --owner <name> --repo <name> --asset-base <url>]");
            exit(2);
            return;
        }
        final action:String = rest[0];
        final ids:Array<String> = [];
        var idIndex = 1;
        while (idIndex < rest.length) {
            ids.push(rest[idIndex]);
            idIndex++;
        }
        var registrySet = 0;
        for (value in [registryOut, registryOwner, registryRepo, registryAssetBase]) {
            if (value != "") registrySet++;
        }
        if (registrySet != 0 && registrySet != 4) {
            fail("registry metadata needs --registry-out, --owner, --repo and --asset-base together");
        }
        if (registrySet == 4) {
            packRegistry = {out: registryOut, owner: registryOwner, repo: registryRepo, assetBase: registryAssetBase};
        }
        final project = loadProject(projectPath);
        #if js
        // Evidence capture reads the project identity once and allocates one
        // fresh run directory for the whole invocation; without the setting
        // it holds nothing and the driver behaves as before.
        if (action != "roots") {
            try {
                ChildEvidence.begin(project.path);
            } catch (problem:ChildEvidenceError) {
                reportEvidenceFailure(problem);
            }
        }
        #end
        if (action == "roots") {
            if (ids.length != 1) fail("roots needs exactly one source set name");
            if (outputPath == "") fail("roots needs --output <file>");
            actionRoots(project, ids[0], outputPath);
            print("bundle driver: ok");
            return;
        }
        if (outputPath != "") fail("--output is only accepted by roots");
        final known:Array<String> = [];
        for (bundle in project.bundles) known.push(bundle.id);
        if (action == "gen") {
            if (ids.length == 0) fail('gen names no bundle; this project declares ${known.join(", ")}');
            actionGen(project, selectBundles(project, ids), false);
        } else if (action == "test") {
            if (ids.length == 0) fail('test names no bundle; this project declares ${known.join(", ")}');
            final testFailures = actionTest(project, selectBundles(project, ids));
            if (testFailures.length > 0) {
                reportAggregate(testFailures);
                exit(1);
            }
        } else if (action == "pack") {
            if (ids.length == 0) fail('pack names no bundle; this project declares ${known.join(", ")}');
            actionGen(project, selectBundles(project, ids), true);
        } else if (action == "compare") {
            actionCompare(project);
        } else if (action == "verify") {
            actionVerify(project, withPack);
        } else if (action == "gp-diff") {
            final gpDiffCode = GpDiff.run(project, ids, baseRev);
            if (gpDiffCode != 0) exit(gpDiffCode);
        } else if (action == "gp-ablate") {
            final gpAblateCode = GpAblate.run(project, ids);
            if (gpAblateCode != 0) exit(gpAblateCode);
        } else {
            fail('unknown action "$action"; the actions are gen, test, pack, compare, verify, roots, gp-diff, gp-ablate');
        }
        print("bundle driver: ok");
    }
}