#if (macro || reflaxe_runtime)
import haxe.macro.Type;
import haxe.macro.TypeTools;

/**
    Written source container identity, as declared by the source.

    `analyze` is the one canonical producer of the source facts of a written
    type. One resolution walk carries the explicit outer `Null` wrapper, the
    container declaration, and the element together, so a caller can never
    combine the wrapper of one walk with the container of another. The three
    legacy container queries are adapters that select from this result.

    Recognition is by compiler-typed declaration identity, never by a printed
    name. The built-in mutable `Array` is recognized in its own declaration
    module with no package (`module = Array`, `pack = []`, `name = Array`);
    the reserved read-only declaration is recognized as
    `module = std.ReadOnlyArray`, `pack = ["std"]`, `name = ReadOnlyArray`;
    the built-in `Null` is recognized as `module = StdTypes`, `pack = []`,
    `name = Null`. Every other resolved type stays distinct, including a
    foreign declaration sharing one of those names. A transparent typedef
    receives the facts of its resolved declaration with the alias's actual
    type arguments substituted.

    An explicit outer `Null` wrapper is a separate fact from the container
    face and is reported for the written spelling only. A `Null` in an
    element belongs to that element type; the element is never classified
    further, because the outer answer does not need it. The absence of a
    written wrapper states nothing about runtime presence.

    Resolution tracks compiler references by physical identity and retains
    actual alias arguments. It has no semantic depth limit, so every finite
    alias chain can reach its declaration. Repeated alias inputs, lazy handles,
    and monomorph references are cycles. A pending monomorph and a failed lazy
    remain unresolved; no container is invented.

    The analysis reads compiler types only. It renders nothing, dispatches on
    no target, and mutates no Boring semantic state. Calling a lazy handle
    may memoize inside the host compiler, which is host behavior and not a
    Boring semantic state change.
**/
class SourceContainerAnalysis {
    /** Classifies one written source type. */
    public static function analyze(written:Null<Type>):SourceContainerFacts {
        return resolve(written);
    }

    /** One iterative resolution walk carries the outer wrapper it entered. */
    static function resolve(written:Null<Type>):SourceContainerFacts {
        var current = written;
        var outerNull:Null<Type> = null;
        final aliases:Array<AliasVisit> = [];
        final lazies:Array<Void->Type> = [];
        final monomorphs:Array<Ref<Null<Type>>> = [];
        while (current != null) {
            switch (current) {
                case TAbstract(abstractRef, params):
                    final abs = abstractRef.get();
                    if (isNullDeclaration(abs)) {
                        switch (params) {
                            case [inner]:
                                if (outerNull == null)
                                    outerNull = inner;
                                current = inner;
                            case _:
                                return resolved(outerNull, OtherSourceType, current);
                        }
                    } else if (isReadOnlyDeclaration(abs) && params.length == 1) {
                        return resolved(outerNull, ReadOnlyArrayFace(params[0]), current);
                    } else {
                        return resolved(outerNull, OtherSourceType, current);
                    }
                case TInst(classRef, params):
                    final cls = classRef.get();
                    if (isArrayDeclaration(cls) && params.length == 1) {
                        return resolved(outerNull, MutableArray(params[0]), current);
                    } else {
                        return resolved(outerNull, OtherSourceType, current);
                    }
                case TType(aliasRef, params):
                    var repeated = false;
                    for (visit in aliases) {
                        if (visit.ref == aliasRef && sameArguments(visit.params, params)) {
                            repeated = true;
                            break;
                        }
                    }
                    if (repeated)
                        return unresolved(CycleDetected, outerWrapper(outerNull, CycleDetected));
                    aliases.push({ref: aliasRef, params: params.copy()});
                    switch (resolveAlias(aliasRef, params)) {
                        case Resolved(resolved): current = resolved;
                        case Unresolvable(reason): return unresolved(reason, outerWrapper(outerNull, reason));
                        case Threw: return unresolved(LazyResolutionFailed, outerWrapper(outerNull, LazyResolutionFailed));
                    }
                case TLazy(handle):
                    if (containsLazy(lazies, handle)) {
                        return unresolved(CycleDetected, outerWrapper(outerNull, CycleDetected));
                    }
                    lazies.push(handle);
                    switch (resolveLazy(handle)) {
                        case Resolved(resolved): current = resolved;
                        case Unresolvable(reason): return unresolved(reason, outerWrapper(outerNull, reason));
                        case Threw: return unresolved(LazyResolutionFailed, outerWrapper(outerNull, LazyResolutionFailed));
                    }
                case TMono(monomorphRef):
                    if (containsMonomorph(monomorphs, monomorphRef)) {
                        return unresolved(CycleDetected, outerWrapper(outerNull, CycleDetected));
                    }
                    monomorphs.push(monomorphRef);
                    final referenced = monomorphRef.get();
                    if (referenced == null) {
                        // A pending monomorph is unresolved; it is neither a
                        // container nor a scalar, and no wrapper is claimed.
                        return unresolved(PendingMonomorph, outerWrapper(outerNull, PendingMonomorph));
                    } else {
                        // A resolved monomorph classifies from the type it now
                        // references.
                        current = referenced;
                    }
                case _:
                    return resolved(outerNull, OtherSourceType, current);
            }
        }
        return unresolved(NullTypeInput, outerWrapper(outerNull, NullTypeInput));
    }

