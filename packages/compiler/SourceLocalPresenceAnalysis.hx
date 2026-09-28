#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Expr.Binop;
import haxe.macro.Expr.Unop;
import haxe.macro.Expr.Constant;
import haxe.macro.Type.TConstant;
import haxe.macro.Type;
import haxe.macro.Type.FieldAccess;
import haxe.macro.Type.FieldKind;
import haxe.macro.TypedExprTools;
import ExpressionPredicates;
import SourceContainerAnalysis;

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
    ProducerContract(producer:SourceProducer);

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
    The source producer contracts this batch recognizes. Each names the rule
    that establishes presence. A written type selects which contract applies
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

/** One immutable environment of local facts. */
class SourceEnvironment {
    final facts:Map<Int, SourcePresence>;

    function new(facts:Map<Int, SourcePresence>) {
        this.facts = facts;
    }

    public static function empty():SourceEnvironment {
        return new SourceEnvironment(new Map<Int, SourcePresence>());
    }

    public function fact(binding:Int):SourcePresence {
        final found = facts.get(binding);
        return found == null ? SourcePresence.Unknown : found;
    }

    public function with(binding:Int, presence:SourcePresence):SourceEnvironment {
        final next = copy();
        next.set(binding, presence);
        return new SourceEnvironment(next);
    }

    /** Sets every listed binding to `Unknown`: the loop pre-removal. */
    public function clearFacts(bindings:Array<Int>):SourceEnvironment {
        final next = copy();
        for (binding in bindings)
            next.set(binding, SourcePresence.Unknown);
        return new SourceEnvironment(next);
    }

    /** Removes the bindings a leaving block declared. */
    public function dropScope(bindings:Array<Int>):SourceEnvironment {
        if (bindings.length == 0)
            return this;
        final next = new Map<Int, SourcePresence>();
        for (key in facts.keys()) {
            var keep = true;
            for (binding in bindings)
                if (binding == key)
                    keep = false;
            if (keep)
                next.set(key, facts.get(key));
        }
        return new SourceEnvironment(next);
    }

    public function snapshot():Map<Int, SourcePresence> {
        return copy();
    }

    function copy():Map<Int, SourcePresence> {
        final next = new Map<Int, SourcePresence>();
        for (key in facts.keys())
            next.set(key, facts.get(key));
        return next;
    }

    /**
        Joins the environments of reachable paths only. Presence joins
        independently from its explanation, and a fact one path carries and
        the other does not joins to `Unknown`.
    **/
    public static function join(a:Null<SourceEnvironment>, b:Null<SourceEnvironment>):Null<SourceEnvironment> {
        if (a == null)
            return b;
        if (b == null)
            return a;
        final out = new Map<Int, SourcePresence>();
        for (key in a.facts.keys())
            out.set(key, SourcePresence.Unknown);
        for (key in b.facts.keys())
            out.set(key, SourcePresence.Unknown);
        for (key in out.keys()) {
            final left = a.facts.get(key);
            final right = b.facts.get(key);
            out.set(key, left == null || right == null ? SourcePresence.Unknown : joinPresence(left, right));
        }
        return new SourceEnvironment(out);
    }

    public static function joinAll(list:Array<SourceEnvironment>):Null<SourceEnvironment> {
        var out:Null<SourceEnvironment> = null;
        for (entry in list)
            out = join(out, entry);
        return out;
    }

    public static function joinPresence(a:SourcePresence, b:SourcePresence):SourcePresence {
        return switch [a, b] {
            case [Present(x), Present(y)]:
                sameReason(x, y) ? Present(x) : SourcePresence.Present(SourcePresenceReason.JoinedPresent);
            case [Absent(x), Absent(y)]:
                sameReason(x, y) ? Absent(x) : SourcePresence.Absent(SourcePresenceReason.JoinedAbsent);
            case _: SourcePresence.Unknown;
        }
    }

    public static function samePresence(left:SourcePresence, right:SourcePresence):Bool {
        return switch [left, right] {
            case [Unknown, Unknown]: true;
            case [Present(l), Present(r)] | [Absent(l), Absent(r)]: sameReason(l, r);
            case _: false;
        }
    }

    static function sameReason(left:SourcePresenceReason, right:SourcePresenceReason):Bool {
        return switch [left, right] {
            case [ProducerContract(l), ProducerContract(r)]: l == r;
            case [GuardPresentOutcome(l), GuardPresentOutcome(r)]
                | [GuardAbsentOutcome(l), GuardAbsentOutcome(r)]: l == r;
            case [NullAssignment, NullAssignment]
                | [NullLiteral, NullLiteral]
                | [JoinedPresent, JoinedPresent]
                | [JoinedAbsent, JoinedAbsent]
                | [NoReason, NoReason]: true;
            case _: false;
        }
    }
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

/** The one evaluation transfer over one prepared body. */
class SourcePresenceWalk {
    final input:SourceFunctionInput;

    final diagnostics:Array<SourceAnalysisDiagnostic> = [];
    final records:Map<TypedExpr, SourceRecord> = new Map<TypedExpr, SourceRecord>();
    final ambiguousNodes:Map<TypedExpr, Bool> = new Map<TypedExpr, Bool>();
    final nestedBodies:Map<TypedExpr, SourceLocalPresenceFacts> = new Map<TypedExpr, SourceLocalPresenceFacts>();
    final nullTestMembership:Map<TypedExpr, Bool> = new Map<TypedExpr, Bool>();

    /** Bindings declared by a `TVar` of this body, its nested bodies aside. */
    final declared:Array<Int> = [];

    /** Bindings this body reads and does not declare. */
    final free:Array<Int> = [];

    /** Bindings a nested body of this body reads. */
    final nestedReads:Array<Int> = [];

    /** Bindings any nested body of this body assigns. */
    final inBodyCapturedWrites:Array<Int> = [];

    /** Every binding an assignment anywhere in this tree may write. */
    var bodyWrites:Array<Int> = [];

    /** The complete captured-write summary. */
    var captures:Array<Int> = [];

    /** The parameter identities this body declares. */
    var parameterBindings:Array<Int> = [];

    var counter:Int = 0;
    var loops:Array<SourceLoopFrame> = [];

    public function new(input:SourceFunctionInput) {
        this.input = input;
    }

