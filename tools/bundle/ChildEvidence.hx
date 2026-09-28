import haxe.Json;
import js.Syntax;

/**
    Child execution evidence for the bundle driver (feature spec 59).

    When `BORING_CHILD_EVIDENCE_DIR` names a directory, every command the
    driver runs through `step` spawns through this module, which requests
    buffer output from the host process API. The child's bytes are retained
    exactly and a copy is decoded only for the console failure tail; the
    UTF-8 `runCommand` helper stays for the uncaptured path. The driver
    keeps its short console output, and the retained streams are the
    authority for warning inspection.

    When the setting is absent the module holds no run and the driver keeps
    its previous behaviour unchanged.

    One driver invocation allocates one run directory under the configured
    parent through exclusive, non-recursive creation, so an existing entry
    is never reused as fresh evidence. The invocation identifier is derived
    from the directory that the exclusive allocation actually created, so
    the identity and the allocation can never disagree. Every child of that
    invocation carries the same identifier and its own sequence number.

    A capture write failure fails the driver: an incomplete record cannot
    stand for a passed child. The module records every fact it can before
    failing, and a record that names a file always names a file that exists.
    The `compare` action's direct consistency manager execution stays outside
    this module and keeps its console behaviour, so one driver run does not
    establish complete evidence for that action.
**/
/**
    The host environment of one spawn: the inherited values plus the declared
    overrides, keyed by name. Values are host strings and are never read back
    by this module; the recorded fact about it is the override name list.
**/
typedef HostEnvironmentBag = haxe.DynamicAccess<String>;

/**
    The shape of a host error object. `code` is present on the platform's own
    system errors, such as ENOENT, ENOBUFS, EEXIST, and ENOTDIR; a plain host
    error carries only its message.
**/
extern class HostError {
    var code:Null<String>;
    var message:Null<String>;
}

/** The module's form of one host error: a platform code name and its message. */
typedef HostErrorReport = {
    var code:String;
    var message:String;
};

/**
    An opaque host byte sequence. Values of this type never pass through a
    Haxe String on the capture path; decoding happens only on an explicit
    copy for console presentation.
**/
extern class NodeBuffer {
    var length:Int;
    function toString(encoding:String):String;
}

/** Options of the buffer output spawn; the buffer encoding keeps the bytes. */
typedef SpawnBufferOptions = {
    var cwd:String;
    var env:HostEnvironmentBag;
    var maxBuffer:Int;
    var encoding:String;
};

/** The host outcome of one synchronous spawn, with independent absence fields. */
typedef SpawnSyncOutcome = {
    @:optional var error:Null<HostError>;
    @:optional var status:Null<Int>;
    @:optional var signal:Null<String>;
    @:optional var stdout:Null<NodeBuffer>;
    @:optional var stderr:Null<NodeBuffer>;
};

@:jsRequire("child_process")
extern class NodeChildProcess {
    @:overload(function(command:String, args:Array<String>, options:SpawnBufferOptions):SpawnSyncOutcome {})
    static function spawnSync(command:String, args:Array<String>):SpawnSyncOutcome;
}

/** Options of recursive directory creation; this form cannot establish a fresh run. */
typedef MkdirRecursiveOptions = {
    var recursive:Bool;
};

/**
    Exclusive, non-recursive directory creation. An existing entry raises the
    platform EEXIST condition, which is the collision signal the fresh run
    allocator acts on.
**/
@:jsRequire("fs")
extern class NodeDirectoryCreate {
    static function mkdirSync(path:String):Void;
}

/**
    Recursive directory creation. It creates missing parents and succeeds on
    an existing directory, so it cannot establish a fresh run by itself.
**/
@:jsRequire("fs")
extern class NodeDirectoryTree {
    static function mkdirSync(path:String, options:MkdirRecursiveOptions):Void;
}

@:jsRequire("fs")
extern class NodeFile {
    @:overload(function(path:String, data:NodeBuffer):Void {})
    static function writeFileSync(path:String, data:String):Void;

    @:overload(function(path:String, encoding:String):String {})
    static function readFileSync(path:String):NodeBuffer;

    static function existsSync(path:String):Bool;
}

