#if (macro || reflaxe_runtime)
import haxe.macro.Type;
import haxe.macro.Context;
import haxe.macro.TypeTools;
import SourceContainerAnalysis;

/** Canonical source shapes and stored fields for record comparison. */
class SourceComparisonAnalysis {
    public static function schemaParameterIndex(type:Type, arguments:Array<Type>):Null<Int> {
        final key = parameterIdentity(type);
        for (index in 0...arguments.length) {
            if (type == arguments[index]) return index;
            if (key != null && parameterIdentity(arguments[index]) == key) return index;
        }
        return null;
    }

    public static function analyzeRecord(declaration:Ref<ClassType>, arguments:Array<Type>, ?maxRecordNodes:Int):SourceRecordNode {
        return new Builder(maxRecordNodes, false).record(declaration, arguments);
    }

    /** Analyze a reusable generic declaration schema using its own
        type parameters as symbolic arguments. */
    public static function analyzeRecordSchema(declaration:Ref<ClassType>):SourceRecordNode {
        return new Builder(null, true).recordSchema(declaration);
    }

    /** Resolve through the owning module so private record declarations retain
        their own reference without an external type lookup. */
    public static function declarationReference(declaration:ClassType):Ref<ClassType> {
        for (type in Context.getModule(declaration.module)) {
            switch (type) {
                case TInst(reference, _):
                    final cls = reference.get();
                    if (cls.module == declaration.module && cls.name == declaration.name)
                        return reference;
                case _:
            }
        }
        Context.error("class declaration has no compiler reference: " + declaration.module + "." + declaration.name, declaration.pos);
        return null;
    }

    public static function analyzeShape(written:Type):SourceComparisonShape {
        return new Builder(null, false).shape(written);
    }

    public static function isStoredField(field:ClassField):Bool {
        return switch (field.kind) {
            case FVar(read, write): !(read.match(AccCall) && write.match(AccNever));
            case _: false;
        };
    }

    public static function comparisonPlan(record:SourceRecordNode, request:SourceComparisonRequest):SourceComparisonPlanResult {
        return new ComparisonBuilder(request).build(record, "");
    }

    public static function operationForType(written:Type, request:SourceComparisonRequest):SourceOperationResult {
        return new ComparisonBuilder(request).operation(new Builder(null, false).shape(written), "");
    }

    /** Finite source admission for one record declaration, one actual
        argument list and one request. Every reachable declaration is
        summarized once, so a recursive field whose actual arguments grow never
        becomes a graph node. The answer is derived only after the demand
        summaries have stabilized. */
    public static function admit(declaration:Ref<ClassType>, arguments:Array<Type>, request:SourceComparisonRequest):SourceAdmissionResult {
        return admitDeclaration(RecordDeclaration(declaration), arguments, request);
    }

    /** The same admission over any written declaration identity. A stored
        field can name an alias application, so an alias's demanded slots must
        be answerable against actual arguments exactly like a record's. */
    public static function admitDeclaration(declaration:SourceDeclarationIdentity, arguments:Array<Type>,
            request:SourceComparisonRequest):SourceAdmissionResult {
        return new AdmissionBuilder(request).admit(declaration, arguments);
    }

    /** The classified source terms of one declaration: one entry per stored
        field of a record, or the single body entry of an alias with no field
        name. Classification reads no request, so this states the written edges
        that `admit` reasons over. */
    public static function declarationTerms(declaration:SourceDeclarationIdentity):Array<SourceAdmissionTerm> {
        return new AdmissionBuilder(SortedKey).observe(declaration);
    }

    /** Canonical identity of one type parameter declaration, or null when the
        written type names no type parameter. The identity carries the owning
        declaration, so two parameters that share one short name stay distinct
        and a source anonymous structure never matches. */
    public static function parameterIdentity(type:Type):Null<String> {
        return switch (type) {
            case TInst(reference, arguments):
                final cls = reference.get();
                final isParameter = cls.kind.match(KTypeParameter(_));
                arguments.length > 0 || !isParameter ? null
                    : (cls.pack.length == 0 ? "" : cls.pack.join(".") + "|") + cls.module + "|" + cls.name;
            case _: null;
        }
    }

    /** The slot of the owning declaration's own type parameter that one
        written type names, or null. Binder provenance is the owning
        declaration's parameter declaration, for a record owner and an alias
        owner alike. Provenance survives the macro substitution wrapper, and a
        separately authored type can never claim it. */
    public static function ownParameterSlot(type:Type, owner:SourceDeclarationIdentity):Null<Int> {
        final key = parameterIdentity(type);
        if (key == null) return null;
        final parameters = declarationParameters(owner);
        for (index in 0...parameters.length)
            if (parameterIdentity(parameters[index].t) == key) return index;
        return null;
    }

    /** The declared type parameters of one record or alias declaration. */
    public static function declarationParameters(owner:SourceDeclarationIdentity):Array<TypeParameter> {
        return switch (owner) {
            case RecordDeclaration(reference): reference.get().params;
            case AliasDeclaration(reference): reference.get().params;
        }
    }
}

/** The reason a consumer requests a source comparison operation. The request
    selects source policy and carries no target capability data. */
enum SourceComparisonRequest {
    SortedKey;
    OptionalEqualityCapability;
}

/** The declaration one admission node summarizes. A record application and an
    alias application are different written declarations, so the identity names
    which one; equality of two identities is decided over the qualified
    declaration path and never over a `Ref` wrapper, which this host
    allocates freshly on every access. */
enum SourceDeclarationIdentity {
    RecordDeclaration(declaration:Ref<ClassType>);
    AliasDeclaration(declaration:Ref<DefType>);
}

private class ComparisonBuilder {
    final request:SourceComparisonRequest;
    final records:Array<{source:SourceRecordNode, plan:SourceRecordComparisonPlan}> = [];

    public function new(request:SourceComparisonRequest) {
        this.request = request;
    }