    public function run():SourceLocalPresenceFacts {
        indexBindings(input.body);
        for (parameter in input.parameters) {
            pushUnique(parameterBindings, parameter.binding);
            if (indexOf(declared, parameter.binding) < 0 && indexOf(free, parameter.binding) < 0)
                diagnostics.push(SourceAnalysisDiagnostic.ParameterSetMismatch(parameter.binding));
        }
        computeInBodyCaptures(input.body);
        bodyWrites = collectWrites(input.body);
        captures = unique(inBodyCapturedWrites.concat(input.outerCapturedWrites));
        computeNullTests(input.body);
        final entry = installCaptureFacts(SourceEnvironment.empty());
        final step = block(entry, statementsOf(input.body), {record: true});
        final exits:Array<SourceBodyExit> = [];
        exits.push(SourceBodyExit.NormalExit(step.normal != null,
            step.normal == null ? new Map<Int, SourcePresence>() : step.normal.snapshot()));
        pushExits(exits, step.exits);
        reportCaptureLimits();
        return new SourceLocalPresenceFacts(input.body, counter, exits, diagnostics, captures, summaryKind(), free, nestedReads,
            records, ambiguousNodes, nullTestMembership, nestedBodies);
    }

    /** Installs the caller's validated capture facts into the entry. */
    function installCaptureFacts(entry:SourceEnvironment):SourceEnvironment {
        var out = entry;
        for (fact in input.outerCaptureFacts) {
            if (indexOf(declared, fact.binding) >= 0)
                continue;
            out = out.with(fact.binding, fact.presence);
        }
        return out;
    }

    function summaryKind():SourceCaptureSummaryKind {
        return switch (input.outerSummaryKind) {
            case EnclosingAssignsNothing: inBodyCapturedWrites.length == 0 ? EnclosingAssignsNothing : EnclosingComplete;
            case other: other;
        }
    }

    /** States every outer capture that entered `Unknown` for want of a fact. */
    function reportCaptureLimits():Void {
        final supplied:Array<Int> = [for (fact in input.outerCaptureFacts) fact.binding];
        for (binding in nestedReads) {
            if (indexOf(declared, binding) >= 0 || indexOf(supplied, binding) >= 0)
                continue;
            diagnostics.push(SourceAnalysisDiagnostic.PrecisionLimit(SourcePrecisionLimit.CaptureEntryUnknown));
            return;
        }
    }

    // ------------------------------------------------------------------
    // Binding index and capture summary
    // ------------------------------------------------------------------

    /**
        Indexes this body's own declarations, reads, and nested reads. A
        function literal's declarations belong to that literal, so the walk
        stops at one and its own walk indexes them again.
    **/
    function indexBindings(root:TypedExpr):Void {
        function walk(e:TypedExpr, nested:Bool):Void {
            switch (e.expr) {
                case TVar(v, _):
                    if (!nested)
                        pushUnique(declared, v.id);
                case TLocal(v):
                    if (!nested) {
                        if (indexOf(declared, v.id) < 0)
                            pushUnique(free, v.id);
                    } else if (indexOf(declared, v.id) >= 0 || indexOf(free, v.id) >= 0) {
                        pushUnique(nestedReads, v.id);
                    }
                case TFunction(fn):
                    walk(fn.expr, true);
                case _:
            }
            TypedExprTools.iter(e, function(child:TypedExpr):Void {
                walk(child, nested);
            });
        }
        walk(root, false);
    }

    /**
        Bindings that a nested body of this body assigns. A literal's writes
        to bindings declared outside it belong to the summary; evaluating
        the literal executes none of them.
    **/
    function computeInBodyCaptures(root:TypedExpr):Void {
        function walk(e:TypedExpr):Void {
            switch (e.expr) {
                case TFunction(fn):
                    for (binding in collectWrites(fn.expr))
                        pushUnique(inBodyCapturedWrites, binding);
                case _:
            }
            TypedExprTools.iter(e, walk);
        }
        walk(root);
    }

    /** Every binding an assignment inside this tree may write. */
    function collectWrites(root:TypedExpr):Array<Int> {
        final out:Array<Int> = [];
        function walk(e:TypedExpr):Void {
            switch (e.expr) {
                case TBinop(OpAssign, target, _) | TBinop(OpAssignOp(_), target, _):
                    switch (ExpressionPredicates.stripWrap(target).expr) {
                        case TLocal(v): pushUnique(out, v.id);
                        case _:
                    }
                case TUnop(OpIncrement, _, t) | TUnop(OpDecrement, _, t):
                    switch (ExpressionPredicates.stripWrap(t).expr) {
                        case TLocal(v): pushUnique(out, v.id);
                        case _:
                    }
                case _:
            }
            TypedExprTools.iter(e, walk);
        }
        walk(root);
        return out;
    }

    // ------------------------------------------------------------------
    // Syntactic null-test membership
    // ------------------------------------------------------------------

    /**
        The collection rule the declaration storage decision uses: a binding
        is a member when the innermost block containing its declaration, or
        any block enclosing it, holds a null comparison whose subject is that
        binding. The scan visits every node of a block's statements,
        including nested functions.
    **/
    function computeNullTests(root:TypedExpr):Void {
        final tested:Array<Int> = [];
        function walk(e:TypedExpr):Void {
            switch (e.expr) {
                case TBlock(stmts):
                    final localTests = nullTestedIds(stmts);
                    for (binding in localTests)
                        pushUnique(tested, binding);
                    for (stmt in stmts)
                        walk(stmt);
                    for (binding in localTests)
                        removeOne(tested, binding);
                case TVar(v, _):
                    nullTestMembership.set(e, indexOf(tested, v.id) >= 0);
                case _:
                    TypedExprTools.iter(e, walk);
            }
        }
        walk(root);
    }

    function nullTestedIds(stmts:Array<TypedExpr>):Array<Int> {
        final out:Array<Int> = [];
        for (stmt in stmts)
            TypedExprTools.iter(stmt, function(node:TypedExpr):Void {
                switch (ExpressionPredicates.stripWrap(node).expr) {
                    case TBinop(OpEq, l, r) | TBinop(OpNotEq, l, r):
                        final subject = ExpressionPredicates.isNullExpr(l) ? r : (ExpressionPredicates.isNullExpr(r) ? l : null);
                        if (subject != null)
                            switch (ExpressionPredicates.stripWrap(subject).expr) {
                                case TLocal(v): pushUnique(out, v.id);
                                case _:
                            }
                    case _:
                }
            });
        return out;
    }

    // ------------------------------------------------------------------
    // Statements consume the one transfer
    // ------------------------------------------------------------------