@:jsRequire("crypto")
extern class NodeHash {
    static function createHash(algorithm:String):NodeDigest;
}

extern class NodeDigest {
    @:overload(function(data:NodeBuffer):NodeDigest {})
    function update(data:String):NodeDigest;

    function digest(encoding:String):String;
}

/**
    How one captured child ended. The host reports a null status both for a
    child that was delivered a signal and for one it failed to launch, so
    those two are distinct outcomes and neither is a normal exit.
**/
enum ChildOutcome {
    /** The child exited normally; the status may still be nonzero. */
    OutcomeNormalExit(status:Int);

    /** The host delivered a signal to the child. */
    OutcomeSignaled(signal:String);

    /** The host could not start the child. */
    OutcomeLaunchFailed(reason:String);

    /** The host stopped or failed the spawn in another way; capture is uncertain. */
    OutcomeInterrupted(reason:String);
}

/**
    A failure of the evidence machinery itself: a directory that cannot be
    allocated, a capture write that did not reach the disk, or a spawn the
    host rejected as a thrown value when it returned no error value. It
    extends the repository error type, so a reported evidence failure is an
    Exception.
**/
class ChildEvidenceError extends haxe.Exception {
    public final detail:String;
    public final childDirectory:Null<String>;
    public final recordPath:Null<String>;

    public function new(message:String, detail:String, childDirectory:Null<String> = null, recordPath:Null<String> = null) {
        super(message);
        this.detail = detail;
        this.childDirectory = childDirectory;
        this.recordPath = recordPath;
    }
}

/** One declared environment override of a recipe step: a name and its value. */
typedef EnvironmentOverride = {
    var name:String;
    var value:String;
};

/**
    The environment of one captured spawn. The host object stays internal to
    this class; the facts the module records about it are the override names,
    and the inherited values are never read back or serialized.
**/
class ChildEnvironment {
    final bag:HostEnvironmentBag;
    final overrideNames:Array<String>;

    function new(bag:HostEnvironmentBag, overrideNames:Array<String>) {
        this.bag = bag;
        this.overrideNames = overrideNames;
    }

    /** The inherited host environment with nothing declared on top of it. */
    public static function inherited():ChildEnvironment {
        final bag:HostEnvironmentBag = Syntax.code("({...process.env})");
        return new ChildEnvironment(bag, []);
    }

    /** The inherited host environment carrying one declared override. */
    public function withOverride(name:String, value:String):ChildEnvironment {
        bag[name] = value;
        final names = overrideNames.copy();
        names.push(name);
        return new ChildEnvironment(bag, names);
    }

    /** The host object one spawn call receives. */
    public function hostBag():HostEnvironmentBag {
        return bag;
    }

    /** The declared override names, in declaration order. */
    public function names():Array<String> {
        return overrideNames.copy();
    }
}

/**
    The identity of one step invocation. Bundle, action, and step names may
    repeat inside one run; the sequence number distinguishes them.
**/
typedef ChildContext = {
    var bundle:String;
    var action:String;
    var step:String;
};

/**
    One captured execution. Status, signal, and launch error stay separate,
    and the outcome names how the child ended. Capture completeness is false
    whenever the host reported an error, truncated a stream, or an evidence
    write failed; a record that reports a stream path names a file that
    exists, and an unavailable stream is recorded as absent, never as
    an empty file.
**/
class ChildExecution {
    public var outcome(default, null):ChildOutcome;
    public var exitStatus(default, null):Null<Int>;
    public var signal(default, null):Null<String>;
    public var launchError(default, null):Null<String>;
    public var captureComplete(default, null):Bool;
    public var captureError(default, null):Null<String>;
    public var stdoutAvailable(default, null):Bool;
    public var stderrAvailable(default, null):Bool;
    public var recordPath(default, null):Null<String>;
    public var childDirectory(default, null):String;
    public var sequence(default, null):Int;