    public function build(source:SourceRecordNode, path:String):SourceComparisonPlanResult {
        switch (source.state) {
            case Failed(reason): return ComparisonPlanFailed(path, reason, null);
            case AnalysisUnresolved(reason): return ComparisonPlanUnresolved(path, reason);
            case Building:
            case Complete:
        }
        // Install the placeholder before visiting fields so a finite recursive
        // record graph gets an operation-graph back-edge. Rebuilding a second
        // plan copy could expand without bound. Mark it complete only after
        // every reachable field operation has been resolved.
        for (entry in records)
            if (entry.source == source)
                return ComparisonPlanReady(entry.plan);

        final plan = new SourceRecordComparisonPlan(source);
        records.push({source: source, plan: plan});
        for (field in source.fields) {
            final fieldPath = path == "" ? field.field.name : path + "." + field.field.name;
            switch (operation(field.shape, fieldPath)) {
                case OperationReady(op): plan.fields.push({field: field.field, sourceType: field.sourceType, operation: op});
                case OperationFailed(reason, failedType): return ComparisonPlanFailed(fieldPath, reason, failedType);
                case OperationUnresolved(reason): return ComparisonPlanUnresolved(fieldPath, reason);
            }
        }
        plan.complete = true;
        return ComparisonPlanReady(plan);
    }

    public function operation(shape:SourceComparisonShape, path:String):SourceOperationResult {
        return switch (shape) {
            case IntShape: OperationReady(IntegerOrder);
            case StringShape: OperationReady(Utf16StringOrder);
            case FloatShape: request == OptionalEqualityCapability ? OperationReady(FloatOrder) : OperationFailed("Float is outside the sorted-key domain", null);
            case BoolShape: request == OptionalEqualityCapability ? OperationReady(BooleanOrder) : OperationFailed("Bool is outside the sorted-key domain", null);
            case ParameterShape(index): request == SortedKey ? OperationReady(ParameterOrder(index)) : OperationFailed("generic parameter has no optional equality evidence", null);
            case EnumShape(declaration, arguments):
                final constructors = [for (constructor in declaration.constructs) constructor];
                constructors.sort((left, right) -> left.index - right.index);
                OperationReady(EnumOrdinalOrder(declaration, arguments.copy(), constructors));
            case RecordShape(record):
                switch (build(record, path)) {
                    case ComparisonPlanReady(nested): OperationReady(RecordOrder(nested, record.arguments.copy()));
                    case ComparisonPlanFailed(failedPath, reason, failedType): OperationFailed(failedPath + ": " + reason, failedType);
                    case ComparisonPlanUnresolved(failedPath, reason): OperationUnresolved(failedPath + ": " + reason);
                }
            case RecordUseShape(record, arguments):
                switch (build(record, path)) {
                    case ComparisonPlanReady(nested): OperationReady(RecordOrder(nested, arguments.copy()));
                    case ComparisonPlanFailed(failedPath, reason, failedType): OperationFailed(failedPath + ": " + reason, failedType);
                    case ComparisonPlanUnresolved(failedPath, reason): OperationUnresolved(failedPath + ": " + reason);
                }
            case NullableShape(inner):
                switch (operation(inner, path)) {
                    case OperationReady(child): OperationReady(NullBeforePresent(child));
                    case OperationFailed(reason, failedType): OperationFailed(reason, failedType);
                    case OperationUnresolved(reason): OperationUnresolved(reason);
                }
            case SequenceShape(element):
                switch (operation(element, path + "[]")) {
                    case OperationReady(child): OperationReady(Lexicographic(child));
                    case OperationFailed(reason, failedType): OperationFailed(reason, failedType);
                    case OperationUnresolved(reason): OperationUnresolved(reason);
                }
            case UnsupportedShape(sourceType): OperationFailed("unsupported resolved source shape", sourceType);
            case UnresolvedShape(reason): OperationUnresolved("unresolved source shape: " + Std.string(reason));
        };
    }
}

enum SourceOperationResult {
    OperationReady(operation:SourceComparisonOperation);
    OperationFailed(reason:String, sourceType:Null<Type>);
    OperationUnresolved(reason:String);
}

enum SourceComparisonPlanResult {
    ComparisonPlanReady(plan:SourceRecordComparisonPlan);
    ComparisonPlanFailed(path:String, reason:String, sourceType:Null<Type>);
    ComparisonPlanUnresolved(path:String, reason:String);
}

class SourceRecordComparisonPlan {
    public final source:SourceRecordNode;
    public final fields:Array<SourcePlannedField> = [];
    public var complete:Bool = false;

    public function new(source:SourceRecordNode) {
        this.source = source;
    }
}

typedef SourcePlannedField = {
    final field:ClassField;
    final sourceType:Type;
    final operation:SourceComparisonOperation;
}

enum SourceComparisonOperation {
    IntegerOrder;
    Utf16StringOrder;
    FloatOrder;
    BooleanOrder;
    EnumOrdinalOrder(declaration:EnumType, arguments:Array<Type>, constructors:Array<EnumField>);
    ParameterOrder(index:Int);
    RecordOrder(record:SourceRecordComparisonPlan, arguments:Array<Type>);
    NullBeforePresent(child:SourceComparisonOperation);
    Lexicographic(child:SourceComparisonOperation);
}

private class Builder {
    final records:Array<SourceRecordNode> = [];
    final maxRecordNodes:Null<Int>;
    final schemaMode:Bool;
    public function new(maxRecordNodes:Null<Int>, schemaMode:Bool) {
        this.maxRecordNodes = maxRecordNodes;
        this.schemaMode = schemaMode;
    }

    public function record(declarationRef:Ref<ClassType>, arguments:Array<Type>):SourceRecordNode {
        final declaration = declarationRef.get();
        for (known in records) {
            if (schemaMode && sameClassDeclaration(known.declarationRef, declarationRef))
                return known;
            if (sameClassDeclaration(known.declarationRef, declarationRef) && sameArguments(known.arguments, arguments))
                return known;
        }

        final node = new SourceRecordNode(declarationRef, arguments.copy(), Building);
        records.push(node);
        if (maxRecordNodes != null && records.length > maxRecordNodes) {
            node.state = AnalysisUnresolved("comparison graph exceeded the requested analysis work limit");
            return node;
        }
        for (field in declaration.fields.get()) {
            if (!SourceComparisonAnalysis.isStoredField(field))
                continue;
            final instantiated = TypeTools.applyTypeParameters(field.type, declaration.params, arguments);
            final fieldShape = schemaMode ? shape(instantiated, declarationRef, arguments) : shape(instantiated);
            node.fields.push({field: field, sourceType: instantiated, shape: fieldShape});
        }
        node.state = Complete;
        return node;
    }

