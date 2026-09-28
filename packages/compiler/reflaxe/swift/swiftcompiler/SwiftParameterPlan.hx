package swiftcompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Type;
import DefaultArgExpander.CoalescingDefaultValue;
import DefaultArgExpander.DefaultArgValue;
import ValueTypeSupport;
import swiftcompiler.SwiftArrayBoundary.SwiftArrayOptionality;
import swiftcompiler.SwiftArrayBoundary.SwiftArrayPresenceFact;
import swiftcompiler.SwiftArrayBoundary.SwiftArrayStorage;

enum SwiftParameterDefaultMode {
    NoParameterDefault;
    NativeValueDefault;
    OptionalNilBodyDefault;
}

/** Text-free Swift declaration and body facts for one Haxe parameter. */
typedef SwiftParameterDecision = {
    final sourceType:Type;
    final argumentName:String;
    final argumentIndex:Int;
    final parameterType:Type;
    final defaultValue:Null<DefaultArgValue>;
    final coalescingValue:Null<CoalescingDefaultValue>;
    final defaultMode:SwiftParameterDefaultMode;
    final readsParameter:Bool;
    final throwsDefault:Bool;
    final referencesPrivateMember:Bool;
    final bodyStorage:SwiftArrayStorage;
    final bodyOptionality:SwiftArrayOptionality;
    final bodyPresenceFact:SwiftArrayPresenceFact;
}

/**
    One Swift-owned producer for the parameter declaration mode and the
    corresponding body binding representation. Callers render the returned
    decision; they do not repeat the Optional/default selection rule.
**/
class SwiftParameterPlan {
    static function makeOptional(t:Type):Type {
        return switch (Context.getType("Null")) {
            case TAbstract(a, _): TAbstract(a, [t]);
            case _: t;
        };
    }

    public static function forArgument(cls:ClassType, fieldName:String, argumentName:String, index:Int, sourceType:Type,
            allowDefaults:Bool = true):SwiftParameterDecision {
        final registered = allowDefaults ? DefaultArgExpander.defaultAt(cls, fieldName, index) : null;
        final coalescing = registered == null ? null : DefaultArgExpander.coalescingOf(registered);
        final readsParameter = coalescing != null && DefaultArgExpander.coalescingReadsParamForParam(cls, fieldName, argumentName);
        final throwsDefault = coalescing != null && coalescingDefaultThrows(coalescing);
        final referencesPrivate = coalescing != null && coalescingDefaultReferencesPrivate(coalescing);
        final baseType = coalescing == null ? sourceType : DefaultArgExpander.coalescingParameterType(coalescing, sourceType);
        final optionalNil = coalescing != null && (readsParameter || throwsDefault || referencesPrivate);
        final parameterType = optionalNil ? makeOptional(baseType) : baseType;
        final defaultMode = coalescing == null ? NoParameterDefault : optionalNil ? OptionalNilBodyDefault : NativeValueDefault;
        final bodyStorage = SwiftArrayBoundary.sourceStorage(baseType);
        // The parameter's exposed Swift type can be optional even when the
        // body shadows it with `p ?? fallback`. Body facts describe that
        // selected normalized value, whose type is baseType. If the fallback
        // itself is nullable, baseType remains nullable and proves nothing.
        final bodyIsOptional = SwiftArrayBoundary.isOptionalArrayType(baseType);
        final bodyOptionality = if (bodyIsOptional) {
            OptionalOperand;
        } else {
            RequiredOperand;
        };
        final bodyPresence = if (bodyIsOptional) {
            NoPresenceProof;
        } else if (defaultMode != NoParameterDefault) {
            // The selected body binding is required after default
            // normalization. Default mode by itself proves nothing: nullable
            // defaults preserve a Null-wrapped body type.
            DefaultMaterializedPresent;
        } else {
            SourceTypeRequired;
        };
        return {
            sourceType: sourceType,
            argumentName: argumentName,
            argumentIndex: index,
            parameterType: parameterType,
            defaultValue: registered,
            coalescingValue: coalescing,
            defaultMode: defaultMode,
            readsParameter: readsParameter,
            throwsDefault: throwsDefault,
            referencesPrivateMember: referencesPrivate,
            bodyStorage: bodyStorage,
            bodyOptionality: bodyOptionality,
            bodyPresenceFact: bodyPresence
        };
    }