    var stdout:Null<NodeBuffer>;
    var stderr:Null<NodeBuffer>;

    public function new(outcome:ChildOutcome, exitStatus:Null<Int>, signal:Null<String>, launchError:Null<String>, stdout:Null<NodeBuffer>,
            stderr:Null<NodeBuffer>, captureComplete:Bool, captureError:Null<String>, stdoutAvailable:Bool, stderrAvailable:Bool, childDirectory:String,
            sequence:Int, recordPath:String) {
        this.outcome = outcome;
        this.exitStatus = exitStatus;
        this.signal = signal;
        this.launchError = launchError;
        this.stdout = stdout;
        this.stderr = stderr;
        this.captureComplete = captureComplete;
        this.captureError = captureError;
        this.stdoutAvailable = stdoutAvailable;
        this.stderrAvailable = stderrAvailable;
        this.childDirectory = childDirectory;
        this.sequence = sequence;
        this.recordPath = recordPath;
    }

    /** True only for a normal zero exit with no signal and no launch failure. */
    public function succeeded():Bool {
        return switch (outcome) {
            case OutcomeNormalExit(status): status == 0;
            case _: false;
        }
    }

    /** The status the driver's existing failure text reports for this outcome. */
    public function reportedCode():Int {
        return exitStatus == null ? -1 : (exitStatus : Int);
    }

    /** A decoded copy for console presentation; the retained bytes stay the authority. */
    public function combinedText():String {
        return stdoutText() + stderrText();
    }

    public function stdoutText():String {
        return stdout == null ? "" : stdout.toString("utf8");
    }

    public function stderrText():String {
        return stderr == null ? "" : stderr.toString("utf8");
    }
}

/**
    The serialized evidence of one child. `stdoutPath` and `stderrPath` are
    set only for streams that were actually written, so every recorded file
    claim is true; an unavailable stream is recorded through its availability
    flag and a zero length. The record names the driver inputs through the
    project path, its content identity, and the invocation identifier; it
    does not state which compiler source a package resolver actually loaded.
    Only the declared override names are recorded; the inherited environment
    is never serialized.
**/
typedef ChildEvidenceRecord = {
    var invocationId:String;
    var sequence:Int;
    var bundle:String;
    var action:String;
    var step:String;
    var command:String;
    var argv:Array<String>;
    var cwd:String;
    var envOverrideKeys:Array<String>;
    var startedAtMs:Float;
    var endedAtMs:Float;
    var elapsedMs:Float;
    var outcome:String;
    var outcomeDetail:Null<String>;
    var exitStatus:Null<Int>;
    var signal:Null<String>;
    var launchError:Null<String>;
    var stdoutAvailable:Bool;
    var stderrAvailable:Bool;
    var stdoutPath:Null<String>;
    var stderrPath:Null<String>;
    var childDirectory:String;
    var stdoutBytes:Int;
    var stderrBytes:Int;
    var captureComplete:Bool;
    var captureError:Null<String>;
    var projectPath:String;
    var projectHash:String;
    var maxBufferBytes:Int;
};

/** One spawn call: either the host's outcome, or the error it raised instead. */
typedef SpawnAttempt = {
    var outcome:Null<SpawnSyncOutcome>;
    var raised:Null<HostErrorReport>;
};

/** One driver invocation's evidence run: one exclusive allocation and a shared identity. */
class ChildRun {
    public var directory(default, null):String;
    public var invocationId(default, null):String;

    var projectPath:String;
    var projectHash:String;
    var maxBufferBytes:Int;
    var sequence:Int;

    function new(directory:String, invocationId:String, projectPath:String, projectHash:String, maxBufferBytes:Int) {
        this.directory = directory;
        this.invocationId = invocationId;
        this.projectPath = projectPath;
        this.projectHash = projectHash;
        this.maxBufferBytes = maxBufferBytes;
        sequence = 0;
    }