    public function recordSchema(declarationRef:Ref<ClassType>):SourceRecordNode {
        final declaration = declarationRef.get();
        for (known in records)
            if (sameClassDeclaration(known.declarationRef, declarationRef))
                return known;
        final arguments = [for (parameter in declaration.params) parameter.t];
        final node = new SourceRecordNode(declarationRef, arguments.copy(), Building);
        records.push(node);
        for (field in declaration.fields.get()) {
            if (!SourceComparisonAnalysis.isStoredField(field))
                continue;
            final instantiated = TypeTools.applyTypeParameters(field.type, declaration.params, arguments);
            node.fields.push({field: field, sourceType: instantiated, shape: shape(instantiated, declarationRef, arguments)});
        }
        node.state = Complete;
        return node;
    }

    public function shape(written:Type, ?binderOwner:Ref<ClassType>, ?binderArguments:Array<Type>):SourceComparisonShape {
        final facts = SourceContainerAnalysis.analyze(written);
        return switch (facts.wrapper) {
            case ExplicitOuterNull(wrapped): NullableShape(shape(wrapped, binderOwner, binderArguments));
            case WrapperUnresolved(reason): UnresolvedShape(reason);
            case NoExplicitWrapper:
                switch (facts.face) {
                    case ReadOnlyArrayFace(element): SequenceShape(shape(element, binderOwner, binderArguments));
                    case MutableArray(_): UnsupportedShape(written);
                    case UnresolvedSource(reason): UnresolvedShape(reason);
                    case OtherSourceType:
                        final resolved = facts.resolvedType;
                        resolved == null ? UnresolvedShape(LazyResolutionFailed) : terminalShape(resolved, binderOwner, binderArguments);
                }
        };
    }

    function terminalShape(t:Type, ?binderOwner:Ref<ClassType>, ?binderArguments:Array<Type>):SourceComparisonShape {
        if (binderOwner != null) {
            final slot = SourceComparisonAnalysis.ownParameterSlot(t, RecordDeclaration(binderOwner));
            if (slot != null) return ParameterShape(slot);
        }
        return switch (t) {
            case TAbstract(a, _):
                final abs = a.get();
                if (isRootAbstract(abs, "Int")) IntShape else if (isRootAbstract(abs, "Float")) FloatShape else if (isRootAbstract(abs, "Bool")) BoolShape else UnsupportedShape(t);
            case TInst(c, arguments):
                final cls = c.get();
                if (isRootClass(cls, "String")) StringShape else if (cls.meta.has(":dataClass")) {
                    schemaMode ? RecordUseShape(recordSchema(c), arguments.copy()) : RecordShape(record(c, arguments));
                } else UnsupportedShape(t);
            case TEnum(e, arguments): EnumShape(e.get(), arguments.copy());
            case _: UnsupportedShape(t);
        };
    }

    public static function isRootAbstract(abs:AbstractType, name:String):Bool {
        return abs.name == name && abs.pack.length == 0 && abs.module == "StdTypes";
    }

    public static function isRootClass(cls:ClassType, name:String):Bool {
        return cls.name == name && cls.pack.length == 0 && cls.module == name;
    }

    function sameArguments(left:Array<Type>, right:Array<Type>):Bool {
        return sameArgumentsWithContext(left, right, [], []);
    }

    function sameArgumentsWithContext(left:Array<Type>, right:Array<Type>, seenLeft:Array<Type>, seenRight:Array<Type>):Bool {
        if (left.length != right.length)
            return false;
        for (index in 0...left.length)
            if (!sameType(left[index], right[index], seenLeft, seenRight))
                return false;
        return true;
    }

    /** Structural, non-unifying identity comparison for instantiated type
        arguments. Nominal references use their physical compiler identity. */
    function sameType(left:Type, right:Type, seenLeft:Array<Type>, seenRight:Array<Type>):Bool {
        if (left == right)
            return true;
        for (index in 0...seenLeft.length)
            if (seenLeft[index] == left && seenRight[index] == right)
                return true;
        seenLeft.push(left);
        seenRight.push(right);
        final result = switch ([left, right]) {
            case [TInst(l, lp), TInst(r, rp)]: sameClassDeclaration(l, r) && sameArgumentsWithContext(lp, rp, seenLeft, seenRight);
            case [TEnum(l, lp), TEnum(r, rp)]: sameEnumDeclaration(l, r) && sameArgumentsWithContext(lp, rp, seenLeft, seenRight);
            case [TAbstract(l, lp), TAbstract(r, rp)]: sameAbstractDeclaration(l, r) && sameArgumentsWithContext(lp, rp, seenLeft, seenRight);
            case [TType(l, lp), TType(r, rp)]: sameTypedefDeclaration(l, r) && sameArgumentsWithContext(lp, rp, seenLeft, seenRight);
            case [TMono(l), TMono(r)]: l == r;
            case [TLazy(l), TLazy(r)]: l == r;
            case [TAnonymous(l), TAnonymous(r)]: l == r;
            case [TDynamic(l), TDynamic(r)]: sameNullableType(l, r, seenLeft, seenRight);
            case [TFun(la, lr), TFun(ra, rr)]:
                la.length == ra.length && sameType(lr, rr, seenLeft, seenRight) && sameFunctionArguments(la, ra, seenLeft, seenRight);
            case _: false;
        };
        seenLeft.pop();
        seenRight.pop();
        return result;
    }

    function sameNullableType(left:Null<Type>, right:Null<Type>, seenLeft:Array<Type>, seenRight:Array<Type>):Bool {
        return if (left == null) right == null else right != null && sameType(left, right, seenLeft, seenRight);
    }

    function sameFunctionArguments(left:Array<{name:String, opt:Bool, t:Type}>, right:Array<{name:String, opt:Bool, t:Type}>, seenLeft:Array<Type>, seenRight:Array<Type>):Bool {
        if (left.length != right.length)
            return false;
        for (index in 0...left.length)
            if (left[index].name != right[index].name || left[index].opt != right[index].opt || !sameType(left[index].t, right[index].t, seenLeft, seenRight))
                return false;
        return true;
    }