    public static function coalescingDefaultThrows(value:CoalescingDefaultValue):Bool {
        return switch (value) {
            case CStaticCall(modulePath, className, methodName, args): coalescingStaticTargetThrows(modulePath, className,
                    methodName) || coalescingArgsThrow(args);
            case CConstructorCall(modulePath, className, args): SwiftFallibility.isThrowing(modulePath, className, "new", false) || coalescingArgsThrow(args);
            case CMethodCall(receiver, _, args): coalescingDefaultThrows(receiver) || coalescingArgsThrow(args);
            case CFieldAccess(receiver, _): coalescingDefaultThrows(receiver);
            case CConditional(c, t, f): coalescingDefaultThrows(c) || coalescingDefaultThrows(t) || coalescingDefaultThrows(f);
            case CBinaryOp(_, left, right): coalescingDefaultThrows(left) || coalescingDefaultThrows(right);
            case _: false;
        };
    }

    public static function coalescingDefaultReferencesPrivate(value:CoalescingDefaultValue):Bool {
        return switch (value) {
            case CStaticCall(modulePath, className, methodName, args): coalescingStaticTargetPrivate(modulePath, className,
                    methodName) || coalescingArgsPrivate(args);
            case CConstructorCall(_, _, args): coalescingArgsPrivate(args);
            case CMethodCall(receiver, _, args): coalescingDefaultReferencesPrivate(receiver) || coalescingArgsPrivate(args);
            case CFieldAccess(receiver, _): coalescingDefaultReferencesPrivate(receiver);
            case CConditional(c, t, f): coalescingDefaultReferencesPrivate(c) || coalescingDefaultReferencesPrivate(t) || coalescingDefaultReferencesPrivate(f);
            case CBinaryOp(_, left, right): coalescingDefaultReferencesPrivate(left) || coalescingDefaultReferencesPrivate(right);
            case _: false;
        };
    }

    static function coalescingArgsThrow(args:Array<CoalescingDefaultValue>):Bool {
        for (value in args) {
            if (coalescingDefaultThrows(value))
                return true;
        }
        return false;
    }

    static function coalescingArgsPrivate(args:Array<CoalescingDefaultValue>):Bool {
        for (value in args) {
            if (coalescingDefaultReferencesPrivate(value))
                return true;
        }
        return false;
    }

    static function coalescingStaticTargetThrows(modulePath:String, className:String, methodName:String):Bool {
        final resolved = try Context.getType(modulePath + "." + className) catch (_:Dynamic) null;
        return switch (resolved) {
            case TInst(c, _): SwiftFallibility.staticCallThrows(c.get(), methodName);
            case TAbstract(a, _):
                final abs = a.get();
                if (ValueTypeSupport.isMarkedAbstract(abs)
                    && methodName == ValueTypeSupport.constructorName(abs)) ValueTypeSupport.constructorThrows(abs); else
                    SwiftFallibility.routedCallThrows(modulePath, className, methodName, true);
            case _: SwiftFallibility.routedCallThrows(modulePath, className, methodName, true);
        };
    }

    static function coalescingStaticTargetPrivate(modulePath:String, className:String, methodName:String):Bool {
        final resolved = try Context.getType(modulePath + "." + className) catch (_:Dynamic) null;
        return switch (resolved) {
            case TInst(c, _):
                var found = false;
                for (field in c.get().statics.get()) {
                    if (field.name == methodName) {
                        found = !field.isPublic && !field.meta.has(":allow");
                        break;
                    }
                }
                found;
            case _: false;
        };
    }
}
#end