    /**
        Creates the run directory under `parent` with the host clock and
        process identity, and fails when the setting cannot be honoured.
    **/
    public static function open(parent:String, projectPath:String, maxBufferBytes:Int):ChildRun {
        return allocate(parent, projectPath, maxBufferBytes, ChildEvidence.nowMs(), processIdentity());
    }

    /**
        Creates the run directory under `parent` from an explicit naming
        identity, which is the whole of what distinguishes one allocation
        from another: the stamp, the process identity, and the attempt
        suffix that an exclusive allocation ends up with. The invocation
        identifier is derived from the created directory, so it names the
        allocation that exists and not only the request.
    **/
    public static function allocate(parent:String, projectPath:String, maxBufferBytes:Int, stampMs:Float, processId:String):ChildRun {
        if (!NodeFile.existsSync(parent)) {
            try {
                NodeDirectoryTree.mkdirSync(parent, {recursive: true});
            } catch (problem:haxe.Exception) {
                throw new ChildEvidenceError('cannot create the evidence parent $parent', Std.string(problem));
            }
        }
        final stamp = Std.string(stampMs);
        for (attempt in 1...1000) {
            final suffix = attempt == 1 ? "" : "-" + attempt;
            final name = "run-" + stamp + "-" + processId + suffix;
            final candidate = parent + "/" + name;
            try {
                NodeDirectoryCreate.mkdirSync(candidate);
                return new ChildRun(candidate, "inv-" + name, projectPath, contentIdentity(projectPath), maxBufferBytes);
            } catch (problem:haxe.Exception) {
                if (errorCode(ChildEvidence.hostErrorOf(problem)) != "EEXIST") {
                    throw new ChildEvidenceError('cannot create the evidence run directory $candidate',
                        Std.string(problem) + " (" + describeError(ChildEvidence.hostErrorOf(problem)) + ")");
                }
            }
        }
        throw new ChildEvidenceError('no fresh evidence run directory could be created under $parent', "every candidate name already existed");
    }