    public function sameClassDeclaration(left:Ref<ClassType>, right:Ref<ClassType>):Bool {
        if (left == right)
            return true;
        final l = left.get();
        final r = right.get();
        if (isTypeParameter(l) || isTypeParameter(r))
            return isTypeParameter(l) && isTypeParameter(r) && sameTypeParameter(left, right);
        return sameBaseIdentity(l, r);
    }

    /** Whether two admission nodes summarize the same declaration. A record
        identity never equals an alias identity, and both are decided over the
        qualified declaration path, because a macro `Ref` wrapper is freshly
        allocated on every access in this host and never identifies one. */
    public function sameDeclaration(left:SourceDeclarationIdentity, right:SourceDeclarationIdentity):Bool {
        return switch ([left, right]) {
            case [RecordDeclaration(l), RecordDeclaration(r)]: sameClassDeclaration(l, r);
            case [AliasDeclaration(l), AliasDeclaration(r)]: sameTypedefDeclaration(l, r);
            case _: false;
        }
    }

    function sameTypeParameter(left:Ref<ClassType>, right:Ref<ClassType>):Bool {
        // A macro `Ref` wrapper is freshly allocated on every access, so
        // pointer equality misses the same logical parameter written twice
        // inside one record (each field sees its own fresh parameter `Ref`).
        // The parameter identity key embeds the owning declaration's full
        // path, so it is owner-unique and serial key comparison decides
        // without cross-owner slot confusion (see `parameterIdentity`).
        if (left == right)
            return true;
        final leftKey = SourceComparisonAnalysis.parameterIdentity(TInst(left, []));
        final rightKey = SourceComparisonAnalysis.parameterIdentity(TInst(right, []));
        return leftKey != null && leftKey == rightKey;
    }

    static function isTypeParameter(cls:ClassType):Bool {
        return switch (cls.kind) {
            case KTypeParameter(_): true;
            case _: false;
        };
    }

    static function sameEnumDeclaration(left:Ref<EnumType>, right:Ref<EnumType>):Bool {
        return left == right || sameBaseIdentity(left.get(), right.get());
    }

    static function sameAbstractDeclaration(left:Ref<AbstractType>, right:Ref<AbstractType>):Bool {
        return left == right || sameBaseIdentity(left.get(), right.get());
    }

    static function sameTypedefDeclaration(left:Ref<DefType>, right:Ref<DefType>):Bool {
        return left == right || sameBaseIdentity(left.get(), right.get());
    }

    static function sameBaseIdentity(left:BaseType, right:BaseType):Bool {
        if (left.module != right.module || left.name != right.name || left.pack.length != right.pack.length)
            return false;
        for (index in 0...left.pack.length)
            if (left.pack[index] != right.pack[index])
                return false;
        return true;
    }
}

class SourceRecordNode {
    public final declarationRef:Ref<ClassType>;
    public final declaration:ClassType;
    public final arguments:Array<Type>;
    public var state:SourceRecordState;
    public final fields:Array<SourceComparisonField> = [];

    public function new(declarationRef:Ref<ClassType>, arguments:Array<Type>, state:SourceRecordState) {
        this.declarationRef = declarationRef;
        this.declaration = declarationRef.get();
        this.arguments = arguments;
        this.state = state;
    }
}

enum SourceRecordState {
    Building;
    Complete;
    Failed(reason:String);
    AnalysisUnresolved(reason:String);
}

typedef SourceComparisonField = {
    final field:ClassField;
    final sourceType:Type;
    final shape:SourceComparisonShape;
}

enum SourceComparisonShape {
    IntShape;
    StringShape;
    FloatShape;
    BoolShape;
    ParameterShape(index:Int);
    EnumShape(declaration:EnumType, arguments:Array<Type>);
    RecordShape(record:SourceRecordNode);
    RecordUseShape(record:SourceRecordNode, arguments:Array<Type>);
    NullableShape(inner:SourceComparisonShape);
    SequenceShape(element:SourceComparisonShape);
    UnsupportedShape(sourceType:Type);
    UnresolvedShape(reason:UnresolvedReason);
}

/** One stored-field term of a declaration summary. Every term carries the
    written type it came from, and application arguments stay as written so a
    later target phase can compose evidence from them.

    An alias application is a term of its own. It names the alias declaration
    and carries the actual-argument terms of that occurrence, so a repeated
    alias closes the traversal on its declaration while its actual arguments
    remain on the edge. The written `Null` and `ReadOnlyArray` faces stay explicit
    on the edges that reach it. */
enum SourceFieldTerm {
    TermInt(type:Type);
    TermString(type:Type);
    TermFloat(type:Type);
    TermBool(type:Type);
    TermEnum(declaration:EnumType, arguments:Array<Type>, type:Type);
    TermBinder(owner:SourceDeclarationIdentity, slot:Int, type:Type);
    TermApplication(declaration:SourceDeclarationIdentity, arguments:Array<SourceFieldTerm>, type:Type);
    TermAlias(declaration:SourceDeclarationIdentity, arguments:Array<SourceFieldTerm>, type:Type);
    TermNull(inner:SourceFieldTerm, type:Type);
    TermReadOnlyArray(inner:SourceFieldTerm, type:Type);
    TermUnsupported(type:Type);
    TermUnresolved(reason:UnresolvedReason, type:Type);
}

/** Why one source form supplies no comparison operation. */
enum SourceFieldFailure {
    FieldRejected(type:Type);
    FieldUnresolved(reason:UnresolvedReason);
}

/** Why the requested source form is outside the comparison domain. */
enum SourceRejectionReason {
    /** A stored field type is outside the request domain. */
    UnsupportedStoredFieldType(type:Type);
    /** A demanded actual argument supplies no operation. */
    UnsupportedDemandedArgumentType(type:Type);
    /** A demanded parameter has no optional equality evidence. */
    ParameterWithoutEqualityEvidence(slot:Int);
}

/** One edge from a declaration to a nested record or alias application. */
typedef SourceAdmissionEdge = {
    final declaration:SourceDeclarationIdentity;
    final field:Null<String>;
}