    function statementsOf(e:TypedExpr):Array<TypedExpr> {
        return switch (ExpressionPredicates.stripWrap(e).expr) {
            case TBlock(stmts): stmts;
            case _: [e];
        }
    }

    function block(env:Null<SourceEnvironment>, stmts:Array<TypedExpr>, policy:SourceEvalPolicy):SourceStep {
        var current = env;
        final exits:Array<SourceEdge> = [];
        final declaredHere:Array<Int> = [];
        for (stmt in stmts) {
            if (current == null) {
                markUnreachable(stmt);
                continue;
            }
            final step = statement(current, stmt, policy);
            current = step.normal;
            for (edge in step.exits)
                switch (edge) {
                    case ContinueOf(site, environment) | BreakOf(site, environment):
                        if (loops.length > 0 && loops[loops.length - 1].site == site)
                            consume(edge, environment);
                        else
                            exits.push(edge);
                    case _:
                        exits.push(edge);
                }
            switch (ExpressionPredicates.stripWrap(stmt).expr) {
                case TVar(v, _): pushUnique(declaredHere, v.id);
                case _:
            }
        }
        return {normal: current == null ? null : current.dropScope(declaredHere), exits: exits};
    }

    function consume(edge:SourceEdge, environment:SourceEnvironment):Void {
        final frame = loops[loops.length - 1];
        switch (edge) {
            case ContinueOf(_, _): frame.continues.push(environment);
            case BreakOf(_, _): frame.breaks.push(environment);
            case _:
        }
    }

    function statement(env:SourceEnvironment, e:TypedExpr, policy:SourceEvalPolicy):SourceStep {
        final inner = ExpressionPredicates.stripWrap(e);
        switch (inner.expr) {
            case TVar(v, init):
                if (init == null)
                    return {normal: env.with(v.id, SourcePresence.Unknown), exits: []};
                final transferred = eval(env, init, policy);
                return {
                    normal: transferred.environment == null ? null : transferred.environment.with(v.id, transferred.result),
                    exits: transferred.exits
                };
            case TIf(c, t, f):
                return branch(env, c, t, f, policy);
            case TWhile(c, b, flag):
                return flag ? preTestedLoop(env, c, b, policy) : postTestedLoop(env, c, b, policy);
            case TTry(body, catches):
                return tryRegion(env, body, catches, policy);
            case TBlock(stmts):
                return block(env, stmts, policy);
            case _:
                final transferred = eval(env, inner, policy);
                return {normal: transferred.environment, exits: transferred.exits};
        }
    }

    function branch(env:SourceEnvironment, c:TypedExpr, t:TypedExpr, f:Null<TypedExpr>, policy:SourceEvalPolicy):SourceStep {
        final condition = eval(env, c, policy);
        final exits = condition.exits.slice(0, condition.exits.length);
        final arms:SourceBranches = condition.branches == null
            ? branchesOf(condition.environment, condition.environment)
            : condition.branches;
        final thenStep = arms.t == null ? unreachableStep(t) : block(arms.t, statementsOf(t), policy);
        final elseStep:SourceStep = f == null
            ? {normal: arms.f, exits: []}
            : (arms.f == null ? unreachableStep(f) : block(arms.f, statementsOf(f), policy));
        for (edge in thenStep.exits)
            exits.push(edge);
        for (edge in elseStep.exits)
            exits.push(edge);
        return {normal: SourceEnvironment.join(thenStep.normal, elseStep.normal), exits: exits};
    }

    /**
        A protected region whose writes the handler cannot assume. The
        handler entry removes every binding the region might write together
        with the captures an unknown effect there may assign. Break and
        continue edges of the region keep their loop destinations.
    **/
    function tryRegion(env:SourceEnvironment, body:TypedExpr, catches:Array<{v:TVar, expr:TypedExpr}>, policy:SourceEvalPolicy):SourceStep {
        if (catches.length != 1)
            return unsupportedStep(env, ExpressionPredicates.stripWrap(body), "try region with more than one catch", policy);
        final bodyStep = block(env, statementsOf(body), policy);
        final handlerStep = handler(bodyStep.exits, env, body, catches, policy);
        final exits:Array<SourceEdge> = [];
        for (edge in bodyStep.exits)
            exits.push(edge);
        for (edge in handlerStep.exits)
            exits.push(edge);
        return {normal: SourceEnvironment.join(bodyStep.normal, handlerStep.normal), exits: exits};
    }

    /**
        The catch arm of one protected body. It runs only when the body
        carries a throw edge, so a body that only returns or breaks leaves its
        catch unreachable and adds no normal path after the region. The entry
        removes every binding the body might write together with the captures
        an unknown effect there may assign.

        The body's throw edges are kept unchanged. Whether a thrown value
        matches the caught type has no source rule in this batch, and the edge
        carries no thrown type, so an unknown call's escape stays possible and
        a definitely matching explicit throw is still reported as a reachable
        throw exit. That precision limit is stated here, not resolved.
    **/
    function handler(bodyThrows:Array<SourceEdge>, env:SourceEnvironment, body:TypedExpr,
            catches:Array<{v:TVar, expr:TypedExpr}>, policy:SourceEvalPolicy):SourceStep {
        if (thrownEnvironments(bodyThrows).length == 0) {
            markUnreachable(catches[0].expr);
            return {normal: null, exits: []};
        }
        final entry = env.clearFacts(unique(collectWrites(body).concat(captures)));
        return block(entry, statementsOf(catches[0].expr), policy);
    }

    /** The environments of the throw edges one transfer carries. */
    function thrownEnvironments(edges:Array<SourceEdge>):Array<SourceEnvironment> {
        final out:Array<SourceEnvironment> = [];
        for (edge in edges)
            switch (edge) {
                case ThrowOfBody(environment): out.push(environment);
                case _:
            }
        return out;
    }

    // ------------------------------------------------------------------
    // Loops
    // ------------------------------------------------------------------

