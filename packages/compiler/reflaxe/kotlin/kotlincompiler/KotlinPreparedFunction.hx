package kotlincompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Type;
import ExpressionPredicates;
import SourceLocalPresenceAnalysis;
import SourceLocalPresenceAnalysis.SourceLocalPresenceFacts;
import SourceLocalPresenceAnalysis.SourceUseFacts;
import SourceLocalPresenceAnalysis.SourceFactAvailability;
import SourceLocalPresenceAnalysis.SourceKnowledge;
import SourceLocalPresenceAnalysis.SourcePresence;
import SourceLocalPresenceAnalysis.SourceUseSubject;

/**
    One prepared body: the normalized root, its source facts, and the target
    declaration storage this target selected before printing.

    The query adapter keeps every source distinction. `localRead` returns the
    source facts of one use with their subject, availability, knowledge,
    presence, and occurrence, so a consumer can keep `Present`, `Absent`,
    `Unknown`, `UnreachablePath`, `NoOccurrence`, and `NotReached` apart. A
    consumer may promote a local presence proof only when the subject is
    `LocalUse`, the availability is `Available`, the knowledge is `Transferred`,
    and the presence is `Present`; `localPresent` states exactly that test and
    nothing weaker.
**/
class KotlinPreparedFunction {
    /** The normalized root this artifact owns. */
    public final root:TypedExpr;

    /** The source facts of `root`. */
    public final source:SourceLocalPresenceFacts;

    /** Which kind of member this body lowers. */
    public final context:KotlinBodyContext;

    /** Declared return type, or null for a constructor or a Void member. */
    public final declaredReturn:Null<Type>;

    /** Whole-body write set. The current conservative smart-cast input. */
    public final wholeFunctionWrites:Map<Int, Bool>;

    /**
        Bindings this body writes from inside a nested function. Kotlin
        refuses to smart-cast a local a capturing closure can mutate, and it
        applies that rule to the whole function rather than from the write's
        source position, because the closure may run at any call. (PIT-388)
    **/
    public final closureWrites:Map<Int, Bool>;

    /** Target entry facts: parameters the signature lifted to non-null. */
    public final targetEntryNonNull:Map<Int, Bool> = [];

    /** Declaration storage, recorded by the declaration pass. */
    public final declared:Map<Int, KotlinDeclarationStorage> = [];

    /** Whether the declaration storage pass has run for this artifact. */
    public var completed:Bool = false;

    public function new(root:TypedExpr, source:SourceLocalPresenceFacts, context:KotlinBodyContext, declaredReturn:Null<Type>,
            wholeFunctionWrites:Map<Int, Bool>, closureWrites:Map<Int, Bool>) {
        this.root = root;
        this.source = source;
        this.context = context;
        this.declaredReturn = declaredReturn;
        this.wholeFunctionWrites = wholeFunctionWrites;
        this.closureWrites = closureWrites;
    }

    /**
        The source facts of one use. Subject, availability, knowledge, presence,
        and occurrence stay distinct, so a consumer cannot merge them.
    **/
    public function localRead(use:TypedExpr):SourceUseFacts {
        return source.useFacts(use);
    }

    /** Whether one use carries a promotable local presence proof. */
    public function localPresent(use:TypedExpr):Bool {
        final facts = source.useFacts(use);
        return switch (facts.subject) {
            case LocalUse(_):
                facts.availability == SourceFactAvailability.Available
                    && facts.knowledge == SourceKnowledge.Transferred
                    && switch (facts.presence) {
                        case Present(_): true;
                        case _: false;
                    }
            case NonLocalUse: false;
        }
    }

    /**
        Whether the declaration this node declares is a syntactic null-test
        member. Membership selects declaration storage and is not a presence
        proof.
    **/
    public function nullTestedAt(declaration:TypedExpr):Bool {
        return source.nullTestedAt(declaration);
    }

    /**
        Whether Kotlin can smart-cast this binding. The body's own write set is
        the current conservative adapter decision; the Kotlin language rule is
        the authority and this approximation stays beside it.
    **/
    public function nativePromotable(binding:Int):Bool {
        return !wholeFunctionWrites.exists(binding);
    }

    public function declaredStorage(binding:Int):Null<KotlinDeclarationStorage> {
        return declared.get(binding);
    }

    public function recordStorage(storage:KotlinDeclarationStorage):Void {
        declared.set(storage.binding, storage);
    }

}

/** Which kind of member one prepared body lowers. */
enum KotlinBodyContext {
    FunctionBody;
    ConstructorBody;
    NestedBody;
}

/** Every emitter state one prepared body can fill. */
typedef EmitterState = {
    final usedNames:Map<String, Bool>;

    final localNames:Map<Int, String>;

    final emittedLocalNames:Map<String, Int>;

    final nonNullFields:Map<String, Bool>;

    final extractedLocals:Map<Int, Bool>;

    final extractedFields:Map<String, Bool>;

    final floatRenderedBinops:Map<String, Bool>;

    final enumVariants:Map<Int, String>;

    final enumVariantExpressions:Map<String, String>;
}

/** The target declaration storage one local binding was given. */
typedef KotlinDeclarationStorage = {
    final binding:Int;

    /** A null literal initialized a reference-typed binding. */
    final nullInitialized:Bool;

    /** A `Null<T>` initializer, so the declaration keeps a nullable type. */
    final declaredNullableInit:Bool;

    /** The initializer renders a nullable Kotlin value. */
    final rendersNullable:Bool;

    /** The declaration extracts the null-typed initializer once. */
    final extractsAtDecl:Bool;

    /** A non-null-typed initializer that still renders nullable. */
    final extractRenderedNullable:Bool;

    /** A null-initialized family binding that extracts at its declaration. */
    final nullInitExtract:Bool;
}
#end
