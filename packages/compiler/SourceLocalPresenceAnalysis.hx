#if (macro || reflaxe_runtime)
import haxe.macro.Type;
import ExpressionPredicates;
import SourceEnvironment;
import SourcePresenceWalk;

/**
    Source-local presence facts of one prepared function body.

    `prepare` is the one producer of these facts. Its input is one prepared
    body tree, the body's parameters, and the captured-write summary the
    caller owns for the enclosing tree. The result answers `useFacts` for one
    evaluated read of a local binding and `valueTransferAt` for the internal
    transfer of any node the walk visited. Queries are pure and repeatable.
    The analysis renders nothing, reads no target state, and rewrites no
    tree.

    One transfer rules every context. `eval` evaluates a value, a statement's
    expression, and a condition's operands, and returns the environment after
    evaluation, the presence of the value, the abrupt destinations the
    expression can reach, and the two Boolean exits of a value that decides a
    branch. Statements and conditions consume that transfer; neither carries
    an evaluation rule of its own. A local write is part of the transfer of
    the expression that performs it, so a write used as an argument, an
    initializer, or a condition operand reaches every consumer of that
    expression.

    Presence comes from a justified source producer, an evaluated null
    comparison, or a transferred fact. A written type never establishes
    presence by itself: a call result and a parameter of non-null written
    type stay `Unknown` in this batch, because no source rule here gives them
    a guarantee. A local read transfers the fact its environment holds,
    including `Absent`, and never overrides it from the binding's annotation.

    Identity is the typed variable identity of a binding plus the traversal
    index of its read. Source positions carry diagnostics only. A field read,
    a call result, an indexed read, `this`, and every other projection are
    outside the local domain and answer `NonLocalUse` with no local fact.

    Abrupt control leaves an expression as explicit destination-bearing
    edges, so a return, a break, a continue, and a throw keep their own
    destinations. Sequencing keeps every operand's edges and stops the normal
    path after an operand delivered none, so a later operand never appears
    normally evaluated on that path.

    Loop analysis is a finite conservative pass. The write set of the test,
    the body, and the increment, joined with the complete captured-write
    summary, is removed from the entry before the test is evaluated. The body
    is walked once, the repeated entry is the join of its fall-through and
    continue edges, and the test is applied once more to that joined input
    under a policy that records nothing, so the abstract revisit cannot mark
    a physical node ambiguous. The pre-removal covers every binding a
    repeated entry could change, so no exit fact depends on an iteration the
    walk did not take.

    Captures enter `Unknown` unless a complete enclosing immutability proof
    is available. The analysis owns that proof only for a binding this body
    declares and never writes anywhere in its tree, which no enclosing scope
    can name. Every other capture enters `Unknown`, and the result names that
    precision limit.
**/
class SourceLocalPresenceAnalysis {
    /** Produces the presence facts of one prepared body. */
    public static function prepare(input:SourceFunctionInput):SourceLocalPresenceFacts {
        return new SourcePresenceWalk(input).run();
    }
}

/** The prepared body and the facts the caller owns for its enclosing tree. */
typedef SourceFunctionInput = {
    /** The prepared body tree. Preparation performed every rewrite that
        produced it; the analysis walks it and rewrites nothing. */
    final body:TypedExpr;

    /** The body's parameters in declaration order. A supplied binding this
        body never reads is a `ParameterSetMismatch` diagnostic. */
    final parameters:Array<SourceParameterInput>;

    /** Bindings that sibling or escaped closures of the complete enclosing
        tree may assign. A conservative superset is permitted and is named
        by `outerSummaryKind`. */
    final outerCapturedWrites:Array<Int>;

    /** How `outerCapturedWrites` was established. */
    final outerSummaryKind:SourceCaptureSummaryKind;

    /** Validated immutability facts for bindings declared outside this
        body. Each one must carry `NoEnclosingAssignment` and the presence it
        holds at every invocation. */
    final outerCaptureFacts:Array<SourceCaptureFact>;
}

typedef SourceParameterInput = {
    /** Typed variable identity of the parameter. */
    final binding:Int;

    /** Written type as declared. It never establishes presence. */
    final written:Null<Type>;
}

typedef SourceCaptureFact = {
    final binding:Int;

    final presence:SourcePresence;

    final proof:SourceCaptureImmutability;
}

enum SourceCaptureImmutability {
    /** The complete enclosing tree assigns the binding nowhere. The caller
        owns that proof; the analysis does not restate it. */
    NoEnclosingAssignment;
}

enum SourceCaptureSummaryKind {
    /** No enclosing closure assigns any binding. */
    EnclosingAssignsNothing;

    /** The listed bindings are the complete set of enclosing writes. */
    EnclosingComplete;

    /** The listed bindings are a superset of the enclosing writes. */
    EnclosingSuperset;
}

enum SourcePrecisionLimit {
    /** A capture declared outside this body entered `Unknown` because the
        caller supplied no validated immutability fact for it. */
    CaptureEntryUnknown;
}

/** Presence facts of one prepared body. */
class SourceLocalPresenceFacts {
    /** The body these facts describe. */
    public final body:TypedExpr;