    /**
        A pre-tested loop. Step one removes the facts of every binding the
        test, the body, or any unknown effect there may write, joined with
        the complete captured-write summary, so every repeated entry is
        covered. Step two evaluates the test once and takes its false exit as
        the zero-iteration exit. Step three walks the body once from the true
        exit. Step four joins the body's fall-through and continue edges into
        the repeated entry and applies the test once more to that input under
        a policy that records nothing. The exit is the join of the
        condition-false exits and the break environments. The entry
        environment is never restored as the loop result.
    **/
    function preTestedLoop(env:SourceEnvironment, c:TypedExpr, b:TypedExpr, policy:SourceEvalPolicy):SourceStep {
        final entry = env.clearFacts(unique(collectWrites(c).concat(collectWrites(b)).concat(captures)));
        final site = nextSite();
        loops.push({site: site, breaks: [], continues: []});
        final first = eval(entry, c, policy);
        final firstArms:SourceBranches = first.branches == null
            ? branchesOf(first.environment, first.environment)
            : first.branches;
        final bodyStep = firstArms.t == null ? unreachableStep(b) : block(firstArms.t, statementsOf(b), policy);
        final frame = loops.pop();
        final repeated = SourceEnvironment.join(bodyStep.normal, SourceEnvironment.joinAll(frame.continues));
        var exit = firstArms.f;
        final exits = first.exits.slice(0, first.exits.length);
        for (edge in bodyStep.exits)
            exits.push(edge);
        if (repeated != null) {
            final again = eval(repeated, c, {record: false});
            final againArms:SourceBranches = again.branches == null
                ? branchesOf(again.environment, again.environment)
                : again.branches;
            exit = SourceEnvironment.join(exit, againArms.f);
            for (edge in again.exits)
                exits.push(edge);
        }
        exit = SourceEnvironment.join(exit, SourceEnvironment.joinAll(frame.breaks));
        return {normal: exit, exits: exits};
    }

    /**
        A post-tested loop runs its body first, so it has no zero-iteration
        exit. The condition's true exit returns to the body, which the walk
        does not walk again; the false exit leaves the loop.
    **/
    function postTestedLoop(env:SourceEnvironment, c:TypedExpr, b:TypedExpr, policy:SourceEvalPolicy):SourceStep {
        final entry = env.clearFacts(unique(collectWrites(c).concat(collectWrites(b)).concat(captures)));
        final site = nextSite();
        loops.push({site: site, breaks: [], continues: []});
        final bodyStep = block(entry, statementsOf(b), policy);
        final frame = loops.pop();
        final repeated = SourceEnvironment.join(bodyStep.normal, SourceEnvironment.joinAll(frame.continues));
        var exit = SourceEnvironment.joinAll(frame.breaks);
        final exits = bodyStep.exits.slice(0, bodyStep.exits.length);
        if (repeated != null) {
            final again = eval(repeated, c, {record: false});
            final againArms:SourceBranches = again.branches == null
                ? branchesOf(again.environment, again.environment)
                : again.branches;
            exit = SourceEnvironment.join(exit, againArms.f);
            for (edge in again.exits)
                exits.push(edge);
        }
        return {normal: exit, exits: exits};
    }

    // ------------------------------------------------------------------
    // Conditions consume the one transfer
    // ------------------------------------------------------------------

    /** The two Boolean exits of one condition. */
    function condition(env:Null<SourceEnvironment>, e:TypedExpr, policy:SourceEvalPolicy):SourceBranches {
        final transferred = eval(env, e, policy);
        return transferred.branches == null
            ? branchesOf(transferred.environment, transferred.environment)
            : transferred.branches;
    }

    // ------------------------------------------------------------------
    // The one evaluation transfer
    // ------------------------------------------------------------------

    function eval(env:Null<SourceEnvironment>, e:TypedExpr, policy:SourceEvalPolicy):SourceValueTransfer {
        if (env == null) {
            markUnreachable(e);
            return noTransfer([]);
        }
        final inner = ExpressionPredicates.stripWrap(e);
        switch (inner.expr) {
            case TConst(constant):
                // A Boolean literal holds its value, so the opposite exit of
                // a test on it carries no reachable path.
                final branches = switch (constant) {
                    case TBool(literal): branchesOf(literal ? env : null, literal ? null : env);
                    case _: null;
                }
                return done(env, e, presenceOfConstant(constant), policy, [], null, branches);
            case TLocal(v):
                return done(env, e, env.fact(v.id), policy, [], v.id);
            case TBinop(op, l, r):
                return binary(env, e, op, l, r, policy);
            case TUnop(op, _, subject):
                return unary(env, e, op, subject, policy);
            case TArray(receiver, index):
                // An indexed read is a projection, not a construction. Its
                // element can be null, so it states no presence.
                final first = eval(env, receiver, policy);
                if (first.environment == null)
                    return noTransfer(first.exits);
                final second = eval(first.environment, index, policy);
                if (second.environment == null)
                    return noTransfer(append(first.exits, second.exits));
                return done(second.environment, e, SourcePresence.Unknown, policy, append(first.exits, second.exits));
            case TArrayDecl(elements):
                final listed = evalList(env, elements, policy);
                return done(listed.environment, e,
                    SourcePresence.Present(ProducerContract(SourceProducer.CollectionConstruction)), policy, listed.exits);
            case TNew(_, _, args):
                final listed = evalList(env, args, policy);
                if (listed.environment == null)
                    return noTransfer(listed.exits);
                final after = afterCall(listed.environment);
                return done(after, e, SourcePresence.Present(ProducerContract(SourceProducer.ObjectConstruction)), policy,
                    append(listed.exits, [SourceEdge.ThrowOfBody(after)]));
            case TObjectDecl(fields):
                final listed = evalList(env, [for (field in fields) field.expr], policy);
                return done(listed.environment, e,
                    SourcePresence.Present(ProducerContract(SourceProducer.ObjectConstruction)), policy, listed.exits);
            case TCall(fn, args):
                final callee = eval(env, fn, policy);
                if (callee.environment == null)
                    return noTransfer(callee.exits);
                final listed = evalList(callee.environment, args, policy);
                if (listed.environment == null)
                    return noTransfer(append(callee.exits, listed.exits));
                final after = afterCall(listed.environment);
                return done(after, e, SourcePresence.Unknown, policy,
                    append(callee.exits.concat(listed.exits), [SourceEdge.ThrowOfBody(after)]));
            case TField(subject, access):
                // A plain property read transfers its receiver's effects. An
                // accessor property is a call: it may assign captures and may
                // throw, and its effects belong to the read.
                final receiver = eval(env, subject, policy);
                if (receiver.environment == null)
                    return noTransfer(receiver.exits);
                if (!accessorRead(access))
                    return done(receiver.environment, e, SourcePresence.Unknown, policy, receiver.exits);
                final after = afterCall(receiver.environment);
                return done(after, e, SourcePresence.Unknown, policy,
                    append(receiver.exits, [SourceEdge.ThrowOfBody(after)]));
            case TEnumParameter(inside, _, _) | TEnumIndex(inside):
                final receiver = eval(env, inside, policy);
                return done(receiver.environment, e, SourcePresence.Unknown, policy, receiver.exits);
            case TIf(c, t, f):
                return conditional(env, e, c, t, f, policy);
            case TSwitch(subject, cases, def):
                return switchValue(env, e, subject, cases, def, policy);
            case TTry(body, catches):
                return tryValue(env, e, body, catches, policy);
            case TBlock(stmts):
                return blockValue(env, e, stmts, policy);
            case TFunction(fn):
                return functionValue(env, e, fn, policy);
            case TThrow(inside):
                return abrupt(env, inside, policy, environment -> SourceEdge.ThrowOfBody(environment));
            case TReturn(inside):
                return abrupt(env, inside, policy, environment -> SourceEdge.ReturnOfBody(environment));
            case TBreak:
                return loopEdge(env, false);
            case TContinue:
                return loopEdge(env, true);
            case TTypeExpr(_):
                return done(env, e, SourcePresence.Unknown, policy, []);
            case TParenthesis(inside) | TCast(inside, _) | TMeta(_, inside):
                return eval(env, inside, policy);
            case _:
                return unsupported(env, inner, Std.string(inner.expr), policy);
        }
    }