    static function resolved(outerNull:Null<Type>, face:SourceContainerFace, resolvedType:Type):SourceContainerFacts {
        return {wrapper: outerNull == null ? NoExplicitWrapper : ExplicitOuterNull(outerNull), face: face, resolvedType: resolvedType};
    }

    static function outerWrapper(outerNull:Null<Type>, reason:UnresolvedReason):SourceNullWrapper {
        return outerNull == null ? WrapperUnresolved(reason) : ExplicitOuterNull(outerNull);
    }

    static function unresolved(reason:UnresolvedReason, wrapper:SourceNullWrapper):SourceContainerFacts {
        return {wrapper: wrapper, face: UnresolvedSource(reason), resolvedType: null};
    }

    static function sameArguments(left:Array<Type>, right:Array<Type>):Bool {
        if (left.length != right.length)
            return false;
        for (index in 0...left.length) {
            if (left[index] != right[index])
                return false;
        }
        return true;
    }

    static function containsLazy(handles:Array<Void->Type>, candidate:Void->Type):Bool {
        for (handle in handles)
            if (handle == candidate)
                return true;
        return false;
    }

    static function containsMonomorph(handles:Array<Ref<Null<Type>>>, candidate:Ref<Null<Type>>):Bool {
        for (handle in handles)
            if (handle == candidate)
                return true;
        return false;
    }

    /** Whether the declaration is the built-in `Null` of the root package. */
    static function isNullDeclaration(abs:AbstractType):Bool {
        return abs.name == "Null" && abs.pack.length == 0 && abs.module == "StdTypes";
    }

    /** Whether the declaration is the built-in mutable `Array`. */
    static function isArrayDeclaration(cls:ClassType):Bool {
        return cls.name == "Array" && cls.pack.length == 0 && cls.module == "Array";
    }

    /**
        Whether the declaration is the reserved read-only array of std. Only
        the specified declaration qualifies; a name or package approximation
        does not.
    **/
    static function isReadOnlyDeclaration(abs:AbstractType):Bool {
        return abs.name == "ReadOnlyArray" && abs.module == "std.ReadOnlyArray" && abs.pack.length == 1 && abs.pack[0] == "std";
    }

    /** One lazy resolution through the supported macro API. */
    static function resolveLazy(handle:Void->Type):SourceResolution {
        try {
            final resolved = handle();
            if (resolved == null) {
                return Unresolvable(LazyResolutionFailed);
            }
            return Resolved(resolved);
        } catch (failure:haxe.Exception) {
            return Threw;
        } catch (failure:String) {
            // A malformed synthetic handle is recorded as unresolved; it is
            // never an ordinary source type and never a container.
            return Threw;
        }
    }

    /** One transparent alias resolution with the alias's type arguments. */
    static function resolveAlias(aliasRef:Ref<DefType>, params:Array<Type>):SourceResolution {
        try {
            final def = aliasRef.get();
            final declared = def.type;
            if (declared == null) {
                return Unresolvable(LazyResolutionFailed);
            }
            final resolved = params.length == 0 ? declared : TypeTools.applyTypeParameters(declared, def.params, params);
            if (resolved == null) {
                return Unresolvable(LazyResolutionFailed);
            }
            return Resolved(resolved);
        } catch (failure:haxe.Exception) {
            return Threw;
        } catch (failure:String) {
            return Threw;
        }
    }
}

/** Whether the written spelling carries an explicit outer `Null` wrapper. */
enum SourceNullWrapper {
    /** The written type is `Null<T>`; the wrapped type is carried as
        written. */
    ExplicitOuterNull(wrapped:Type);

    /** The written spelling reached a concrete declaration with no wrapper.
        This states nothing about runtime presence. */
    NoExplicitWrapper;

    /** The wrapper could not be decided because a resolution step did not
        resolve. No absence is claimed. */
    WrapperUnresolved(reason:UnresolvedReason);
}

/** The source container declaration the written type names. */
enum SourceContainerFace {
    /** The built-in mutable `Array<T>`. */
    MutableArray(element:Type);

    /** The reserved `std.ReadOnlyArray<T>` source face. */
    ReadOnlyArrayFace(element:Type);

    /** A resolved type that names neither built-in container, including a
        foreign declaration sharing one of their names. */
    OtherSourceType;

    /** The written type resolved to no identity; no container is invented. */
    UnresolvedSource(reason:UnresolvedReason);
}

/** Why a written type resolved to no identity. */
enum UnresolvedReason {
    /** The caller supplied no type. */
    NullTypeInput;

    /** A lazy handle failed while resolving. The handle is the problem; the
        result says nothing about accepted source. */
    LazyResolutionFailed;

    /** A monomorph is still pending, so the written type is not yet known. */
    PendingMonomorph;

    /** Alias, lazy, or monomorph resolution revisited the same typed input. */
    CycleDetected;
}

/** One alias declaration and the actual arguments at that occurrence. */
typedef AliasVisit = {
    final ref:Ref<DefType>;
    final params:Array<Type>;
}

/** Outcome of one wrapper or alias resolution step. */
enum SourceResolution {
    Resolved(resolved:Type);
    Unresolvable(reason:UnresolvedReason);
    Threw;
}

/** The source facts of one written type, produced by one resolution. */
typedef SourceContainerFacts = {
    /** Explicit outer `Null` wrapper of the written spelling. */
    final wrapper:SourceNullWrapper;

    /** Source container declaration the written type names. */
    final face:SourceContainerFace;

    /** Fully resolved terminal type for non-container source analysis. Null
        only when the resolution itself is unresolved. */
    final resolvedType:Null<Type>;
}
#end