    public function capture(context:ChildContext, command:String, argv:Array<String>, cwd:String, environment:ChildEnvironment):ChildExecution {
        sequence += 1;
        final childDirectory = directory + "/" + StringTools.lpad(Std.string(sequence), "0", 4);
        try {
            NodeDirectoryCreate.mkdirSync(childDirectory);
        } catch (problem:haxe.Exception) {
            throw new ChildEvidenceError('cannot create the evidence directory $childDirectory', Std.string(problem));
        }
        final startedAt = ChildEvidence.nowMs();
        final attempt = trySpawn(command, argv, cwd, environment);
        final endedAt = ChildEvidence.nowMs();
        if (attempt.outcome == null) {
            // The host raised with no returned outcome, so no stream
            // exists and nothing about the child is known. The record states
            // that, and the run fails without reporting a capture.
            final raised = attempt.raised == null ? "no detail from the host" : describeError(attempt.raised);
            return interrupted(childDirectory, sequence, startedAt, endedAt, context, command, argv, cwd, environment,
                'the host raised before it could report an outcome for "$command": $raised, so the capture is uncertain');
        }
        final outcome = attempt.outcome;
        final outcomeError = outcome.error;
        final hasHostError = outcomeError != null;
        final hostError = ChildEvidence.errorReportOf(outcomeError, null);
        final errorCodeName = errorCode(hostError);
        final launchError = describeError(hostError);
        final stdout = outcome.stdout;
        final stderr = outcome.stderr;
        final stdoutAvailable = stdout != null;
        final stderrAvailable = stderr != null;
        final exitStatus = normalizeStatus(outcome.status);
        final signal = normalizeText(outcome.signal);

        var outcomeKind:ChildOutcome;
        var outcomeDetail:Null<String> = null;
        var captureError:Null<String> = null;
        if (hasHostError) {
            if (stdoutAvailable || stderrAvailable || exitStatus != null || signal != null) {
                // The child started, so what arrived is retained; only the
                // buffer exhaustion error states a cause, and any other host
                // error stays an uncertain capture with its real code.
                outcomeKind = signal != null ? OutcomeSignaled(signal) : OutcomeInterrupted(launchError);
                outcomeDetail = launchError;
                captureError = errorCodeName == "ENOBUFS"
                    ? 'the host stopped the child at the $maxBufferBytes byte capture limit: $launchError'
                    : 'the host reported $errorCodeName while the child ran, so the capture is uncertain: $launchError';
            } else {
                // Nothing arrived and no status was reported: the child never
                // started, which is a launch failure and not a capture.
                outcomeKind = OutcomeLaunchFailed(launchError);
                outcomeDetail = launchError;
                captureError = 'the host could not start "$command": $launchError';
            }
        } else if (signal != null) {
            outcomeKind = OutcomeSignaled(signal);
            outcomeDetail = signal;
        } else if (exitStatus != null) {
            outcomeKind = OutcomeNormalExit(exitStatus);
            outcomeDetail = Std.string(exitStatus);
        } else {
            outcomeKind = OutcomeInterrupted("the host reported neither a status nor a signal");
            outcomeDetail = "the host outcome carries no status and no signal";
            captureError = "the host outcome carries no status and no signal";
        }

        final stdoutPath = writeStream(childDirectory, "stdout.bin", stdout, "stdout", function(problem:String) {
            captureError = joinCapture(captureError, problem);
        });
        final stderrPath = writeStream(childDirectory, "stderr.bin", stderr, "stderr", function(problem:String) {
            captureError = joinCapture(captureError, problem);
        });
        final recordPath = childDirectory + "/record.json";
        final record:ChildEvidenceRecord = {
            invocationId: invocationId,
            sequence: sequence,
            bundle: context.bundle,
            action: context.action,
            step: context.step,
            command: command,
            argv: argv,
            cwd: cwd,
            envOverrideKeys: environment.names(),
            startedAtMs: startedAt,
            endedAtMs: endedAt,
            elapsedMs: endedAt - startedAt,
            outcome: outcomeName(outcomeKind),
            outcomeDetail: outcomeDetail,
            exitStatus: exitStatus,
            signal: signal,
            launchError: launchError,
            stdoutAvailable: stdoutAvailable,
            stderrAvailable: stderrAvailable,
            stdoutPath: stdoutPath,
            stderrPath: stderrPath,
            childDirectory: childDirectory,
            stdoutBytes: stdout == null ? 0 : stdout.length,
            stderrBytes: stderr == null ? 0 : stderr.length,
            captureComplete: captureError == null,
            captureError: captureError,
            projectPath: projectPath,
            projectHash: projectHash,
            maxBufferBytes: maxBufferBytes,
        };
        try {
            NodeFile.writeFileSync(recordPath, Json.stringify(record));
        } catch (problem:haxe.Exception) {
            captureError = joinCapture(captureError, 'evidence record write failed: $problem');
        }
        if (captureError != null) {
            throw new ChildEvidenceError('child evidence for step "${context.step}" of bundle "${context.bundle}" is incomplete: $captureError',
                "the child evidence record states what was retained", childDirectory, recordPath);
        }
        return new ChildExecution(outcomeKind, exitStatus, signal, launchError, stdout, stderr, true, null, stdoutAvailable, stderrAvailable, childDirectory,
            sequence, recordPath);
    }