/** One diagnostic site. `declaration` and `field` name the stored field, or
    the alias body when `field` is null, that carries the failing form, `type`
    is that form, and `chain` lists the nested declaration edges crossed from
    the requested declaration. A recursive path stops at `cycleBoundary`. */
typedef SourceObligationSite = {
    final declaration:SourceDeclarationIdentity;
    final field:Null<String>;
    final type:Null<Type>;
    final chain:Array<SourceAdmissionEdge>;
    final cycleBoundary:Bool;
}

/** The finite source answer for one declaration and request. */
typedef SourceAdmissionSummary = {
    final declaration:SourceDeclarationIdentity;
    final request:SourceComparisonRequest;
    /** Parameter slots whose comparison operation is required. */
    final requiredSlots:Array<Int>;
    /** Required slots whose actual is still a binder, so the caller supplies
        the operation. */
    final unsuppliedSlots:Array<Int>;
    /** Distinct record and alias declarations the summary visited. */
    final visitedDeclarations:Int;
}

/** One classified term of a declaration: a stored field of a record, or the
    whole body of an alias with no field name. */
typedef SourceAdmissionTerm = {
    final field:Null<String>;
    final type:Type;
    final term:SourceFieldTerm;
}

/** Finite source admission for one declaration, one actual argument list and
    one request. This result carries capability and obligation sites only; it
    names no target symbol, import or printed expression. A failed answer also
    carries how many declarations were visited, so a diagnostic can tell a deep
    walk from a shallow one. */
enum SourceAdmissionResult {
    SourceAdmissionAdmitted(summary:SourceAdmissionSummary);
    SourceAdmissionRejected(reason:SourceRejectionReason, site:SourceObligationSite, visitedDeclarations:Int);
    SourceAdmissionIncomplete(reason:UnresolvedReason, site:SourceObligationSite, visitedDeclarations:Int);
}

enum SourceAdmissionState {
    StateClean;
    StateRejected;
    StateUnresolved;
}

enum SourceDemandOutcome {
    DemandOk;
    DemandUnsupplied(slot:Int);
    DemandRejected(reason:SourceRejectionReason, site:SourceObligationSite);
    DemandIncomplete(reason:UnresolvedReason, site:SourceObligationSite);
}

/** One declaration in the admission graph. A declaration is a node once; its
    instantiations are argument terms on the edges, never nodes. A record
    contributes one term per stored field, an alias exactly one term for its
    body, with no field name. */
private class SourceDeclarationSummary {
    public final declaration:SourceDeclarationIdentity;
    public final binders:Array<Type>;
    public final terms:Array<SourceAdmissionTerm> = [];
    public var requiredSlots:Array<Int> = [];
    public var state:SourceAdmissionState = StateClean;
    public var stateReason:Null<UnresolvedReason> = null;

    public function new(declaration:SourceDeclarationIdentity, binders:Array<Type>) {
        this.declaration = declaration;
        this.binders = binders;
    }
}

/** Derives the finite source admission answer. The demand sets and the field
    states ascend a finite lattice until both are stable, and the request is
    evaluated only afterwards. */
private class AdmissionBuilder {
    final request:SourceComparisonRequest;
    final declarations:Array<SourceDeclarationSummary> = [];
    final identity:Builder;

    public function new(request:SourceComparisonRequest) {
        this.request = request;
        this.identity = new Builder(null, false);
    }

    public function admit(declaration:SourceDeclarationIdentity, arguments:Array<Type>):SourceAdmissionResult {
        final root = discover(declaration);
        discoverReachable(root, []);
        stabilize();
        final failure = stateFailure(root, []);
        if (failure != null) return failure;
        final unsupplied:Array<Int> = [];
        for (slot in root.requiredSlots) {
            if (slot >= arguments.length)
                return SourceAdmissionIncomplete(NullTypeInput, obligationSite(root, null, null, [], false), declarations.length);
            final actual = classifyActual(arguments[slot], root);
            switch (checkDemand(actual, root, demandField(root, slot), [], true)) {
                case DemandOk:
                case DemandUnsupplied(index): addSlot(unsupplied, index);
                case DemandRejected(reason, site): return SourceAdmissionRejected(reason, site, declarations.length);
                case DemandIncomplete(reason, site): return SourceAdmissionIncomplete(reason, site, declarations.length);
            }
        }
        return SourceAdmissionAdmitted({
            declaration: root.declaration,
            request: request,
            requiredSlots: root.requiredSlots.copy(),
            unsuppliedSlots: sortSlots(unsupplied),
            visitedDeclarations: declarations.length
        });
    }

    /** The classified terms of one declaration, without a request. This is the
        observation entry: it builds the same graph `admit` builds and stops
        before any demand is solved. */
    public function observe(declaration:SourceDeclarationIdentity):Array<SourceAdmissionTerm> {
        return discover(declaration).terms.copy();
    }

    /** One declaration is discovered once. The node is installed before its
        terms are classified, so a recursive record edge and a recursive alias
        occurrence both re-enter the same summary while its demand data is
        still empty. That placeholder is never read as an answer: every
        decision happens after stabilize. */
    function discover(declaration:SourceDeclarationIdentity):SourceDeclarationSummary {
        for (known in declarations)
            if (identity.sameDeclaration(known.declaration, declaration)) return known;
        final binders = [for (parameter in SourceComparisonAnalysis.declarationParameters(declaration)) parameter.t];
        final summary = new SourceDeclarationSummary(declaration, binders);
        declarations.push(summary);
        switch (declaration) {
            case RecordDeclaration(reference):
                final owner = reference.get();
                for (field in owner.fields.get()) {
                    if (!SourceComparisonAnalysis.isStoredField(field)) continue;
                    final instantiated = TypeTools.applyTypeParameters(field.type, owner.params, binders);
                    summary.terms.push({field: field.name, type: instantiated, term: classify(instantiated, declaration, binders)});
                }
            case AliasDeclaration(reference):
                final body = reference.get().type;
                final written:Type = body == null ? TType(reference, binders) : body;
                summary.terms.push({field: null, type: written,
                    term: body == null ? TermUnresolved(LazyResolutionFailed, written) : classify(body, declaration, binders)});
        }
        return summary;
    }