    /** Number of recorded occurrences and loop sites. */
    public final occurrenceCount:Int;

    /** The body's reachable exits. */
    public final exits:Array<SourceBodyExit>;

    /** Diagnostics for unsupported forms and precision limits. */
    public final diagnostics:Array<SourceAnalysisDiagnostic>;

    /** The complete captured-write summary: the bindings this body's own
        nested bodies assign, joined with the enclosing summary. */
    public final capturedWrites:Array<Int>;

    /** How the summary was established. */
    public final summaryKind:SourceCaptureSummaryKind;

    /** Bindings the body reads and does not declare: its parameters and its
        outer captures. */
    public final freeBindings:Array<Int>;

    /** Bindings a nested body of this body reads. */
    public final nestedReads:Array<Int>;

    final records:Map<TypedExpr, SourceRecord>;
    final ambiguousNodes:Map<TypedExpr, Bool>;
    final nullTestMembership:Map<TypedExpr, Bool>;
    final nestedBodies:Map<TypedExpr, SourceLocalPresenceFacts>;

    public function new(body:TypedExpr, occurrenceCount:Int, exits:Array<SourceBodyExit>,
            diagnostics:Array<SourceAnalysisDiagnostic>, capturedWrites:Array<Int>,
            summaryKind:SourceCaptureSummaryKind, freeBindings:Array<Int>, nestedReads:Array<Int>,
            records:Map<TypedExpr, SourceRecord>, ambiguousNodes:Map<TypedExpr, Bool>,
            nullTestMembership:Map<TypedExpr, Bool>, nestedBodies:Map<TypedExpr, SourceLocalPresenceFacts>) {
        this.body = body;
        this.occurrenceCount = occurrenceCount;
        this.exits = exits;
        this.diagnostics = diagnostics;
        this.capturedWrites = capturedWrites;
        this.summaryKind = summaryKind;
        this.freeBindings = freeBindings;
        this.nestedReads = nestedReads;
        this.records = records;
        this.ambiguousNodes = ambiguousNodes;
        this.nullTestMembership = nullTestMembership;
        this.nestedBodies = nestedBodies;
    }

    /**
        Facts of one evaluated use. A local read transfers the fact its
        environment held at that occurrence. A field read, a call result, an
        indexed read, `this`, and every other projection answer `NonLocalUse`
        and carry no local fact.
    **/
    public function useFacts(use:TypedExpr):SourceUseFacts {
        final subject = ExpressionPredicates.stripWrap(use);
        final record = records.get(subject);
        if (record == null) {
            return {
                subject: subjectKind(subject),
                availability: SourceFactAvailability.NoOccurrence,
                knowledge: SourceKnowledge.Conservative,
                presence: SourcePresence.Unknown,
                occurrence: null
            };
        }
        return {
            subject: subjectKind(subject),
            availability: record.availability,
            knowledge: record.knowledge,
            presence: record.presence,
            occurrence: record.occurrence
        };
    }

    /**
        The internal transfer of one node the walk visited, including a
        construction, a literal, a conditional, and a call. Returns null for
        a node the walk did not transfer. This is not a public presence
        query: `useFacts` stays the local-read query.
    **/
    public function valueTransferAt(node:TypedExpr):Null<SourceValueTransfer> {
        final record = records.get(ExpressionPredicates.stripWrap(node));
        return record == null ? null : record.transfer;
    }

    /**
        Whether the body holds a syntactic null test on the binding this
        declaration declares. This is membership for declaration storage
        selection. It is not a presence proof and never feeds one.
    **/
    public function nullTestedAt(declaration:TypedExpr):Bool {
        final value = nullTestMembership.get(ExpressionPredicates.stripWrap(declaration));
        return value == null ? false : value;
    }

    /** The nested body facts of one function literal in this body. */
    public function nestedAt(literal:TypedExpr):Null<SourceLocalPresenceFacts> {
        return nestedBodies.get(ExpressionPredicates.stripWrap(literal));
    }

    function subjectKind(node:TypedExpr):SourceUseSubject {
        return switch (node.expr) {
            case TLocal(v): SourceUseSubject.LocalUse(v.id);
            case _: SourceUseSubject.NonLocalUse;
        }
    }
}

/** Facts of one evaluated use. */
typedef SourceUseFacts = {
    /** What the use reads. */
    final subject:SourceUseSubject;

    final availability:SourceFactAvailability;

    final knowledge:SourceKnowledge;

    final presence:SourcePresence;

    /** The source occurrence of this use, or null when unavailable. */
    final occurrence:Null<SourceOccurrence>;
}

enum SourceUseSubject {
    /** The use reads one local binding of this body. */
    LocalUse(binding:Int);

    /** The use reads a projection outside the local domain. */
    NonLocalUse;
}

enum SourceFactAvailability {
    /** The walk transferred this occurrence through its own rules. */
    Available;

    /** The path to this occurrence carries no reachable normal value. */
    UnreachablePath;

    /** The node has no occurrence in this prepared body: a node built after
        preparation, a node of another body, a query made outside a prepared
        context, or one physical node reached on several paths. */
    NoOccurrence;