    /**
        Writes the retained record for a spawn the host raised on, then fails
        the run. Nothing about the child is known, so no stream is claimed.
    **/
    function interrupted(childDirectory:String, sequence:Int, startedAt:Float, endedAt:Float, context:ChildContext, command:String, argv:Array<String>,
            cwd:String, environment:ChildEnvironment, reason:String):ChildExecution {
        final recordPath = childDirectory + "/record.json";
        final record:ChildEvidenceRecord = {
            invocationId: invocationId,
            sequence: sequence,
            bundle: context.bundle,
            action: context.action,
            step: context.step,
            command: command,
            argv: argv,
            cwd: cwd,
            envOverrideKeys: environment.names(),
            startedAtMs: startedAt,
            endedAtMs: endedAt,
            elapsedMs: endedAt - startedAt,
            outcome: outcomeName(OutcomeInterrupted(reason)),
            outcomeDetail: reason,
            exitStatus: null,
            signal: null,
            launchError: reason,
            stdoutAvailable: false,
            stderrAvailable: false,
            stdoutPath: null,
            stderrPath: null,
            childDirectory: childDirectory,
            stdoutBytes: 0,
            stderrBytes: 0,
            captureComplete: false,
            captureError: reason,
            projectPath: projectPath,
            projectHash: projectHash,
            maxBufferBytes: maxBufferBytes,
        };
        try {
            NodeFile.writeFileSync(recordPath, Json.stringify(record));
        } catch (problem:haxe.Exception) {
            throw new ChildEvidenceError("child evidence record write failed", Std.string(problem), childDirectory, recordPath);
        }
        throw new ChildEvidenceError('child evidence for step "${context.step}" is incomplete: $reason', "the host outcome carries no stream and no status",
            childDirectory, recordPath);
    }

    function trySpawn(command:String, argv:Array<String>, cwd:String, environment:ChildEnvironment):SpawnAttempt {
        final options:SpawnBufferOptions = {
            cwd: cwd,
            env: environment.hostBag(),
            maxBuffer: maxBufferBytes,
            encoding: "buffer",
        };
        try {
            return {outcome: NodeChildProcess.spawnSync(command, argv, options), raised: null};
        } catch (problem:haxe.Exception) {
            // A host that raises with no returned outcome leaves the caller
            // with no child to describe; the converted error says why.
            return {outcome: null, raised: ChildEvidence.hostErrorOf(problem)};
        }
    }

    /** Writes one retained stream and answers with the path, or null when nothing was retained. */
    function writeStream(directory:String, fileName:String, data:Null<NodeBuffer>, name:String, report:String->Void):Null<String> {
        if (data == null) {
            return null;
        }
        final path = directory + "/" + fileName;
        try {
            NodeFile.writeFileSync(path, data);
            return path;
        } catch (problem:haxe.Exception) {
            report('$name stream write to $path failed: $problem');
            return null;
        }
    }

    function outcomeName(outcome:ChildOutcome):String {
        return switch (outcome) {
            case OutcomeNormalExit(_): "normal-exit";
            case OutcomeSignaled(_): "signaled";
            case OutcomeLaunchFailed(_): "launch-failed";
            case OutcomeInterrupted(_): "interrupted";
        };
    }

    static function joinCapture(current:Null<String>, added:String):String {
        return current == null ? added : current + "; " + added;
    }

    static function errorCode(error:Null<HostErrorReport>):String {
        return error == null ? "" : error.code;
    }

    static function describeError(error:Null<HostErrorReport>):Null<String> {
        if (error == null) {
            return null;
        }
        final name = error.code;
        final text = error.message.length == 0 ? "no message from the host" : error.message;
        return name.length == 0 ? text : name + ": " + text;
    }

    static function normalizeStatus(value:Null<Int>):Null<Int> {
        return value == null ? null : (value : Int);
    }

    static function normalizeText(value:Null<String>):Null<String> {
        return value == null ? null : (value : String);
    }

    /** The content identity of one file, read as bytes. */
    static function contentIdentity(path:String):String {
        try {
            return NodeHash.createHash("sha256").update(NodeFile.readFileSync(path)).digest("hex");
        } catch (problem:haxe.Exception) {
            throw new ChildEvidenceError('cannot read the project file $path for its content identity', Std.string(problem));
        }
    }

    static function processIdentity():String {
        return Syntax.code("String(process.pid)");
    }
}

/**
    Entry points the driver uses. `begin` reads the evidence setting once per
    invocation and allocates the run with the documented capture limit;
    `execute` captures one child when the setting is present. A caller that
    needs a different limit calls `ChildRun.open` with it directly.
**/
class ChildEvidence {
    static var run:Null<ChildRun>;
    public static var parentSetting(default, null):String = "BORING_CHILD_EVIDENCE_DIR";
    public static var defaultMaxBufferBytes(default, null):Int = 1024 * 1024 * 64;