    function discoverReachable(summary:SourceDeclarationSummary, visited:Array<SourceDeclarationSummary>):Void {
        if (containsSummary(visited, summary)) return;
        visited.push(summary);
        for (entry in summary.terms) collectApplications(entry.term, visited);
    }

    function collectApplications(term:SourceFieldTerm, visited:Array<SourceDeclarationSummary>):Void {
        switch (term) {
            case TermApplication(declaration, arguments, _): visitApplication(declaration, arguments, visited);
            case TermAlias(declaration, arguments, _): visitApplication(declaration, arguments, visited);
            case TermNull(inner, _) | TermReadOnlyArray(inner, _): collectApplications(inner, visited);
            case _:
        }
    }

    /** Installs the applied declaration and walks its actual argument terms.
        Both application kinds close here, so neither kind of repeated
        declaration grows the graph. */
    function visitApplication(declaration:SourceDeclarationIdentity, arguments:Array<SourceFieldTerm>,
            visited:Array<SourceDeclarationSummary>):Void {
        final nested = discover(declaration);
        if (!containsSummary(visited, nested)) discoverReachable(nested, visited);
        for (argument in arguments) collectApplications(argument, visited);
    }

    /** Least fixed point of the demanded slot sets and the field states. Each
        component only grows or worsens, so the iteration reaches the least
        solution and its result cannot depend on the visit order. */
    function stabilize():Void {
        var changed = true;
        while (changed) {
            changed = false;
            for (summary in declarations) {
                final slots = demandedSlots(summary);
                if (!sameSlots(slots, summary.requiredSlots)) {
                    summary.requiredSlots = slots;
                    changed = true;
                }
                final next = evaluateState(summary);
                if (next.state != summary.state || next.reason != summary.stateReason) {
                    summary.state = next.state;
                    summary.stateReason = next.reason;
                    changed = true;
                }
            }
        }
    }

    function demandedSlots(summary:SourceDeclarationSummary):Array<Int> {
        final result:Array<Int> = [];
        for (entry in summary.terms)
            for (slot in needSlots(entry.term)) addSlot(result, slot);
        return sortSlots(result);
    }

    /** The parameter slots of the owning declaration that this term compares.
        A record application contributes the required slots of the applied
        record, an alias application those of the applied alias body. Both read
        the applied declaration's own slot set, so a repeated declaration
        transfers demand through one edge and closes the repeated declaration. */
    function needSlots(term:SourceFieldTerm):Array<Int> {
        return switch (term) {
            case TermBinder(_, slot, _): [slot];
            case TermInt(_) | TermString(_) | TermFloat(_) | TermBool(_) | TermEnum(_, _, _): [];
            case TermUnsupported(_) | TermUnresolved(_, _): [];
            case TermNull(inner, _) | TermReadOnlyArray(inner, _): needSlots(inner);
            case TermApplication(declaration, arguments, _): transferredSlots(declaration, arguments);
            case TermAlias(declaration, arguments, _): transferredSlots(declaration, arguments);
        }
    }

    /** Demand transfer through one application edge: the applied declaration's
        required slots, mapped onto the actual argument terms. */
    function transferredSlots(declaration:SourceDeclarationIdentity, arguments:Array<SourceFieldTerm>):Array<Int> {
        final nested = known(declaration);
        final result:Array<Int> = [];
        for (slot in nested.requiredSlots) {
            if (slot >= arguments.length) continue;
            for (need in needSlots(arguments[slot])) addSlot(result, need);
        }
        return result;
    }

    /** null when every stored field is comparable in this request domain. */
    function evaluateState(summary:SourceDeclarationSummary):{state:SourceAdmissionState, reason:Null<UnresolvedReason>} {
        for (entry in summary.terms) {
            final result = evaluateTerm(entry.term);
            if (result.state != StateClean) return result;
        }
        return {state: StateClean, reason: null};
    }

    /** One field term contributes its own failure, the failure of a nested
        declaration, or the failure of an argument bound at a demanded slot. */
    function evaluateTerm(term:SourceFieldTerm):{state:SourceAdmissionState, reason:Null<UnresolvedReason>} {
        final unresolved = leafUnresolved(term);
        if (unresolved != null) return {state: StateUnresolved, reason: unresolved};
        if (leafRejected(term)) return {state: StateRejected, reason: null};
        return switch (term) {
            case TermNull(inner, _) | TermReadOnlyArray(inner, _): evaluateTerm(inner);
            case TermApplication(declaration, arguments, _): appliedState(declaration, arguments);
            case TermAlias(declaration, arguments, _): appliedState(declaration, arguments);
            case _: {state: StateClean, reason: null};
        }
    }

    /** The state of one application: the applied declaration's own state,
        then the failure of any actual bound at a demanded slot. The applied
        state is the stored fixed-point variable, so an application edge is
        never re-entered while it is being solved. */
    function appliedState(declaration:SourceDeclarationIdentity, arguments:Array<SourceFieldTerm>):{state:SourceAdmissionState, reason:Null<UnresolvedReason>} {
        final nested = known(declaration);
        if (nested.state == StateUnresolved) return {state: StateUnresolved, reason: nested.stateReason};
        if (nested.state == StateRejected) return {state: StateRejected, reason: null};
        for (slot in nested.requiredSlots) {
            if (slot >= arguments.length) return {state: StateUnresolved, reason: NullTypeInput};
            final failure = argumentFailure(arguments[slot]);
            if (failure != null)
                return switch (failure) {
                    case FieldUnresolved(reason): {state: StateUnresolved, reason: reason};
                    case FieldRejected(_): {state: StateRejected, reason: null};
                }
        }
        return {state: StateClean, reason: null};
    }

    /** Whether a demanded argument term of an application supplies an
            operation. A binder forwards the requirement to the owning slot. */
    function argumentFailure(term:SourceFieldTerm):Null<SourceFieldFailure> {
        return switch (term) {
            case TermBinder(_, _, _) | TermInt(_) | TermString(_) | TermEnum(_, _, _): null;
            case TermFloat(_) | TermBool(_): request == SortedKey ? FieldRejected(termType(term)) : null;
            case TermUnsupported(_): FieldRejected(termType(term));
            case TermUnresolved(reason, _): FieldUnresolved(reason);
            case TermNull(inner, _) | TermReadOnlyArray(inner, _): argumentFailure(inner);
            case TermApplication(declaration, arguments, _): appliedArgumentFailure(declaration, arguments, term);
            case TermAlias(declaration, arguments, _): appliedArgumentFailure(declaration, arguments, term);
        }
    }