    /** The walk stopped at an unsupported form before this node. The
        effects and exits of the skipped region are accounted as possible. */
    NotReached(form:String);
}

enum SourceKnowledge {
    /** The node form's own rule produced the answer. */
    Transferred;

    /** A fallback supplied the answer, so no source rule states it. */
    Conservative;
}

enum SourcePresence {
    Present(reason:SourcePresenceReason);

    Absent(reason:SourcePresenceReason);

    Unknown;
}

enum SourcePresenceReason {
    ProducerRule(producer:SourceProducer);

    /** A null comparison held its non-null outcome on every path here. */
    GuardPresentOutcome(testedOperator:SourceGuardOperator);

    /** A null comparison held its null outcome on every path here. */
    GuardAbsentOutcome(testedOperator:SourceGuardOperator);

    /** Every reachable path assigned the null literal. */
    NullAssignment;

    /** The occurrence is the null literal. */
    NullLiteral;

    /** Present paths whose individual explanations do not both hold. */
    JoinedPresent;

    /** Absent paths whose individual explanations do not both hold. */
    JoinedAbsent;

    NoReason;
}

/**
    The source producer rules this batch recognizes. Each names the construct
    that establishes presence. A written type selects which rule applies
    at a node form and never establishes presence by itself.
**/
enum SourceProducer {
    /** A literal of a scalar written type. */
    ScalarConstant;

    /** An arithmetic, comparison, or logical operation whose result the
        operation cannot make absent. */
    ScalarOperation;

    /** A string concatenation. */
    StringConcatenation;

    /** An array or collection construction. */
    CollectionConstruction;

    /** An object or closure construction. */
    ObjectConstruction;
}

enum SourceGuardOperator {
    /** `subject != null` was the tested comparison. */
    NotEqualToNull;

    /** `subject == null` was the tested comparison. */
    EqualToNull;
}

typedef SourceOccurrence = {
    /** Traversal index of this occurrence. */
    final id:Int;

    /** Typed variable identity of the read binding. */
    final binding:Int;
}

enum SourceBodyExit {
    NormalExit(reachable:Bool, facts:Map<Int, SourcePresence>);

    ReturnExit(reachable:Bool, facts:Map<Int, SourcePresence>);

    ThrowExit(reachable:Bool, facts:Map<Int, SourcePresence>);
}

enum SourceAnalysisDiagnostic {
    /** The walk met a form it does not transfer. Its subtree is marked not
        reached and its effects are accounted as possible. */
    UnsupportedForm(form:String, position:haxe.macro.Expr.Position);

    /** The caller supplied a parameter binding this body never reads. */
    ParameterSetMismatch(binding:Int);

    /** One physical node was reached on several paths. Its record is
        dropped and every query about it answers `NoOccurrence`. */
    AmbiguousNode;

    /** A control edge reached no destination this analysis models. */
    UnconsumedEdge(edge:String);

    /** A stated precision limit applies to this body. */
    PrecisionLimit(limit:SourcePrecisionLimit);
}

/**
    One evaluation transfer. `environment` is null when the expression
    delivered no normal continuation, so no consumer can manufacture a
    reachable value from it. `exits` carries every abrupt destination,
    including the operands' edges. `branches` carries the two Boolean exits
    of a value that decides a branch; `condition` consumes it and falls back
    to the normal environment when the value decides nothing.
**/
typedef SourceValueTransfer = {
    final environment:Null<SourceEnvironment>;

    final result:SourcePresence;

    final normal:Bool;

    final exits:Array<SourceEdge>;

    final branches:Null<SourceBranches>;
}

typedef SourceBranches = {
    final t:Null<SourceEnvironment>;

    final f:Null<SourceEnvironment>;
}

/** Whether this evaluation records its occurrences. */
typedef SourceEvalPolicy = {
    /** True for the one real walk over the body, false for an abstract
        revisit of an already transferred node. */
    final record:Bool;
}

/**
    One abrupt destination. `site` is the traversal index of the loop
    occurrence, never a source position. A `break` and a `continue` of a
    nested function literal belong to that literal and never reach an
    enclosing loop. A `continue` reaches the loop's own continuation point:
    the test of a pre-tested loop, and the test of a post-tested loop, whose
    true edge returns to the body.
**/
enum SourceEdge {
    ContinueOf(site:Int, environment:SourceEnvironment);

    BreakOf(site:Int, environment:SourceEnvironment);

    ReturnOfBody(environment:SourceEnvironment);

    ThrowOfBody(environment:SourceEnvironment);
}

typedef SourceStep = {
    final normal:Null<SourceEnvironment>;

    final exits:Array<SourceEdge>;
}

typedef SourceRecord = {
    final occurrence:Null<SourceOccurrence>;

    final presence:SourcePresence;

    final knowledge:SourceKnowledge;

    final availability:SourceFactAvailability;

    final transfer:Null<SourceValueTransfer>;
}

typedef SourceLoopFrame = {
    final site:Int;

    final breaks:Array<SourceEnvironment>;

    final continues:Array<SourceEnvironment>;
}

#end