    /**
        One binary operation. An assignment writes its binding inside this
        transfer, so every consumer of the expression sees the write.
        Short-circuit operands follow the contract's true and false exit
        table, and an operand whose controlling exit is unreachable is never
        evaluated.
    **/
    function binary(env:SourceEnvironment, node:TypedExpr, op:Binop, l:TypedExpr, r:TypedExpr,
            policy:SourceEvalPolicy):SourceValueTransfer {
        switch (op) {
            case OpBoolAnd:
                final left = eval(env, l, policy);
                if (!left.normal)
                    return noTransfer(left.exits);
                final arms:SourceBranches = left.branches == null
                    ? branchesOf(left.environment, left.environment)
                    : left.branches;
                if (arms.t == null) {
                    // The left operand can never hold, so the right operand
                    // is never evaluated on any path and the false outcome is
                    // the only reachable one.
                    markUnreachable(r);
                    return done(arms.f, node, operationPresence(op, l, r), policy, left.exits, null, branchesOf(null, arms.f));
                }
                final right = eval(arms.t, r, policy);
                final rightArms:SourceBranches = right.branches == null
                    ? branchesOf(right.environment, right.environment)
                    : right.branches;
                final t = rightArms.t;
                final f = SourceEnvironment.join(arms.f, rightArms.f);
                // The value is produced on both reachable outcomes, so its
                // normal continuation joins them and carries neither alone.
                final normal = SourceEnvironment.join(arms.f, right.environment);
                return done(normal, node, operationPresence(op, l, r), policy, append(left.exits, right.exits), null,
                    branchesOf(t, f));
            case OpBoolOr:
                final left = eval(env, l, policy);
                if (!left.normal)
                    return noTransfer(left.exits);
                final arms:SourceBranches = left.branches == null
                    ? branchesOf(left.environment, left.environment)
                    : left.branches;
                if (arms.f == null) {
                    markUnreachable(r);
                    return done(arms.t, node, operationPresence(op, l, r), policy, left.exits, null, branchesOf(arms.t, null));
                }
                final right = eval(arms.f, r, policy);
                final rightArms:SourceBranches = right.branches == null
                    ? branchesOf(right.environment, right.environment)
                    : right.branches;
                final t = SourceEnvironment.join(arms.t, rightArms.t);
                final f = rightArms.f;
                final normal = SourceEnvironment.join(arms.t, right.environment);
                return done(normal, node, operationPresence(op, l, r), policy, append(left.exits, right.exits), null,
                    branchesOf(t, f));
            case OpAssign:
                final location = eval(env, l, {record: false});
                if (!location.normal)
                    return noTransfer(location.exits);
                final value = eval(location.environment, r, policy);
                if (!value.normal)
                    return noTransfer(append(location.exits, value.exits));
                return assigned(location, value, l, node, value.result, policy);
            case OpAssignOp(inner):
                final location = eval(env, l, {record: false});
                if (!location.normal)
                    return noTransfer(location.exits);
                final value = eval(location.environment, r, policy);
                if (!value.normal)
                    return noTransfer(append(location.exits, value.exits));
                return assigned(location, value, l, node, operationPresence(inner, l, r), policy);
            case _:
                final left = eval(env, l, policy);
                if (!left.normal)
                    return noTransfer(left.exits);
                final right = eval(left.environment, r, policy);
                if (!right.normal)
                    return noTransfer(append(left.exits, right.exits));
                final branches = switch (op) {
                    case OpEq | OpNotEq: nullTestBranches(right.environment, op, l, r);
                    case _: null;
                };
                return done(right.environment, node, operationPresence(op, l, r), policy, append(left.exits, right.exits), null,
                    branches);
        }
    }

    /** Whether reading this member can run source code. */
    function accessorRead(access:FieldAccess):Bool {
        return switch (access) {
            case FInstance(_, _, cf): throughCall(cf.get().kind);
            case FAnon(cf): throughCall(cf.get().kind);
            case FDynamic(_): true;
            case _: false;
        }
    }

    function throughCall(kind:FieldKind):Bool {
        return switch (kind) {
            case FVar(read, write): read == AccCall || write == AccCall;
            case _: false;
        }
    }

    /**
        One assignment rule for the plain and the compound form. The
        destination write lands in the environment the right side left behind,
        so the write cannot restore a fact the right side removed, and the
        operand edges stay in evaluation order.
    **/
    function assigned(location:SourceValueTransfer, value:SourceValueTransfer, locationExpr:TypedExpr, node:TypedExpr,
            result:SourcePresence, policy:SourceEvalPolicy):SourceValueTransfer {
        return done(written(value.environment, locationExpr, result), node, result, policy, append(location.exits, value.exits));
    }

    /** Applies the write one assignment performs to its local binding. */
    function written(env:SourceEnvironment, location:TypedExpr, presence:SourcePresence):SourceEnvironment {
        return switch (ExpressionPredicates.stripWrap(location).expr) {
            case TLocal(v): env.with(v.id, presence);
            case _: env;
        }
    }