    function appliedArgumentFailure(declaration:SourceDeclarationIdentity, arguments:Array<SourceFieldTerm>,
            term:SourceFieldTerm):Null<SourceFieldFailure> {
        final nested = known(declaration);
        if (nested.state == StateUnresolved) return FieldUnresolved(nested.stateReason);
        if (nested.state == StateRejected) return FieldRejected(termType(term));
        for (slot in nested.requiredSlots) {
            if (slot >= arguments.length) return FieldUnresolved(NullTypeInput);
            final failure = argumentFailure(arguments[slot]);
            if (failure != null) return failure;
        }
        return null;
    }

    function leafRejected(term:SourceFieldTerm):Bool {
        return switch (term) {
            case TermUnsupported(_): true;
            case TermFloat(_) | TermBool(_): request == SortedKey;
            case TermNull(inner, _) | TermReadOnlyArray(inner, _): leafRejected(inner);
            case _: false;
        }
    }

    function leafUnresolved(term:SourceFieldTerm):Null<UnresolvedReason> {
        return switch (term) {
            case TermUnresolved(reason, _): reason;
            case TermNull(inner, _) | TermReadOnlyArray(inner, _): leafUnresolved(inner);
            case _: null;
        }
    }

    function stateFailure(summary:SourceDeclarationSummary, chain:Array<SourceAdmissionEdge>):Null<SourceAdmissionResult> {
        if (summary.state == StateClean) return null;
        final found = locate(summary, chain, []);
        final visited = declarations.length;
        return switch (summary.state) {
            case StateRejected: SourceAdmissionRejected(UnsupportedStoredFieldType(found.site.type), found.site, visited);
            case StateUnresolved: SourceAdmissionIncomplete(found.reason, found.site, visited);
            case StateClean: null;
        }
    }

    /** Walks to the first failing stored field in declaration order. The walk
        enters a nested declaration once, so a recursive path terminates at a
        cycle boundary and never grows a path string. */
    function locate(summary:SourceDeclarationSummary, chain:Array<SourceAdmissionEdge>,
            visited:Array<SourceDeclarationSummary>):{site:SourceObligationSite, reason:Null<UnresolvedReason>} {
        if (containsSummary(visited, summary))
            return {site: obligationSite(summary, null, null, chain, true), reason: summary.stateReason};
        visited.push(summary);
        for (entry in summary.terms) {
            final found = locateInTerm(entry.term, summary, entry, chain, visited);
            if (found != null) return found;
        }
        return {site: obligationSite(summary, null, null, chain, false), reason: summary.stateReason};
    }

    function locateInTerm(term:SourceFieldTerm, summary:SourceDeclarationSummary, entry:SourceAdmissionTerm, chain:Array<SourceAdmissionEdge>,
            visited:Array<SourceDeclarationSummary>):Null<{site:SourceObligationSite, reason:Null<UnresolvedReason>}> {
        final unresolved = leafUnresolved(term);
        if (unresolved != null)
            return {site: obligationSite(summary, entry.field, entry.type, chain, false), reason: unresolved};
        if (leafRejected(term)) return {site: obligationSite(summary, entry.field, entry.type, chain, false), reason: null};
        return switch (term) {
            case TermNull(inner, _) | TermReadOnlyArray(inner, _): locateInTerm(inner, summary, entry, chain, visited);
            case TermApplication(declaration, arguments, _): locateApplication(declaration, arguments, summary, entry, chain, visited);
            case TermAlias(declaration, arguments, _): locateApplication(declaration, arguments, summary, entry, chain, visited);
            case _: null;
        }
    }

    /** Reports the first demanded actual that supplies no operation, or walks
        into the applied declaration when that declaration itself fails. */
    function locateApplication(declaration:SourceDeclarationIdentity, arguments:Array<SourceFieldTerm>, summary:SourceDeclarationSummary,
            entry:SourceAdmissionTerm, chain:Array<SourceAdmissionEdge>,
            visited:Array<SourceDeclarationSummary>):Null<{site:SourceObligationSite, reason:Null<UnresolvedReason>}> {
        final nested = known(declaration);
        for (slot in nested.requiredSlots) {
            if (slot >= arguments.length) continue;
            final failure = argumentFailure(arguments[slot]);
            if (failure != null)
                return {
                    site: obligationSite(summary, entry.field, termType(arguments[slot]), chain, false),
                    reason: switch (failure) {
                        case FieldUnresolved(reason): reason;
                        case FieldRejected(_): null;
                    }
                };
        }
        if (nested.state != StateClean) {
            chain.push({declaration: summary.declaration, field: entry.field});
            return locate(nested, chain, visited);
        }
        return null;
    }

    /** Checks one demanded actual argument. A binder at the requested
        declaration leaves the operation to the caller; a binder inside a
        nested application is already covered, because the demand transfer
        mapped it to a slot of the requested declaration. */
    function checkDemand(term:SourceFieldTerm, owner:SourceDeclarationSummary, field:Null<String>, chain:Array<SourceAdmissionEdge>,
            atRoot:Bool):SourceDemandOutcome {
        final unresolved = leafUnresolved(term);
        if (unresolved != null) return DemandIncomplete(unresolved, obligationSite(owner, field, termType(term), chain, false));
        if (leafRejected(term)) return DemandRejected(UnsupportedDemandedArgumentType(termType(term)),
            obligationSite(owner, field, termType(term), chain, false));
        return switch (term) {
            case TermBinder(_, slot, _):
                if (!atRoot) DemandOk;
                else if (request == SortedKey) DemandUnsupplied(slot);
                else DemandRejected(ParameterWithoutEqualityEvidence(slot), obligationSite(owner, field, termType(term), chain, false));
            case TermNull(inner, _) | TermReadOnlyArray(inner, _): checkDemand(inner, owner, field, chain, atRoot);
            case TermApplication(declaration, arguments, _): checkDemandedApplication(declaration, arguments, owner, field, chain);
            case TermAlias(declaration, arguments, _): checkDemandedApplication(declaration, arguments, owner, field, chain);
            case _: DemandOk;
        }
    }