    /**
        The single conversion of one caught host value into the module's error
        form. The caught exception's own message is trusted first, because
        every host throw carries one. The optional native metadata is read only
        after a runtime check establishes that the thrown value is an object,
        and each exported field is accepted only when the runtime states it is
        text, so a thrown primitive keeps a truthful message and never claims
        a system code. This is the only place those host fields are read.
    **/
    public static function hostErrorOf(caught:haxe.Exception):HostErrorReport {
        return errorReportOf(nativeErrorOf(caught), caught.message);
    }

    /**
        Narrows the value the host threw to a native error object, and reports
        nothing when it is a primitive. `haxe.Exception` is a wildcard catch,
        so `native` holds whatever the host threw. The narrowing is validated
        with the host's own `typeof`, because the platform reports an `Error`
        instance as a function-typed value, and the fields of that object are
        re-established as text by `errorReportOf`, so the annotation there is
        not the evidence.
    **/
    static function nativeErrorOf(caught:haxe.Exception):Null<HostError> {
        final native:Any = caught.native;
        return isHostErrorObject(native) ? (native : HostError) : null;
    }

    /**
        Whether a thrown host value is an object that can carry error
        metadata. This is the runtime shape check that allows the metadata
        read; a thrown primitive answers false and keeps only its message.
    **/
    static function isHostErrorObject(native:Any):Bool {
        return Syntax.code("typeof({0}) === 'object' && {0} !== null", native);
    }

    /**
        Validates one host error's metadata before it enters the module's
        string fields. A field the host did not carry, or carried as a
        non-text value, stays empty and is not exported, and a missing message
        keeps the caller's fallback. No returned error and no raised value
        means there is no launch error, so the caller sees null.
    **/
    public static function errorReportOf(error:Null<HostError>, fallbackMessage:Null<String>):Null<HostErrorReport> {
        if (error == null && fallbackMessage == null) {
            return null;
        }
        var code = "";
        var message = fallbackMessage;
        if (error != null) {
            if (isTextual(error.code)) {
                code = (error.code : String);
            }
            if (isTextual(error.message)) {
                message = (error.message : String);
            }
        }
        if (!isTextual(message)) {
            message = "the host threw a value that carries no message";
        }
        return {code: code, message: message};
    }

    /** True when the value is present, is host text, and is not empty. */
    public static function isTextual(value:Null<String>):Bool {
        return value != null && Std.isOfType(value, String) && value.length > 0;
    }

    /** True when this invocation captures child evidence. */
    public static function enabled():Bool {
        return run != null;
    }

    /** The run directory holding this invocation's evidence, or null when capture is off. */
    public static function directory():Null<String> {
        return run == null ? null : run.directory;
    }

    /** Reads the evidence setting and allocates the run when it names a directory. */
    public static function begin(projectPath:String):Void {
        final parent = setting(parentSetting);
        if (parent == null || parent.length == 0) {
            return;
        }
        run = ChildRun.open(parent, projectPath, defaultMaxBufferBytes);
    }

    /** Adopts a run the caller allocated, for a caller that chooses its own limit. */
    public static function adopt(allocated:ChildRun):Void {
        run = allocated;
    }

    /**
        Captures one child. The spawn, the stream writes, and the record write
        all happen before the call returns, so the driver's later failure exit
        cannot lose a captured outcome.
    **/
    public static function execute(context:ChildContext, command:String, argv:Array<String>, cwd:String, environment:ChildEnvironment):ChildExecution {
        final current = run;
        if (current == null) {
            throw new ChildEvidenceError("child evidence was not enabled for this invocation", "execute is called only after begin adopted a run");
        }
        return current.capture(context, command, argv, cwd, environment);
    }

    static function setting(name:String):Null<String> {
        final value:String = Syntax.code("process.env[{0}] || null", name);
        return value;
    }

    public static function nowMs():Float {
        return Syntax.code("Date.now()");
    }
}