    /**
        The two Boolean exits of one null comparison, or null when the
        comparison refines nothing. Refinement requires the null literal as
        one operand and a local read as the other. Any other value also holds
        for null, so it refines nothing.
    **/
    function nullTestBranches(after:SourceEnvironment, op:Binop, l:TypedExpr, r:TypedExpr):Null<SourceBranches> {
        final test = ExpressionPredicates.isNullExpr(l) ? localSubject(r) : (ExpressionPredicates.isNullExpr(r) ? localSubject(l) : null);
        if (test == null)
            return null;
        final testedOperator:SourceGuardOperator = op == OpNotEq ? NotEqualToNull : EqualToNull;
        return switch (op) {
            case OpNotEq:
                {
                    t: after.with(test.binding, SourcePresence.Present(GuardPresentOutcome(testedOperator))),
                    f: after.with(test.binding, SourcePresence.Absent(GuardAbsentOutcome(testedOperator)))
                };
            case _:
                {
                    t: after.with(test.binding, SourcePresence.Absent(GuardAbsentOutcome(testedOperator))),
                    f: after.with(test.binding, SourcePresence.Present(GuardPresentOutcome(testedOperator)))
                };
        }
    }

    function localSubject(e:TypedExpr):Null<{binding:Int, subject:TypedExpr}> {
        return switch (ExpressionPredicates.stripWrap(e).expr) {
            case TLocal(v): {binding: v.id, subject: e};
            case _: null;
        }
    }

    /** One unary operation. An increment or decrement writes its binding. */
    function unary(env:SourceEnvironment, node:TypedExpr, op:Unop, subject:TypedExpr, policy:SourceEvalPolicy):SourceValueTransfer {
        final writes = op == OpIncrement || op == OpDecrement;
        final inner = eval(env, subject, writes ? {record: false} : policy);
        if (!inner.normal)
            return noTransfer(inner.exits);
        final result = unopPresence(op, subject);
        return done(writes ? written(inner.environment, subject, result) : inner.environment, node, result, policy, inner.exits);
    }

    /**
        A throw and a return are expressions as well as statements, so a
        literal can hold one as an operand. Either delivers no normal
        continuation, keeps the operand's own edges, and adds its
        destination.
    **/
    function abrupt(env:SourceEnvironment, inside:Null<TypedExpr>, policy:SourceEvalPolicy,
            edge:SourceEnvironment->SourceEdge):SourceValueTransfer {
        if (inside == null)
            return noTransfer([edge(env)]);
        final transferred = eval(env, inside, policy);
        if (transferred.environment == null)
            return noTransfer(transferred.exits);
        return noTransfer(append(transferred.exits, [edge(transferred.environment)]));
    }

    /** A break and a continue reach their own loop's destination. */
    function loopEdge(env:SourceEnvironment, forward:Bool):SourceValueTransfer {
        if (loops.length == 0) {
            diagnostics.push(SourceAnalysisDiagnostic.UnconsumedEdge(forward ? "continue" : "break"));
            return noTransfer([]);
        }
        final site = loops[loops.length - 1].site;
        final edge = forward ? SourceEdge.ContinueOf(site, env) : SourceEdge.BreakOf(site, env);
        return noTransfer([edge]);
    }

    /** Threads the effects of an operand list in source order. */
    function evalList(env:Null<SourceEnvironment>, list:Array<TypedExpr>,
            policy:SourceEvalPolicy):{environment:Null<SourceEnvironment>, exits:Array<SourceEdge>} {
        var current = env;
        final exits:Array<SourceEdge> = [];
        for (entry in list) {
            if (current == null) {
                markUnreachable(entry);
                continue;
            }
            final transferred = eval(current, entry, policy);
            for (edge in transferred.exits)
                exits.push(edge);
            current = transferred.environment;
        }
        return {environment: current, exits: exits};
    }

    function conditional(env:SourceEnvironment, node:TypedExpr, c:TypedExpr, t:TypedExpr, f:Null<TypedExpr>,
            policy:SourceEvalPolicy):SourceValueTransfer {
        final condition = eval(env, c, policy);
        final exits = condition.exits.slice(0, condition.exits.length);
        final arms:SourceBranches = condition.branches == null
            ? branchesOf(condition.environment, condition.environment)
            : condition.branches;
        final thenValue = arms.t == null ? unreachableValue(t) : eval(arms.t, t, policy);
        final elseValue:SourceValueTransfer = f == null
            ? {
                environment: arms.f,
                result: SourcePresence.Unknown,
                normal: arms.f != null,
                exits: [],
                branches: null
            }
            : (arms.f == null ? unreachableValue(f) : eval(arms.f, f, policy));
        for (edge in thenValue.exits)
            exits.push(edge);
        for (edge in elseValue.exits)
            exits.push(edge);
        final joined = SourceEnvironment.join(thenValue.environment, elseValue.environment);
        // Each arm contributes its own true and false exit to the value's
        // exits, so a conditional of deciders decides too.
        final branches = branchesOf(
            SourceEnvironment.join(deciderTrue(thenValue), deciderTrue(elseValue)),
            SourceEnvironment.join(deciderFalse(thenValue), deciderFalse(elseValue)));
        return done(joined, node, SourceEnvironment.joinPresence(thenValue.result, elseValue.result), policy, exits, null, branches);
    }

    /** The true exit of a value that decides a branch. */
    function deciderTrue(value:SourceValueTransfer):Null<SourceEnvironment> {
        return value.branches == null ? value.environment : value.branches.t;
    }

    /** The false exit of a value that decides a branch. */
    function deciderFalse(value:SourceValueTransfer):Null<SourceEnvironment> {
        return value.branches == null ? value.environment : value.branches.f;
    }

    function switchValue(env:SourceEnvironment, node:TypedExpr, subject:TypedExpr,
            cases:Array<{values:Array<TypedExpr>, expr:TypedExpr}>, def:Null<TypedExpr>,
            policy:SourceEvalPolicy):SourceValueTransfer {
        final head = eval(env, subject, policy);
        if (head.environment == null)
            return noTransfer(head.exits);
        final arms = def == null ? [for (entry in cases) entry.expr] : [for (entry in cases) entry.expr].concat([def]);
        var joined:Null<SourceEnvironment> = null;
        var result:Null<SourcePresence> = null;
        final exits:Array<SourceEdge> = [];
        for (arm in arms) {
            final transferred = eval(head.environment, arm, policy);
            for (edge in transferred.exits)
                exits.push(edge);
            joined = SourceEnvironment.join(joined, transferred.environment);
            result = result == null ? transferred.result : SourceEnvironment.joinPresence(result, transferred.result);
        }
        return done(joined, node, result == null ? SourcePresence.Unknown : result, policy, exits);
    }