    function checkDemandedApplication(declaration:SourceDeclarationIdentity, arguments:Array<SourceFieldTerm>, owner:SourceDeclarationSummary,
            field:Null<String>, chain:Array<SourceAdmissionEdge>):SourceDemandOutcome {
        final nested = known(declaration);
        final nestedChain = chain.copy();
        if (field != null) nestedChain.push({declaration: owner.declaration, field: field});
        switch (nested.state) {
            case StateClean:
            case _:
                final found = locate(nested, nestedChain, []);
                return switch (found.reason) {
                    case null: DemandRejected(UnsupportedStoredFieldType(found.site.type), found.site);
                    case reason: DemandIncomplete(reason, found.site);
                }
        }
        for (slot in nested.requiredSlots) {
            if (slot >= arguments.length)
                return DemandIncomplete(NullTypeInput, obligationSite(nested, null, null, nestedChain, false));
            switch (checkDemand(arguments[slot], nested, null, nestedChain, false)) {
                case DemandOk:
                case other: return other;
            }
        }
        return DemandOk;
    }

    /** The first stored field whose term demands one slot, or null when the
        demand arrives through an alias body. */
    function demandField(summary:SourceDeclarationSummary, slot:Int):Null<String> {
        for (entry in summary.terms)
            if (needSlots(entry.term).indexOf(slot) >= 0) return entry.field;
        return null;
    }

    function known(declaration:SourceDeclarationIdentity):SourceDeclarationSummary {
        for (known in declarations)
            if (identity.sameDeclaration(known.declaration, declaration)) return known;
        throw new haxe.Exception("admission visited an undiscovered declaration");
    }

    function classifyActual(written:Type, root:SourceDeclarationSummary):SourceFieldTerm {
        final slot = SourceComparisonAnalysis.ownParameterSlot(written, root.declaration);
        return slot == null ? classify(written, root.declaration, root.binders) : TermBinder(root.declaration, slot, written);
    }

    /** Classifies one written type into a finite source term. An alias
        application is a term of its own: the alias declaration is discovered
        once and the occurrence carries its actual-argument terms, so a legal
        recursive alias closes on its own declaration, with the occurrence's
        actual argument terms retained on the edge. */
    function classify(written:Type, owner:SourceDeclarationIdentity, binders:Array<Type>):SourceFieldTerm {
        return switch (written) {
            case TType(aliasRef, arguments):
                final declaration = AliasDeclaration(aliasRef);
                discover(declaration);
                TermAlias(declaration, [for (argument in arguments) classify(argument, owner, binders)], written);
            case _:
                final facts = SourceContainerAnalysis.analyze(written);
                switch (facts.wrapper) {
                    case ExplicitOuterNull(wrapped): TermNull(classify(wrapped, owner, binders), written);
                    case WrapperUnresolved(reason): TermUnresolved(reason, written);
                    case NoExplicitWrapper: switch (facts.face) {
                        case ReadOnlyArrayFace(element): TermReadOnlyArray(classify(element, owner, binders), written);
                        case MutableArray(_): TermUnsupported(written);
                        case UnresolvedSource(reason): TermUnresolved(reason, written);
                        case OtherSourceType:
                            final resolved = facts.resolvedType;
                            resolved == null ? TermUnresolved(LazyResolutionFailed, written) : terminal(resolved, owner, binders, written);
                    }
                }
        }
    }

    function terminal(resolved:Type, owner:SourceDeclarationIdentity, binders:Array<Type>, written:Type):SourceFieldTerm {
        final slot = SourceComparisonAnalysis.ownParameterSlot(resolved, owner);
        if (slot != null) return TermBinder(owner, slot, written);
        return switch (resolved) {
            case TAbstract(abstractRef, _):
                final abs = abstractRef.get();
                if (Builder.isRootAbstract(abs, "Int")) TermInt(written);
                else if (Builder.isRootAbstract(abs, "Float")) TermFloat(written);
                else if (Builder.isRootAbstract(abs, "Bool")) TermBool(written);
                else TermUnsupported(written);
            case TInst(classRef, arguments):
                final cls = classRef.get();
                if (Builder.isRootClass(cls, "String")) TermString(written);
                else if (cls.meta.has(":dataClass"))
                    TermApplication(RecordDeclaration(classRef), [for (argument in arguments) classify(argument, owner, binders)], written);
                else TermUnsupported(written);
            case TEnum(enumRef, arguments): TermEnum(enumRef.get(), arguments.copy(), written);
            case _: TermUnsupported(written);
        }
    }

    function termType(term:SourceFieldTerm):Type {
        return switch (term) {
            case TermInt(type) | TermString(type) | TermFloat(type) | TermBool(type): type;
            case TermEnum(_, _, type) | TermBinder(_, _, type) | TermApplication(_, _, type) | TermAlias(_, _, type): type;
            case TermNull(_, type) | TermReadOnlyArray(_, type): type;
            case TermUnsupported(type) | TermUnresolved(_, type): type;
        }
    }

    function obligationSite(owner:SourceDeclarationSummary, field:Null<String>, type:Null<Type>, chain:Array<SourceAdmissionEdge>,
            cycleBoundary:Bool):SourceObligationSite {
        return {declaration: owner.declaration, field: field, type: type, chain: chain.copy(), cycleBoundary: cycleBoundary};
    }

    function addSlot(slots:Array<Int>, slot:Int):Void {
        if (slots.indexOf(slot) < 0) slots.push(slot);
    }

    function sortSlots(slots:Array<Int>):Array<Int> {
        final copy = slots.copy();
        copy.sort((left, right) -> left - right);
        return copy;
    }

    function sameSlots(left:Array<Int>, right:Array<Int>):Bool {
        if (left.length != right.length) return false;
        for (index in 0...left.length)
            if (left[index] != right[index]) return false;
        return true;
    }

    function containsSummary(list:Array<SourceDeclarationSummary>, candidate:SourceDeclarationSummary):Bool {
        for (entry in list)
            if (entry == candidate) return true;
        return false;
    }
}

/** One registered binder: the minted type, its field name, the owning
    declaration and the parameter slot. */
#end