    function tryValue(env:SourceEnvironment, node:TypedExpr, body:TypedExpr, catches:Array<{v:TVar, expr:TypedExpr}>,
            policy:SourceEvalPolicy):SourceValueTransfer {
        if (catches.length != 1)
            return unsupported(env, ExpressionPredicates.stripWrap(body), "try region with more than one catch", policy);
        final bodyValue = eval(env, body, policy);
        if (thrownEnvironments(bodyValue.exits).length == 0) {
            markUnreachable(catches[0].expr);
            return done(bodyValue.environment, node, bodyValue.result, policy, bodyValue.exits);
        }
        final entry = env.clearFacts(unique(collectWrites(body).concat(captures)));
        final handlerValue = eval(entry, catches[0].expr, policy);
        final joined = SourceEnvironment.join(bodyValue.environment, handlerValue.environment);
        return done(joined, node, SourceEnvironment.joinPresence(bodyValue.result, handlerValue.result), policy,
            append(bodyValue.exits, handlerValue.exits));
    }

    function blockValue(env:SourceEnvironment, node:TypedExpr, stmts:Array<TypedExpr>, policy:SourceEvalPolicy):SourceValueTransfer {
        final step = block(env, stmts, policy);
        final tail = stmts.length == 0 ? null : stmts[stmts.length - 1];
        return done(step.normal, node, tail == null ? SourcePresence.Unknown : recordedPresence(tail), policy, step.exits);
    }

    function recordedPresence(e:TypedExpr):SourcePresence {
        final record = records.get(ExpressionPredicates.stripWrap(e));
        return record == null ? SourcePresence.Unknown : record.presence;
    }

    /**
        A function literal is its own prepared body. Creating it executes no
        write of its body and assigns nothing. Its entry facts come from the
        proofs this body establishes, from the caller's validated facts, and
        from `Unknown` everywhere else.
    **/
    function functionValue(env:SourceEnvironment, node:TypedExpr, fn:TFunc, policy:SourceEvalPolicy):SourceValueTransfer {
        if (!policy.record)
            return done(env, node, SourcePresence.Present(ProducerContract(SourceProducer.ObjectConstruction)), policy, []);
        final inherited:Array<SourceCaptureFact> = [];
        for (fact in input.outerCaptureFacts)
            inherited.push(fact);
        final enclosingWrites = unique(bodyWrites.concat(input.outerCapturedWrites));
        for (binding in declared)
            if (indexOf(enclosingWrites, binding) < 0 && indexOf(parameterBindings, binding) < 0)
                inherited.push({
                    binding: binding,
                    presence: env.fact(binding),
                    proof: SourceCaptureImmutability.NoEnclosingAssignment
                });
        final child = new SourcePresenceWalk({
            body: fn.expr,
            parameters: [for (argument in fn.args) {binding: argument.v.id, written: argument.v.t}],
            outerCapturedWrites: enclosingWrites,
            outerSummaryKind: EnclosingComplete,
            outerCaptureFacts: inherited
        });
        nestedBodies.set(node, child.run());
        return done(env, node, SourcePresence.Present(ProducerContract(SourceProducer.ObjectConstruction)), policy, []);
    }

    // ------------------------------------------------------------------
    // Transfer assembly
    // ------------------------------------------------------------------

    function done(env:Null<SourceEnvironment>, node:TypedExpr, presence:SourcePresence, policy:SourceEvalPolicy,
            exits:Array<SourceEdge>, ?binding:Int, ?branches:SourceBranches):SourceValueTransfer {
        final transfer:SourceValueTransfer = {
            environment: env,
            result: presence,
            normal: env != null,
            exits: exits,
            branches: branches
        };
        // One assembly rule for every producer: a path with no normal
        // continuation cannot yield an available produced value, whatever the
        // node form would have stated.
        if (!policy.record)
            return transfer;
        if (env == null) {
            recordNode(node, binding, SourcePresence.Unknown, SourceKnowledge.Conservative, SourceFactAvailability.UnreachablePath,
                transfer);
            return transfer;
        }
        recordNode(node, binding, presence, SourceKnowledge.Transferred, SourceFactAvailability.Available, transfer);
        return transfer;
    }

    function branchesOf(t:Null<SourceEnvironment>, f:Null<SourceEnvironment>):SourceBranches {
        return {t: t, f: f};
    }

    function noTransfer(exits:Array<SourceEdge>):SourceValueTransfer {
        return {environment: null, result: SourcePresence.Unknown, normal: false, exits: exits, branches: null};
    }

    function append(left:Array<SourceEdge>, right:Array<SourceEdge>):Array<SourceEdge> {
        final out = left.slice(0, left.length);
        for (edge in right)
            out.push(edge);
        return out;
    }

    /**
        The effect summary of a call, a constructor, or an accessor read: it
        may assign every captured binding and may throw. The result presence
        is stated separately and never follows from this summary.
    **/
    function afterCall(env:SourceEnvironment):SourceEnvironment {
        return env.clearFacts(captures);
    }

    function presenceOfConstant(constant:TConstant):SourcePresence {
        return switch (constant) {
            case TNull: SourcePresence.Absent(SourcePresenceReason.NullLiteral);
            case TInt(_) | TFloat(_) | TString(_) | TBool(_):
                SourcePresence.Present(ProducerContract(SourceProducer.ScalarConstant));
            case _:
                SourcePresence.Unknown;
        }
    }

    function operationPresence(op:Binop, l:TypedExpr, r:TypedExpr):SourcePresence {
        return switch (op) {
            case OpAdd:
                if (isStringWritten(l.t) || isStringWritten(r.t))
                    SourcePresence.Present(ProducerContract(SourceProducer.StringConcatenation));
                else if (isScalarWritten(l.t) && isScalarWritten(r.t))
                    SourcePresence.Present(ProducerContract(SourceProducer.ScalarOperation));
                else
                    SourcePresence.Unknown;
            case OpMult | OpDiv | OpSub | OpMod | OpShl | OpShr | OpUShr | OpAnd | OpOr | OpXor | OpGt | OpGte | OpLt | OpLte
                | OpEq | OpNotEq | OpBoolAnd | OpBoolOr:
                if (isScalarWritten(l.t) && isScalarWritten(r.t))
                    SourcePresence.Present(ProducerContract(SourceProducer.ScalarOperation));
                else
                    SourcePresence.Unknown;
            case OpInterval:
                SourcePresence.Present(ProducerContract(SourceProducer.CollectionConstruction));
            case OpArrow | OpIn:
                SourcePresence.Unknown;
            case _:
                SourcePresence.Unknown;
        }
    }

    function unopPresence(op:Unop, subject:TypedExpr):SourcePresence {
        return switch (op) {
            case OpIncrement | OpDecrement | OpNeg | OpNegBits | OpNot:
                isScalarWritten(subject.t)
                    ? SourcePresence.Present(ProducerContract(SourceProducer.ScalarOperation))
                    : SourcePresence.Unknown;
            case _:
                SourcePresence.Unknown;
        }
    }

    // ------------------------------------------------------------------
    // Conservative fallback
    // ------------------------------------------------------------------

    /**
        Marks a subtree this analysis does not transfer. The effects of the
        skipped region are accounted as a possible write of every binding the
        region names and of every captured binding, and as a possible throw,
        so no unvisited node is presented as a proven source path.
    **/
    function unsupported(env:SourceEnvironment, root:TypedExpr, form:String, policy:SourceEvalPolicy):SourceValueTransfer {
        diagnostics.push(SourceAnalysisDiagnostic.UnsupportedForm(form, root.pos));
        markNotReached(root, form);
        final cleared = env.clearFacts(unique(collectWrites(root).concat(captures)));
        return {
            environment: cleared,
            result: SourcePresence.Unknown,
            normal: true,
            exits: [SourceEdge.ThrowOfBody(cleared)],
            branches: null
        };
    }

    function unsupportedStep(env:SourceEnvironment, root:TypedExpr, form:String, policy:SourceEvalPolicy):SourceStep {
        final transferred = unsupported(env, root, form, policy);
        return {normal: transferred.environment, exits: transferred.exits};
    }

    function markNotReached(root:TypedExpr, form:String):Void {
        TypedExprTools.iter(root, function(node:TypedExpr):Void {
            markNotReached(node, form);
        });
        if (records.exists(root))
            return;
        recordNode(root, null, SourcePresence.Unknown, SourceKnowledge.Conservative, SourceFactAvailability.NotReached(form), null);
    }

    function markUnreachable(root:TypedExpr):Void {
        TypedExprTools.iter(root, function(node:TypedExpr):Void {
            markUnreachable(node);
        });
        if (records.exists(root))
            return;
        recordNode(root, null, SourcePresence.Unknown, SourceKnowledge.Conservative, SourceFactAvailability.UnreachablePath, null);
    }

    function unreachableStep(root:TypedExpr):SourceStep {
        markUnreachable(root);
        return {normal: null, exits: []};
    }

    function unreachableValue(root:TypedExpr):SourceValueTransfer {
        markUnreachable(root);
        return noTransfer([]);
    }

    function recordNode(node:TypedExpr, binding:Null<Int>, presence:SourcePresence, knowledge:SourceKnowledge,
            availability:SourceFactAvailability, transfer:Null<SourceValueTransfer>):Void {
        if (ambiguousNodes.exists(node)) {
            // The marker is sticky for the whole prepared body: a further
            // visit to one physical node revives no record and adds no second
            // diagnostic.
            return;
        }
        if (records.exists(node)) {
            records.remove(node);
            ambiguousNodes.set(node, true);
            diagnostics.push(SourceAnalysisDiagnostic.AmbiguousNode);
            return;
        }
        final occurrence:Null<SourceOccurrence> = binding == null ? null : {id: counter++, binding: binding};
        records.set(node, {
            occurrence: occurrence,
            presence: presence,
            knowledge: knowledge,
            availability: availability,
            transfer: transfer
        });
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    function isScalarWritten(t:Null<Type>):Bool {
        if (t == null)
            return false;
        if (unresolvedWritten(t))
            return false;
        return switch (Context.follow(t)) {
            case TAbstract(a, _):
                switch (a.get().name) {
                    case "Int" | "Float" | "Bool" | "Single": true;
                    case _: false;
                }
            case TInst(c, _): c.get().module == "String" && c.get().pack.length == 0;
            case _: false;
        }
    }

    function isStringWritten(t:Null<Type>):Bool {
        if (t == null)
            return false;
        if (unresolvedWritten(t))
            return false;
        return switch (Context.follow(t)) {
            case TInst(c, _): c.get().module == "String" && c.get().pack.length == 0;
            case _: false;
        }
    }

    /** Whether the written type resolved to no identity. */
    function unresolvedWritten(t:Null<Type>):Bool {
        if (t == null)
            return true;
        final facts = SourceContainerAnalysis.analyze(t);
        return switch (facts.wrapper) {
            case WrapperUnresolved(_): true;
            case _:
                switch (facts.face) {
                    case UnresolvedSource(_): true;
                    case _: false;
                }
        }
    }

    function nextSite():Int {
        counter += 1;
        return counter;
    }

    function pushExits(exits:Array<SourceBodyExit>, edges:Array<SourceEdge>):Void {
        final returns:Array<SourceEnvironment> = [];
        final throws:Array<SourceEnvironment> = [];
        for (edge in edges)
            switch (edge) {
                case ReturnOfBody(environment): returns.push(environment);
                case ThrowOfBody(environment): throws.push(environment);
                case _:
            }
        if (returns.length > 0)
            exits.push(SourceBodyExit.ReturnExit(true, SourceEnvironment.joinAll(returns).snapshot()));
        if (throws.length > 0)
            exits.push(SourceBodyExit.ThrowExit(true, SourceEnvironment.joinAll(throws).snapshot()));
    }

    static function indexOf(list:Array<Int>, value:Int):Int {
        for (index in 0...list.length)
            if (list[index] == value)
                return index;
        return -1;
    }

    static function pushUnique(list:Array<Int>, value:Int):Void {
        if (indexOf(list, value) < 0)
            list.push(value);
    }

    static function removeOne(list:Array<Int>, value:Int):Void {
        final index = indexOf(list, value);
        if (index >= 0)
            list.splice(index, 1);
    }

    static function unique(list:Array<Int>):Array<Int> {
        final out:Array<Int> = [];
        for (entry in list)
            pushUnique(out, entry);
        return out;
    }
}
#end
