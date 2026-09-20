package rustcompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Expr.Binop;
import haxe.macro.Expr.Unop;
import haxe.macro.Type;
import haxe.macro.Type.FieldAccess;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypedExprTools;
import reflaxe.data.ClassFuncData;
import ExpressionPredicates;
import PolicyQueries;
import PolicyQueries.EnumQueryStep;
import ExpressionBlockNorm;
import AssignTargetPlan;
import AssignTargetPlan.AssignTargetFieldKind;
import PolicyQueries.StdStringCategory;
import PolicyQueries.Int64Op;
import FusionPlan;
import FusionPlan.FusionStep;
import VarFusionPlan;
import TerminationAnalysis;
import ValueTypeSupport;
import ValueTypePlan;

/**
    Statement and expression lowering from the Haxe typed AST to Rust.
**/
class RustExpr {
    // EnumCycleDetector classification is shared by PolicyQueries.
    // Runtime shim parameters that take i32 where the haxe declaration
    // says Int. slice clamps with bounds that may be negative, so its
    // bound parameters are signed in the Rust runtime; the compiler
    // cannot read a Rust signature, so the signed positions are listed
    // here and the call sites cast into them. Resident runtime modules
    // take their signed positions from the resident ABI rule at every
    // call, so they carry no entry here.
    static final SIGNED_SHIM_PARAMS:Map<String, Array<Int>> = ["u_string.slice" => [1, 2]];

    final imports:RustImports;
    final types:RustType;
    final state:RustEmissionState;

    var isFallible:Bool = false;
    var countOverflowVariant:Null<String> = null;
    var errorTypeName:Null<String> = null;
    // StringBuf lowering can run while a nested renderer temporarily clears
    // the active error context. Keep the enclosing function's declared enum
    // so its UStringFault payload still reaches the correct synthetic variant.
    var declaredErrorTypeName:Null<String> = null;
    var returnUnsigned:Bool = false;
    var returnTypeName:Null<String> = null;
    var currentReturnType:Null<Type> = null;
    // A field used as a method receiver remains borrowed; value reads clone
    // non-Copy fields unless this narrow receiver context applies.
    var renderingMethodReceiver:Bool = false;
    var inTryClosure:Bool = false;

    final subst:Map<Int, String> = [];

    /** Catch variables of the region being lowered; features/06 catch-site lowering. */
    final catchVars:Map<Int, Bool> = [];

    // Locals declared outside a try closure need mutable, initialized storage
    // when the closure assigns them.
    final tryCapturedAssignments:Map<Int, Bool> = [];
    final mutated:Map<Int, Bool> = [];
    /**
        Set while emitting a switch whose value the statement position
        discards (`case X: null;` side-effect idiom). The arm renderer
        turns null-literal arms into empty blocks so every arm unifies on
        the unit type; mixing None with () would not compile.
    **/
    var discardingStatementSwitch:Bool = false;
    final deferredLocals:Map<Int, Bool> = [];
    final usedNames:Map<String, Bool> = [];

    /** Active runtime renderers for cyclic enum stringification. */
    final enumStringNaming:EnumStringHelperNaming = new EnumStringHelperNaming();

    final hiddenNames:Map<Int, String> = [];
    final rangeLoopVars:Map<Int, Bool> = [];
    final argTypes:Map<String, String> = [];
    final paramVarIds:Map<Int, Bool> = [];
    // Actual constructor-call arguments used while materializing coalescing defaults.
    final defaultParameterSubstitutions:Map<String, String> = [];
    final genericParamIds:Map<Int, Bool> = [];
    final closureParamIds:Map<Int, Bool> = [];
    // Local function values whose body throws: the closure signature carries
    // the enclosing Result error so call sites can propagate it.
    final fallibleLocalFunctionErrors:Map<Int, String> = [];
    // Error type of the local function literal currently being lowered; null
    // for argument closures that do not own a Result boundary.
    var localFunctionErrorName:Null<String> = null;
    var inGenericFunction:Bool = false;
    final borrowedLoopVarIds:Map<Int, Bool> = [];
    final provenNonNullVarIds:Map<Int, Bool> = [];
    // Array locals captured by two or more nested functions whose scan
    // proved a write. Each capturing closure clones the Arc, so the writes
    // of one are visible to the readers of the others, matching the
    // reference semantics of Haxe Array captures. (SharedClosureArrays)
    final sharedClosureArrays:Map<Int, Bool> = [];
    // Scalar locals (Int/Float/Bool) written inside a named local function
    // lowered as Arc<dyn Fn>. The Fn contract forbids assigning a captured
    // binding, so the scalar shares through Arc<Mutex> like the array family.
    // (SharedClosureScalars)
    final sharedClosureScalars:Map<Int, Bool> = [];
    // Subject texts proven non-null by an `if (X == null) { continue; }`
    // guard inside a loop. A later `let v = X;` copy of the same subject
    // inherits the proof, so it passes call slots as the inner value.
    // (ContinueNullGuards)
    final provenContinueSubjects:Map<String, Bool> = [];
    // Cursor locals: initialized from a nullable proven source and later
    // re-assigned an Option-typed expression inside a loop. They keep the
    // Option shape end to end. (CursorPattern)
    final cursorLocals:Map<Int, Bool> = [];
    // Locals initialized from a ternary whose else arm is the null
    // literal: the binding renders as an Option, and a non-null value
    // slot unwraps it at the boundary. (NullElseTernaryLocals)
    final nullElseTernaryLocals:Map<Int, Bool> = [];
    // Locals whose initializer already rendered through the forcing read
    // (an unwrap_or): the binding holds the inner value, so a return of
    // that local must not unwrap again. (ForcingReadLocals)
    final forcingReadLocals:Map<Int, Bool> = [];
    // Sorted map get() calls proven present by an enclosing has() guard.
    // Keyed by the rendered receiver+key text so a get() inside the guard
    // unwraps its Option into the value slot.
    final provenMapGets:Array<String> = [];
    // Option subjects narrowed by an immediately enclosing null guard. The
    // rendered text is the key because guarded subjects may be fields.
    final optionNarrowings:Array<{subjectText:String, name:String}> = [];
    var optionNarrowingHitCount:Int = 0;
    final fillNarrowings:Array<{subjectText:String, fillBody:String}> = [];
    final readsAfterDeclaration:Map<Int, Bool> = [];
    // Locals pushed into a container and read somewhere else in the same
    // function: their push argument must clone, since Haxe's push keeps
    // the source binding alive. (PushedThenRead)
    final pushedThenRead:Map<Int, Bool> = [];
    // Sorted-table builders whose every put stores a has-guard-proven
    // value: their value type lowers bare, and reads of the built table
    // see non-null values. (BuilderValueNullability)
    final bareValueBuilders:Map<Int, Bool> = [];
    final bareValueBuilderPos:Map<String, Bool> = [];
    final builtBareTables:Map<Int, Bool> = [];
    // Field paths proven non-null by enclosing `x.f != null` guards.
    // (BuilderValueNullability)
    final fieldNullGuards:Map<String, Bool> = [];
    // Locals a conditional arm names as a bare value of owned non-Copy
    // type while a later mention of the local remains in statement order:
    // the arm must clone or the later read trips E0382.
    // (BranchArmMoveClone)
    final branchArmMoveReadsAfter:Map<Int, Bool> = [];
    // Locals whose binding the body never reads: their declarations take
    // the underscore name Rust uses for intentionally unused bindings.
    // (UnusedLocalNaming)
    final unusedLocalIds:Map<Int, Bool> = [];
    // Declarations the typer shares with a `for` binding: the loop
    // re-initializes the var and every read sits inside the loop, so the
    // emitted `for` shadows the declaration and the line drops.
    // (ForSharedBindingDeclaration)
    final forSharedLocals:Map<Int, Bool> = [];
    // Declared locals the interval machinery adopted as counted-loop
    // counters: the emitted `for index in ..` rebinds and the loop's own
    // increment disappears into the stride, so the declaration's `mut`
    // would be unused. (IntervalCounterMut)
    final intervalCounterLocals:Map<Int, Bool> = [];
    // Reassigned locals whose constant initializer is never read between
    // the declaration and the first reassignment: Haxe requires the
    // initializer, Rust reads nothing from it, so the declaration drops
    // it. Only literal initializers participate (no side effects to
    // preserve). (DeadConstantInitElision)
    // Capture-copy bindings the current function-value prologue emits:
    // inside the closure body a captured name binds an owned clone of the
    // outer value, so an element loop over it must borrow or the loop
    // moves the capture out of the Fn closure. (ClosureCaptureBorrow)
    var currentCaptureClones:Map<Int, Bool> = [];
    // Captures whose closure body calls a mutating method through the
    // capture's field chain: the prologue copy binding takes mut, and the
    // mutation applies to the closure's own copy, which an Fn closure may
    // not do to the captured binding itself. (ClosureCaptureMutation)
    var currentCaptureMut:Map<Int, Bool> = [];
    // Capture copies a function-value prologue converted to owned String:
    // reads inside the closure body borrow the copy as a &str view.
    // (ClosureCaptureOwnedCopy)
    var captureOwnedStringCopies:Map<Int, Bool> = [];
    final unsignedLocals:Map<Int, Bool> = [];
    // Locals whose declaration received a sunk initializer through
    // DeadInitializerMatchFusion: the value crossed an assignment boundary,
    // so the declaration renders through the same numeric adaptation an
    // assignment applies. Haxe var ids are globally unique, so stale
    // entries cannot collide across functions.
    final sunkInitVarIds:Map<Int, Bool> = [];
    // Locals initialized from charCodeAt are collapsed from Option<u32> to a scalar.
    final nullableCollapsedLocals:Map<Int, Bool> = [];
    // Locals whose emitted declaration text names or infers the Option
    // shape: the exact ground truth for whether a read of the local
    // renders an Option. (NonNullSlotUnwrap)
    final optionRenderedLocals:Map<Int, Bool> = [];
    // The initializer text each local's declaration emitted, keyed by
    // local id. The parsed shape of this text is the type account every
    // slot boundary reads. (DeclShapeRecord)
    final declInitTexts:Map<Int, String> = [];
    final declShapeCache:Map<Int, RustShape> = [];
    // Subset of nullableCollapsedLocals whose null-coalescing initializer
    // actually renders a non-null value (both guarded-match arms are
    // non-null), so an Option parameter must re-wrap the read in Some. A
    // collapsed local whose null arm stays null renders as Option and must
    // not be re-wrapped.
    final nonNullRenderedLocals:Map<Int, Bool> = [];
    // String.indexOf lowers to an expression that always yields i32; a local
    // initialized from it keeps that domain even where Int maps to u32.
    final i32Locals:Map<Int, Bool> = [];
    // True while rendering the initializer of an i32-domain local, so the
    // wrapping arithmetic in it picks the i32 domain and the binding infers
    // i32; wrapping arithmetic is bit-identical on both domains, so the
    // choice is safe anywhere inside the initializer.
    var i32ComparisonTarget = false;
    var i32InitializerTarget = false;
    // Locals whose declaration renders an i32 binding (a wrapping-binop
    // initializer under i32InitializerTarget, or a String.indexOf result).
    // Assignments to them keep the i32 target override; every other
    // i32-domain local binds u32 (a constant or u32-source initializer)
    // and its assignments must render in the binding's u32 domain.
    final i32BindingLocals:Map<Int, Bool> = [];
    // Int locals whose declaration renders in the business u32 domain (a
    // constant or u32-source initializer). The comparison sentinel
    // heuristic consults this declaration fact so a signed-looking
    // comparison cannot override a u32 binding; a countdown loop variable
    // (decremented under a `>= 0` guard) stays eligible for the signed
    // domain because its loop exits only when the value goes negative.
    final declaredUnsignedIntLocals:Map<Int, Bool> = [];
    // Countdown loop variables whose guard is `>= 0` with a non-unit step
    // (transformCountdownLoops only shifts unit steps): the loop exits
    // when the value goes negative, so the signed domain is required even
    // though the declaration renders u32.
    final signedCountdownVars:Map<Int, Bool> = [];
    // Downward loops the renderer shifts to an unsigned guard
    // (transformCountdownLoops): their variable keeps the u32 domain.
    final countdownShiftedVars:Map<Int, Bool> = [];
    /** Locals whose declared Haxe type is non-null but whose initializer
        is nullable. A collection `.get()` or similar call returns Null<T>,
        and the local is typed as T; its Rust storage is still Option<T> and
        its null guard must be detected by nullGuardOf. Covers the
        implicit-nullable-local family. **/
    final implicitNullableLocals:Map<Int, Bool> = [];
    // Locals initialized to a null literal (TConst(TNull)) whose declared
    // Haxe type is non-null. Their Rust storage is Option<T> but the
    // assignment path must wrap non-null RHS values in Some(...). Covers
    // the null-initialized local assignment wrapping family.
    final noneInitializedLocals:Map<Int, Bool> = [];
    // Active `map.has(key)` statement guards; a local initialized from
    // `map.get(key)` under the guard holds the inner value (the has guard
    // proved presence). Covers the has-guarded get local family.
    final hasGuardedGets:Array<{subj:String, key:String}> = [];
    // Locals initialized from a has-guarded get ternary (`map.has(k) ?
    // map.get(k) : value`); the initializer renders the inner value, so
    // arithmetic operands must not re-apply the unwrap_or forcing read.
    final hasGuardedTernaryLocals:Map<Int, Bool> = [];
    final declaredNullableLocals:Map<Int, Bool> = [];
    // Keep Option when Haxe code observes null separately from code point zero.
    final nullableSensitiveLocals:Map<Int, Bool> = [];
    // Locals initialized from Std.parseInt hold the i32 parse domain. The
    // push renderer reinterprets them at the business u32 element boundary.
    final parseIntLocals:Map<Int, Bool> = [];
    final fpInt64Halves:Map<Int, Bool> = [];
    var hiddenCounter:Int = 0;

    public function new(imports:RustImports, types:RustType, state:RustEmissionState) {
        this.imports = imports;
        this.types = types;
        this.state = state;
    }

    public function setArgType(name:String, typeName:String):Void {
        argTypes.set(name, typeName);
    }

    public function setReturnUnsigned(value:Bool):Void {
        this.returnUnsigned = value;
    }

    public function setReturnTypeName(value:Null<String>):Void {
        this.returnTypeName = value;
    }

    public function setReturnType(value:Null<Type>):Void {
        this.currentReturnType = value;
    }

    public function reserveName(name:String):Void {
        usedNames.set(name, true);
    }

    public function bindLocalName(v:TVar, name:String):Void {
        subst.set(v.id, name);
    }

    public function boundNameOf(v:TVar):Null<String> {
        return subst.get(v.id);
    }

    public function setFallible(value:Bool, errorType:Null<String> = null, overflowVariant:Null<String> = null):Void {
        this.isFallible = value;
        this.errorTypeName = errorType != null ? errorType : state.errorName;
        this.declaredErrorTypeName = this.errorTypeName;
        // The overflow variant belongs to the resolved error enum; a function
        // owned by an enum without it reports the gap at the first capacity
        // expression that copies the foreign variant here.
        this.countOverflowVariant = overflowVariant;
        if (value && this.errorTypeName == null) {
            Context.error("fallible operation requires an error enum, but none found in AST", Context.currentPos());
        }
    }

    public function expressionOf(e:TypedExpr):String {
        return expr(e);
    }

    public function topLevelStatements(e:TypedExpr):String {
        scanLocals(e);
        scanLocalFunctionFallibility(e);
        return blockLines(statementsOf(e), 0).join("\n");
    }

    public function rawExpression(e:TypedExpr):String {
        return expr(e);
    }

    public function rawArrayLiteral(e:TypedExpr):String {
        return switch (stripWrap(e).expr) {
            case TArrayDecl(elements): renderArrayLiteralExpr(elements, false);
            case _: rawExpression(e);
        };
    }

    /** Renders the literal itself for a Rust static function pointer initializer. */
    public function rawFunctionInitializer(e:TypedExpr):String {
        return switch (stripWrap(e).expr) {
            case TFunction(f): functionLiteral(f, e.t);
            case _: fail(e, "static function fields accept capture-free initializers only");
        }
    }

    // ------------------------------------------------------------------
    // Function bodies
    // ------------------------------------------------------------------
    var currentMethodName:Null<String> = null;
    var currentClass:Null<ClassType> = null;
    var currentLocalName:Null<String> = null;
    /**
        The Rust binding that `this` lowers to in the current function body.
        Ordinary methods use `self`; a constructor that uses `this` as a value
        binds a mutable local (a fresh name, since `self` is a keyword and
        cannot be shadowed) and returns it.
    **/
    var thisBindingName:String = "self";

    function coalescingSiteFor(e:TypedExpr):Null<{parameter:String, defaultExpr:TypedExpr, valueExpr:TypedExpr}> {
        if (currentClass == null || currentMethodName == null)
            return null;
        final site = DefaultArgExpander.coalescingSite(e);
        if (site == null)
            return null;
        if (coalescingSiteValue(site) == null)
            return null;
        return site;
    }

    /** The registered coalescing default value for a site, or null when unregistered. */
    function coalescingSiteValue(site:Null<{parameter:String, defaultExpr:TypedExpr, valueExpr:TypedExpr}>):Null<DefaultArgExpander.CoalescingDefaultValue> {
        if (site == null || currentClass == null || currentMethodName == null)
            return null;
        return currentLocalName != null ? DefaultArgExpander.coalescingDefaultForLocalParam(currentClass, currentMethodName, currentLocalName,
            site.parameter) : DefaultArgExpander.coalescingDefaultForParam(currentClass, currentMethodName, site.parameter);
    }

    /** Renders the sanctioned expression in Rust's normalization closure. */
    public function coalescingDefaultText(value:DefaultArgExpander.CoalescingDefaultValue, targetType:Type, asOption:Bool = false, nested:Bool = false,
            inClosure:Bool = false):String {
        // Null conditionals already produce an Option-valued expression; their
        // branches must be rendered in that same domain. The whole conditional is not
        // wrapped in Some(...).
        if (asOption)
            switch (value) {
                case CNull:
                    return "None";
                case CConditional(c, t, f):
                    return "if " + coalescingDefaultText(c, targetType, false, nested, inClosure) + " { " + coalescingDefaultText(t, targetType, true, nested,
                        inClosure) + " } else { " + coalescingDefaultText(f, targetType, true, nested, inClosure) + " }";
                default:
            }
        final rendered = switch (value) {
            case CInt(v): isFloatType(targetType) ? intToFloatText(Std.string(v)) : Std.string(v);
            case CFloat(s):
                final padded = s.indexOf(".") >= 0 || s.indexOf("e") >= 0 || s.indexOf("E") >= 0 ? s : s + ".0";
                FloatPrecision.isF32() ? padded + "f32" : padded;
            case CString(s): quoteString(s) + (asOption || !nested ? ".to_string()" : "");
            case CBool(b): b ? "true" : "false";
            case CNull: "None";
            case CEmptyArray: "vec![]";
            case CEmptyMap:
                imports.require("std::collections::HashMap");
                "HashMap::new()";
            case CPositiveInfinity: FloatPrecision.isF32() ? "f32::INFINITY" : "f64::INFINITY";
            case CNegativeInfinity: FloatPrecision.isF32() ? "f32::NEG_INFINITY" : "f64::NEG_INFINITY";
            case CEnum(enumRef, enumField):
                final en = enumRef.get();
                requireEnum(en.module, en.name);
                en.name + "::" + enumField.name;
            case CParameterRead(name):
                if (defaultParameterSubstitutions.exists(name)) {
                    final sub = defaultParameterSubstitutions.get(name);
                    if (asOption && !StringTools.startsWith(sub, "Some(") && sub != "None") {
                        // An owned String slot receiving the substituted value
                        // owns its text; a literal or a reusable view converts
                        // once at the boundary.
                        if (isStringType(targetType) && !StringTools.endsWith(sub, ".to_string()")
                            && (isStringLiteralText(sub) || reusableReadText(sub)))
                            return "Some(" + sub + ".to_string())";
                        return "Some(" + sub + ")";
                    }
                    return asOption && isStringType(targetType) && isStringLiteralText(sub) ? sub + ".to_string()" : sub;
                } else if (name.indexOf(".") >= 0) coalescingStaticFieldText(name, targetType)
                else RustImports.toSnakeCase(name);
            case CInstanceFieldRead(name):
                final fieldText = "self." + RustImports.toSnakeCase(name);
                isTypeCopy(targetType) ? fieldText : "(" + fieldText + ").clone()";
            case CLocalRead(name): RustImports.toSnakeCase(name);
            case CFieldAccess(CParameterRead(staticPath), ""): coalescingStaticFieldText(staticPath, targetType);
            case CFieldAccess(receiver, fieldName):
                fieldName == "length" ? rustU32Length("(" + coalescingDefaultText(receiver,
                    targetType, false, nested, inClosure) + ").len()") : coalescingDefaultText(receiver, targetType, false, nested, inClosure) + "."
                    + RustImports.toSnakeCase(fieldName);
            case CMethodCall(receiver, methodName, args):
                // A String substring in a default-argument closure lowers
                // into the u_string runtime like the ordinary member-call
                // path: the bounds are UTF-16 units converted to byte
                // boundaries, and a borrowed &str receiver passes through
                // directly (E0599 substring on &str).
                if (methodName == "substring" || methodName == "sub_string") {
                    state.shimsUsed.set("std.UStringRT", true);
                    imports.require("crate::runtime::u_string");
                    final recv = coalescingDefaultText(receiver, targetType, false, nested, inClosure);
                    // The u_string runtime keeps i32 bounds (SIGNED_SHIM_PARAMS);
                    // a business u32 bound reinterprets its bits once at the
                    // boundary, matching the ordinary member-call lowering.
                    final from = coalescingSignedBound(args[0], targetType, nested, inClosure);
                    if (args.length < 2)
                        return "u_string::substring_from(" + recv + ", " + from + ")";
                    return "u_string::substring(" + recv + ", " + from + ", " + coalescingSignedBound(args[1], targetType, nested, inClosure) + ")";
                }
                coalescingDefaultText(receiver, targetType, false, nested, inClosure)
                + "."
                + rustMethodName(methodName)
                + "("
                + [for (a in args) coalescingDefaultText(a, targetType, false, nested, inClosure)].join(", ") + ")";
            case CStaticCall(modulePath, className, methodName, args):
                coalescingStaticCallText(modulePath, className, methodName, args, targetType, inClosure);
            case CConditional(c, t, f):
                "if "
                + coalescingDefaultText(c, targetType, false, nested, inClosure)
                + " { "
                + coalescingDefaultText(t, targetType, false, nested, inClosure)
                + " } else { "
                + coalescingDefaultText(f, targetType, false, nested, inClosure)
                + " }";
            case CBinaryOp(op, left, right):
                coalescingDefaultText(left, targetType, false, nested, inClosure)
                + " "
                + opStr(op)
                + " "
                + coalescingDefaultText(right, targetType, false, nested, inClosure);
            case CConstructorCall(modulePath, className, args):
                imports.requireType(modulePath, className);
                var constructed = className
                    + "::new("
                    + completeCoalescingCallArgs(modulePath, "new", args, targetType, true, className, true, inClosure).join(", ")
                    + ")";
                // A throwing constructor default resolves its Result before
                // the value enters the slot; the ordinary call path applies
                // the same unwrap through normalizeConstructorResult. Inside
                // an unwrap_or_else closure the closure returns the concrete
                // value, so `?` cannot propagate there.
                if (state.funcErrorEnums.exists(RustEmissionState.funcKey(modulePath, "new", false)))
                    constructed += inClosure ? ".unwrap()" : (isFallible ? "?" : ".unwrap()");
                // A concrete implementor default entering an interface slot
                // boxes through the same sanctioned construction the
                // ordinary call path uses; the interface default is
                // otherwise emitted bare and fails the dyn cast.
                if (isInterfaceType(targetType))
                    "Box::new(" + constructed + ")";
                else
                    constructed;
        };
        if (!asOption)
            return rendered;
        // A nullable slot owns its payload. A plain read (a local or field,
        // borrowed or owned) clones once at the boundary; a fresh literal or
        // call already owns and passes through. The emitter clones reusable
        // reads so a loop reuses each read.
        final inner = getNullInnerType(targetType);
        // An owned String slot receiving a reusable string view converts once
        // at the boundary so the Option owns its text.
        if (isStringType(inner) && reusableReadText(rendered) && !StringTools.endsWith(rendered, ".to_string()"))
            return "Some(" + rendered + ".to_string())";
        if (!isTypeCopy(inner) && !isStringType(inner) && reusableReadText(rendered)
            && !StringTools.endsWith(rendered, ".clone()")
            && !StringTools.endsWith(rendered, ".to_vec()"))
            return "Some(" + ownedNullableReadText(rendered) + ")";
        return "Some(" + rendered + ")";
    }

    /**
        A substring bound in a default-argument closure: the u_string runtime
        takes i32 bounds, so a business u32 field read reinterprets its bits
        once at the boundary (T5), matching the ordinary member-call
        lowering's castSignedI32. A literal folds to its signed value.
    **/
    function coalescingSignedBound(value:DefaultArgExpander.CoalescingDefaultValue, targetType:Type, nested:Bool, inClosure:Bool):String {
        final text = coalescingDefaultText(value, targetType, false, nested, inClosure);
        return switch (value) {
            case CInt(v): RustConversions.reinterpret(Std.string(v) + "u32", "i32");
            case CFieldAccess(_, _) | CParameterRead(_) | CLocalRead(_) | CInstanceFieldRead(_): RustConversions.reinterpret(text, "i32");
            case _: text;
        };
    }

    /** Explicit arguments plus the callee's omitted-parameter defaults; a rust signature carries no defaults. */
    function completeCoalescingCallArgs(modulePath:String, fieldName:String, args:Array<DefaultArgExpander.CoalescingDefaultValue>, targetType:Type,
            nested:Bool = false, ?className:String, nestedArg:Bool = false, inClosure:Bool = false):Array<String> {
        final rendered = [for (i in 0...args.length) coalescingDefaultText(args[i], coalescingCallArgType(modulePath, fieldName, i, className),
            isNullType(coalescingCallArgType(modulePath, fieldName, i, className)), nestedArg, inClosure)];
        final omitted = DefaultArgExpander.omittedCallDefaults(modulePath, fieldName, args.length, className);
        if (omitted != null) {
            for (o in omitted)
                rendered.push(coalescingDefaultText(o.value, o.type, isNullType(o.type), nestedArg, inClosure));
        }
        return rendered;
    }

    function coalescingCallArgType(modulePath:String, fieldName:String, index:Int, ?className:String):Null<Type> {
        try {
            final cls = if (className != null) switch (Context.getType(modulePath + "." + className)) {
                case TInst(ref, _): ref.get();
                default: null;
            } else switch (Context.getType(modulePath)) {
                case TInst(ref, _): ref.get();
                default: null;
            };
            if (cls != null) {
                final ft = fieldName == "new" && cls.constructor != null ? cls.constructor.get().type : null;
                if (ft != null) switch (Context.follow(ft)) {
                    case TFun(values, _) if (index < values.length): return values[index].t;
                    default:
                }
            }
        } catch (_:Dynamic) {}
        return null;
    }

    function coalescingStaticCallText(modulePath:String, className:String, methodName:String, args:Array<DefaultArgExpander.CoalescingDefaultValue>,
            targetType:Type, inClosure:Bool = false):String {
        if (modulePath == "std.SortedMap" && methodName == "builder") {
            // The omitted map default carries its key and value types on
            // the receiving parameter, so the builder binds the same
            // comparator the direct call path binds (stdlib/07).
            final followed = Context.follow(getNullInnerType(targetType));
            final keyType = switch (followed) {
                case TInst(_, params) if (params.length > 0): params[0];
                case _: null;
            };
            final valueType = switch (followed) {
                case TInst(_, params) if (params.length > 1): params[1];
                case _: null;
            };
            imports.requireType("runtime.SortedTable", "SortedTable");
            final comparator = sortedComparator(keyType, Context.currentPos());
            return "SortedTable::sorted_table_map_builder::<" + types.of(keyType) + ", " + types.of(valueType) + ">(" + comparator + ")";
        }
        if (modulePath == "std.SortedSet" && methodName == "builder") {
            imports.requireType("runtime.SortedTable", "SortedTable");
            return "SortedTable::sorted_table_set_builder(" + [for (a in args) coalescingDefaultText(a, targetType, false, false, inClosure)].join(", ") + ")";
        }
        imports.requireType(modulePath, className);
        var rendered = className
            + "::"
            + (RustImports.isShimModule(modulePath) ? RustImports.toSnakeCase(methodName) : RustImports.toSnakeCase(className + "_" + methodName))
            + "("
            + completeCoalescingCallArgs(modulePath, methodName, args, targetType, false, className, false, inClosure).join(", ")
            + ")";
        // A throwing static default resolves its Result before the value
        // enters the slot, mirroring the constructor default handling.
        // Inside an unwrap_or_else closure the closure returns the concrete
        // value, so `?` cannot propagate there.
        if (state.funcErrorEnums.exists(RustEmissionState.funcKey(modulePath, methodName, true)))
            rendered += inClosure ? ".unwrap()" : (isFallible ? "?" : ".unwrap()");
        return rendered;
    }

    function coalescingStaticFieldText(path:String, targetType:Type):String {
        final parts = path.split(".");
        if (parts.length < 2)
            return path;
        final fieldName = parts[parts.length - 1];
        final typePath = parts.slice(0, parts.length - 1).join(".");
        try {
            switch (Context.getType(typePath)) {
                case TInst(clsRef, _):
                    final cls = clsRef.get();
                    // A self-construction singleton static emits as a
                    // module-scope Mutex guard, so a coalescing default
                    // referencing it must open the guard exactly like an
                    // ordinary field read. The staticRef path would
                    // otherwise name it as an associated item
                    // (`Fill::FILL_INSTANCE`) that the emitted module-scope
                    // static does not provide.
                    if (isGuardStaticField(cls, fieldName)) {
                        final value = staticGuardClone(cls, fieldName);
                        // A concrete singleton entering an interface slot boxes
                        // through the sanctioned construction, so the
                        // unwrap_or_else closure returns the boxed trait object
                        // its Option payload declares.
                        final field = staticFieldOf(cls, fieldName);
                        return isInterfaceSlotType(targetType) && (field == null || !isInterfaceType(field.type))
                            ? "Box::new(" + value + ")" : value;
                    }
                    // A construction or lazy-array static is emitted as a
                    // LazyLock; the coalescing default must deref and clone
                    // the referent the same way field() renders a static
                    // read, never reference the LazyLock itself.
                    final lazyRead = lazyStaticRead(cls, fieldName);
                    if (lazyRead != null) {
                        // A concrete singleton entering an interface slot boxes
                        // through the sanctioned construction, so the
                        // unwrap_or_else closure returns the boxed trait object
                        // its Option payload declares.
                        final field = staticFieldOf(cls, fieldName);
                        return isInterfaceSlotType(targetType) && (field == null || !isInterfaceType(field.type))
                            ? "Box::new(" + lazyRead + ")" : lazyRead;
                    }
                    final rendered = staticRef(cls, fieldName);
                    // A direct array static lowers to a Rust array, while an
                    // owned Vec slot needs the slice copied into a Vec. The
                    // nullable coalescing boundary owns its storage.
                    if (isOwnedVecType(getNullInnerType(targetType)) || isOwnedVecType(targetType)) {
                        final field = staticFieldOf(cls, fieldName);
                        if (field != null && isDirectArrayStaticField(field))
                            return rendered + ".to_vec()";
                    }
                    return isStringType(targetType)
                        && !StringTools.endsWith(rendered, ".to_string()") ? rendered + ".to_string()" : rendered;
                case TAbstract(absRef, _) if (ValueTypeSupport.isMarkedAbstract(absRef.get())):
                    final abs = absRef.get();
                    final member = ValueTypeSupport.memberField(abs, fieldName);
                    if (member == null)
                        return fieldName;
                    imports.requireType(abs.module, abs.name);
                    final isConst = valueTypeStaticIsConst(member);
                    final rendered = abs.name + "::" + (isConst ? RustImports.toScreamingSnakeCase(fieldName) : RustImports.toSnakeCase(fieldName));
                    final memberValue = isConst ? rendered : rendered + "()";
                    return isStringType(targetType) ? memberValue + ".to_string()" : memberValue;
                case TAbstract(absRef, _):
                    final abs = absRef.get();
                    imports.requireType(abs.module, abs.name);
                    final rendered = abs.name + "::" + RustImports.toScreamingSnakeCase(fieldName);
                default:
            }
        } catch (_:Dynamic) {}
        // Abstract implementations are represented as TInst at some typed
        // sites, but the original dotted path still identifies the abstract.
        final parts = typePath.split(".");
        if (parts.length > 0) {
            try {
                switch (Context.getType(typePath)) {
                    case TAbstract(absRef, _) if (ValueTypeSupport.isMarkedAbstract(absRef.get())):
                        final abs = absRef.get();
                        if (ValueTypeSupport.memberField(abs, fieldName) != null) {
                            imports.requireType(abs.module, abs.name);
                            return abs.name + "::" + RustImports.toScreamingSnakeCase(fieldName);
                        }
                    default:
                }
            } catch (_:Dynamic) {}
        }
        return path;
    }

    static function rustMethodName(name:String):String {
        return name == "toUpperCase" ? "to_uppercase" : RustImports.toSnakeCase(name);
    }

    static function opStr(op:Binop):String {
        return switch (op) {
            case OpAdd: "+";
            case OpMult: "*";
            case OpDiv: "/";
            case OpMod: "%";
            case OpEq: "==";
            case OpNotEq: "!=";
            case OpLt: "<";
            case OpLte: "<=";
            case OpGt: ">";
            case OpGte: ">=";
            case OpBoolAnd: "&&";
            case OpBoolOr: "||";
            case OpShl: "<<";
            case OpShr: ">>";
            case OpUShr: ">>";
            case OpXor: "^";
            case _: "?";
        };
    }

    public function functionBody(cls:ClassType, f:ClassFuncData):Array<String> {
        if (f.expr == null) {
            Context.error("function field has no body to lower", f.field.pos);
        }
        DefaultArgExpander.completeRootExprForRust(cls, f.field.name, f.expr);
        LoopCounterGuard.prepare(f.expr);
        PipelineExpander.expandRootExpr(f.expr);
        EnumQueryExpander.expandRootExpr(f.expr);
        currentClass = cls;
        currentMethodName = f.field.name;
        currentLocalName = null;
        paramVarIds.clear();
        borrowedLoopVarIds.clear();
        unsignedLocals.clear();
        nullableCollapsedLocals.clear();
        optionRenderedLocals.clear();
        declInitTexts.clear();
        declShapeCache.clear();
        nonNullRenderedLocals.clear();
        implicitNullableLocals.clear();
        hasGuardedGets.resize(0);
        hasGuardedTernaryLocals.clear();
        declaredNullableLocals.clear();
        noneInitializedLocals.clear();
        nullableSensitiveLocals.clear();
        parseIntLocals.clear();
        i32Locals.clear();
        i32BindingLocals.clear();
        declaredUnsignedIntLocals.clear();
        signedCountdownVars.clear();
        countdownShiftedVars.clear();
        mutated.clear();
        deferredLocals.clear();
        for (a in f.args) {
            if (a.tvar != null)
                paramVarIds.set(a.tvar.id, true);
        }
        // Fuse declaration-plus-assignment pairs before the mutation scan.
        // The typer lowers abstract-inline receiver bindings as `TVar(v,
        // null)` followed by an assignment; the fused initializer is the
        // declaration's own initialization, so the scan must not read it as
        // a reassignment.
        final fusedRoot = fuseWithin(f.expr);
        f.expr.expr = fusedRoot.expr;
        scanLocals(f.expr);
        scanSharedClosureArrays(f.expr);
        scanSharedClosureScalars(f.expr);
        scanPushedThenRead(f.expr);
        bareValueBuilders.clear();
        bareValueBuilderPos.clear();
        builtBareTables.clear();
        fieldNullGuards.clear();
        branchArmMoveReadsAfter.clear();
        unusedLocalIds.clear();
        scanBuilderValueNullability(f.expr);
        scanBranchArmMoves(f.expr);
        scanUnusedLocals(f.expr);
        scanContinueNullGuards(f.expr);
        scanCursorLocals(f.expr);
        scanLocalFunctionFallibility(f.expr);
        scanReadsAfter(f.expr);
        final previousReceiverContext = renderingMethodReceiver;
        renderingMethodReceiver = RustDecl.methodWritesReceiver(f.field);
        final lines = blockLines(statementsOf(f.expr), 1, true);
        final normalized = coalescingNormalizationLines(f.expr, 1, [for (a in f.args) a.name]);
        renderingMethodReceiver = previousReceiverContext;
        return normalized.concat(lines);
    }

    /** Body lowering for a member declared on a value wrapper. */
    public function valueTypeFunctionBody(cls:ClassType, f:ClassFuncData, receiverName:String):Array<String> {
        final abs = ValueTypeSupport.markedAbstractOfClass(cls);
        final op = abs == null ? null : ValueTypeSupport.operatorOf(abs, f.field);
        if (op != null) {
            switch (op) {
                case Binary(_):
                    if (f.args.length > 0)
                        bindLocalName(f.args[0].tvar, "self.0");
                    if (f.args.length > 1)
                        bindLocalName(f.args[1].tvar, "rhs.0");
                case Unary(_):
                    if (f.args.length > 0)
                        bindLocalName(f.args[0].tvar, "self.0");
            }
        } else if (ValueTypeSupport.hasReceiver(f.field) && f.args.length > 0) {
            bindLocalName(f.args[0].tvar, receiverName);
        }
        final rawReturn = types.of(f.ret, false);
        setReturnUnsigned(rawReturn == "u32");
        setReturnTypeName(rawReturn);
        return functionBody(cls, f);
    }

    /** Drops Haxe's synthetic representation assignment from a validating constructor. */
    public function valueTypeConstructorBody(cls:ClassType, f:ClassFuncData):Array<String> {
        if (f.expr == null)
            Context.error("value type constructor has no body to lower", f.field.pos);
        DefaultArgExpander.completeRootExprForRust(cls, f.field.name, f.expr);
        LoopCounterGuard.prepare(f.expr);
        PipelineExpander.expandRootExpr(f.expr);
        EnumQueryExpander.expandRootExpr(f.expr);
        currentClass = cls;
        currentMethodName = f.field.name;
        currentLocalName = null;
        paramVarIds.clear();
        unsignedLocals.clear();
        mutated.clear();
        for (a in f.args)
            if (a.tvar != null)
                paramVarIds.set(a.tvar.id, true);
        scanLocals(f.expr);
        scanLocalFunctionFallibility(f.expr);
        final out:Array<String> = [];
        for (stmt in statementsOf(f.expr)) {
            if (ValueTypeSupport.isThisDeclaration(stmt) || ValueTypeSupport.isThisAssignment(stmt) || ValueTypeSupport.isThisReturn(stmt))
                continue;
            for (line in stmtLines(stmt, 1))
                out.push(line);
        }
        return out;
    }

    /**
        Constructor body classification (feature spec 27): a `this.f = f`
        assignment of a constructor parameter is the struct-literal
        shorthand and drops out; an assignment to a field the constructor
        does not receive as a parameter is that field's initialization in
        the literal; every other statement keeps statement form and
        renders before the literal, so constructor validation survives on
        this target.
    **/
    public function constructorBody(cls:ClassType, f:ClassFuncData):{statementLines:Array<String>, fieldInits:Map<String, String>, thisAsValue:Bool, thisBindingName:String} {
        if (f.expr == null) {
            Context.error("constructor has no body to lower", f.field.pos);
        }
        DefaultArgExpander.completeRootExprForRust(cls, f.field.name, f.expr);
        LoopCounterGuard.prepare(f.expr);
        PipelineExpander.expandRootExpr(f.expr);
        EnumQueryExpander.expandRootExpr(f.expr);
        currentClass = cls;
        currentMethodName = f.field.name;
        currentLocalName = null;
        paramVarIds.clear();
        unsignedLocals.clear();
        mutated.clear();
        for (a in f.args) {
            if (a.tvar != null)
                paramVarIds.set(a.tvar.id, true);
        }
        final fusedRoot = fuseWithin(f.expr);
        f.expr.expr = fusedRoot.expr;
        scanLocals(f.expr);
        scanLocalFunctionFallibility(f.expr);
        final argNames = [for (a in f.args) a.name];
        final fieldInits = new Map<String, String>();
        final fallbackBindings:Array<String> = [];
        final fallbackBoundFields:Map<String, Bool> = [];
        final fallbackVars:Map<String, TVar> = [];
        // Assignments nested in the constructor body cannot become struct
        // literal initializers.  Treat their fields as locals for the whole
        // constructor instead; the Haxe constructor's control flow is trusted
        // to assign the final field on every path.
        final branchAssignedFields:Map<String, Bool> = [];
        final stmts:Array<TypedExpr> = [];
        for (stmt in statementsOf(f.expr)) {
            // Rust has no class inheritance: a Haxe constructor super call
            // has no callable Rust equivalent. The enclosing data-class
            // constructor is hand-rolled, so consume the call; emitting Rust's
            // module-path keyword as a function is invalid.
            switch (stmt.expr) {
                case TCall({expr: TConst(TSuper)}, _):
                    continue;
                case TBinop(OpAssign, target, value):
                    switch (stripWrap(target).expr) {
                        case TField({expr: TConst(TThis)}, FInstance(_, _, cf)):
                            final fieldName = cf.get().name;
                            final coalescing = coalescingSiteFor(value);
                            if (coalescing != null) {
                                // A non-null default narrows the stored field
                                // through coalescingParameterType. Render the
                                // initializer at that same storage boundary so
                                // a String default does not retain Option
                                // wrapping after the declaration narrows it.
                                final registered = DefaultArgExpander.coalescingDefaultForParam(cls, f.field.name, coalescing.parameter);
                                final fieldStorageType = registered != null
                                    ? DefaultArgExpander.coalescingParameterType(registered, cf.get().type)
                                    : cf.get().type;
                                fieldInits.set(fieldName, renderValueForType(fieldStorageType, value, expr(value)));
                                continue;
                            }
                            final paramLocal = switch (stripWrap(value).expr) {
                                case TLocal(v) if (argNames.indexOf(v.name) >= 0): v;
                                case _: null;
                            };
                            // The parameter name is a local binding. It is not necessarily the
                            // target field name (Haxe permits constructor shorthand such
                            // as `owner = o`). Preserve the typed field assignment so the
                            // declaration pass can emit the real Rust field name.
                            // A like-named parameter (this.x = x) records nothing: the
                            // declaration-side initializer branches own its conversions
                            // (String borrow, recursive-class Box wrap, shorthand move).
                            if (paramLocal == null || RustImports.toSnakeCase(paramLocal.name) != RustImports.toSnakeCase(fieldName)) {
                                fieldInits.set(fieldName, renderValueForType(cf.get().type, value, expr(value)));
                            }
                        case _:
                            stmts.push(stmt);
                    }
                case _:
                    stmts.push(stmt);
            }
        }
        final thisFieldArgs:Map<String, TVar> = [];
        for (a in f.args) {
            if (a.tvar != null)
                thisFieldArgs.set(RustImports.toSnakeCase(a.name), a.tvar);
        }
        // Nested assignments stay as statements, but their fields use a local
        // slot so the final Self literal can consume the value.
        function collectNestedFieldAssignments(node:TypedExpr, root:Bool = true):Void {
            if (node == null)
                return;
            switch (node.expr) {
                case TBinop(OpAssign, target, _):
                    switch (stripWrap(target).expr) {
                        case TField({expr: TConst(TThis)}, FInstance(_, _, cf)) if (!root):
                            branchAssignedFields.set(cf.get().name, true);
                        case _:
                    }
                case _:
            }
            TypedExprTools.iter(node, child -> collectNestedFieldAssignments(child, false));
        }
        for (stmt in stmts)
            collectNestedFieldAssignments(stmt);

        function defaultConstructorFieldValue(t:Type):Null<String> {
            return switch (Context.follow(t)) {
                case TAbstract(a, _) if (a.get().name == "Bool"): "false";
                case TAbstract(a, _) if (a.get().name == "Int"): "0";
                case TAbstract(a, _) if (a.get().name == "Float"): "0.0";
                case TInst(c, _) if (c.get().name == "String"): "String::new()";
                case TAbstract(a, _) if (a.get().name == "Null"): "None";
                case TType(_, _): null;
                case _: null;
            };
        }
        // A branch-assigned field keeps a local slot for the tail struct
        // literal. The slot must not reuse a parameter name, so a null check
        // on that parameter still reads the optional parameter. A field with
        // no literal default declares its Rust type and lets the branch
        // assignments initialize it.
        function fallbackBindingDecl(bindingName:String, t:Type):String {
            final value = defaultConstructorFieldValue(t);
            return value != null ? "let mut " + bindingName + " = " + value + ";" : "let mut " + bindingName + ": " + types.of(t, false) + ";";
        }
        function fallbackBindingName(fieldName:String):String {
            final snake = RustImports.toSnakeCase(fieldName);
            for (a in f.args)
                if (RustImports.toSnakeCase(a.name) == snake)
                    // Declarations, branch writes, and the tail Self literal
                    // render this slot through different paths; collapsing
                    // here keeps all three on one identifier.
                    return RustImports.collapseUnderscores("__field_" + snake);
            return snake;
        }
        for (fieldName in branchAssignedFields.keys()) {
            var field:Null<ClassField> = null;
            for (candidate in cls.fields.get())
                if (candidate.name == fieldName) {
                    field = candidate;
                    break;
                }
            if (field == null)
                continue;
            final bindingName = fallbackBindingName(fieldName);
            fallbackBindings.push(fallbackBindingDecl(bindingName, field.type));
            fallbackBoundFields.set(fieldName, true);
            fieldInits.set(fieldName, bindingName);
            fallbackVars.set(fieldName, {
                id: -1000000 - fallbackBindings.length,
                name: bindingName,
                t: field.type,
                capture: false,
                extra: null,
                meta: null,
                isStatic: false
            });
        }

        function bindThisFieldReads(node:TypedExpr, assignmentTarget:Bool = false):Void {
            if (node == null)
                return;
            switch (node.expr) {
                case TField({expr: TConst(TThis)}, FInstance(_, _, cf)) if ((!assignmentTarget || branchAssignedFields.exists(cf.get().name)) && cf.get().kind.match(FieldKind.FVar(_))):
                    final fieldName = RustImports.toSnakeCase(cf.get().name);
                    // A branch-assigned field takes its value from the fallback
                    // slot; a like-named parameter must not capture the read.
                    final local = branchAssignedFields.exists(cf.get().name) ? null : thisFieldArgs.get(fieldName);
                    if (local == null) {
                        // A non-parameter field assignment is emitted in the tail
                        // Self literal. Bind that same initializer before the
                        // validation statements so reads do not become `self.*`
                        // in the associated constructor function.
                        if (!fieldInits.exists(cf.get().name) && !branchAssignedFields.exists(cf.get().name))
                            Context.error("unsupported this-field read in data-class constructor: field has no initializer [" + cf.get().name + "]", node.pos);
                        final bindingName = fallbackBindingName(cf.get().name);
                        if (!fallbackBoundFields.exists(cf.get().name)) {
                            final initialValue = branchAssignedFields.exists(cf.get().name)
                                ? defaultConstructorFieldValue(cf.get().type)
                                : fieldInits.get(cf.get().name);
                            if (initialValue != null)
                                fallbackBindings.push("let mut " + bindingName + " = " + initialValue + ";");
                            else
                                fallbackBindings.push(fallbackBindingDecl(bindingName, cf.get().type));
                            fallbackBoundFields.set(cf.get().name, true);
                            fieldInits.set(cf.get().name, bindingName);
                        }
                        final binding = fallbackVars.exists(cf.get().name) ? fallbackVars.get(cf.get().name) : {
                            id: -1000000 - fallbackBindings.length,
                            name: bindingName,
                            t: cf.get().type,
                            capture: false,
                            extra: null,
                            meta: null,
                            isStatic: false
                        };
                        if (!fallbackVars.exists(cf.get().name))
                            fallbackVars.set(cf.get().name, binding);
                        node.expr = TLocal(binding);
                    } else {
                        node.expr = TLocal(local);
                    }
                case TBinop(OpAssign, target, value):
                    bindThisFieldReads(target, true);
                    bindThisFieldReads(value);
                    return;
                case _:
            }
            TypedExprTools.iter(node, child -> bindThisFieldReads(child));
        }
        for (stmt in stmts)
            bindThisFieldReads(stmt);
        // A constructor body that uses `this` as a value (an instance-method
        // receiver or a bare assignment target) has no `self` in the static
        // `new()` function. The caller then emits a mutable local (a fresh
        // name, since `self` is a keyword and cannot be shadowed), runs the
        // body against it, and returns it.
        var thisAsValue = false;
        function scanThisValue(node:TypedExpr):Void {
            if (node == null || thisAsValue)
                return;
            // bindThisFieldReads already rewrote every `this.field` FVar
            // read to a local or parameter. Any `TThis` that survives is a
            // method receiver or a bare value, both of which need the local.
            if (node.expr.match(TConst(TThis)))
                thisAsValue = true;
            else
                TypedExprTools.iter(node, child -> scanThisValue(child));
        }
        for (stmt in stmts)
            scanThisValue(stmt);
        final bindingName = thisAsValue ? freshRegionName("__self") : "self";
        final previousThisBinding = thisBindingName;
        thisBindingName = bindingName;
        // tailScope stays off: the constructor's tail is the Ok(Self { ... })
        // literal assembled by the caller, so blockLines must not append the
        // fallible void closer `Ok(())` after the validation statements.
        final lines = stmts.length > 0 ? blockLines(stmts, 1, false) : [];
        final normalized = coalescingNormalizationLines(f.expr, 1, [for (a in f.args) a.name]);
        thisBindingName = previousThisBinding;
        return {statementLines: normalized.concat(fallbackBindings).concat(lines), fieldInits: fieldInits, thisAsValue: thisAsValue, thisBindingName: bindingName};
    }

    function coalescingNormalizationLines(root:TypedExpr, depth:Int, parameterOrder:Null<Array<String>> = null):Array<String> {
        final out:Array<String> = [];
        if (currentClass == null || currentMethodName == null)
            return out;
        final sites = DefaultArgExpander.coalescingSitesForFunction(root);
        if (parameterOrder != null) {
            var next = 0;
            for (parameterName in parameterOrder) {
                var found = next;
                while (found < sites.length && sites[found].parameter != parameterName) {
                    found++;
                }
                if (found < sites.length) {
                    final site = sites[found];
                    sites[found] = sites[next];
                    sites[next] = site;
                    next++;
                }
            }
        }
        final seen:Map<String, Bool> = [];
        for (site in sites) {
            if (parameterOrder != null && parameterOrder.indexOf(site.parameter) < 0)
                continue;
            final value = currentLocalName != null ? DefaultArgExpander.coalescingDefaultForLocalParam(currentClass, currentMethodName, currentLocalName,
                site.parameter) : DefaultArgExpander.coalescingDefaultForParam(currentClass, currentMethodName, site.parameter);
            if (value == null)
                continue;
            if (seen.exists(site.parameter)) {
                continue;
            }
            seen.set(site.parameter, true);
            // Optional parameters whose default is null may be typed by the
            // Haxe typer as the already-unwrapped payload at this site.  The
            // default value is authoritative: null defaults retain the
            // Option and avoid calling unwrap_or_else with a None payload.
            final defaultIsNull = containsNullDefault(value);
            final rawDefaultText = value != null ? coalescingDefaultText(value, DefaultArgExpander.withoutNull(site.valueExpr.t),
                defaultIsNull, false, true) : expr(site.defaultExpr);
            // When a string parameter read appears inside unwrap_or_else, Rust needs
            // the owned form (&str → String).
            final isStringDefault = switch (value) {
                case CParameterRead(_): isStringType(DefaultArgExpander.withoutNull(site.valueExpr.t));
                default: false;
            };
            final defaultText = isStringDefault ? rawDefaultText + ".to_string()" : rawDefaultText;
            final combinator = defaultIsNull ? ".or_else(|| " : ".unwrap_or_else(|| ";
            // The rebound parameter only needs mutability when the body
            // assigns it again or a try block captures an assignment; the
            // same condition as plain local declarations.
            final paramVar = switch (stripWrap(site.valueExpr).expr) {
                case TLocal(v): v;
                case _: null;
            };
            final bindingKw = paramVar != null
                && (mutated.exists(paramVar.id) || tryCapturedAssignments.exists(paramVar.id)) ? "let mut " : "let ";
            out.push(indent(depth) + bindingKw + RustImports.toSnakeCase(site.parameter) + " = " + RustImports.toSnakeCase(site.parameter) + combinator
                + defaultText + ");");
        }
        return out;
    }

    // ------------------------------------------------------------------
    // Statements
    // ------------------------------------------------------------------

    public function statementsOf(e:TypedExpr):Array<TypedExpr> {
        return PolicyQueries.statementsOf(e);
    }

    function stmtLines(e:TypedExpr, depth:Int):Array<String> {
        switch (e.expr) {
            case TVar(v, init) if (init != null && isTryRegion(init)):
                return regionInitializerLines(v, stripWrap(init), depth);
            case TVar(v, init) if (init != null):
                // A for-shared binding's declaration is shadowed dead code:
                // the loop declares its own binding. (ForSharedBindingDeclaration)
                if (forSharedLocals.exists(v.id))
                    return [];
                // A declaration adopted as a counted loop's counter renders
                // bare: the emitted `for` rebinds and the loop's increment
                // disappears into the stride, so no write reaches it.
                // (IntervalCounterMut)
                final isMut = (mutated.exists(v.id) || tryCapturedAssignments.exists(v.id))
                    && !intervalCounterLocals.exists(v.id);
                final kw = isMut ? "let mut" : "let";
                final raw = RustImports.toSnakeCase(localName(v));
                final name = unusedLocalIds.exists(v.id) ? "_" + raw : raw;
                // A Null<T> declared local keeps Option storage at runtime
                // even when a guard narrows a later read's Haxe type to T;
                // record it so &str/&T slots unwrap the wrapper before the
                // method call; calling on Option would fail (E0599).
                if (isNullType(v.t))
                    declaredNullableLocals.set(v.id, true);
                final explicitType = if (isFunctionType(v.t)) {
                    final isStaticRef = switch (stripWrap(init).expr) {
                        case TField(_, FStatic(_, _)): true;
                        case _: false;
                    };
                    final localError = fallibleLocalFunctionErrors.get(v.id);
                    // Static method pointers are 'static; the trait-object
                    // lifetime does not need the elided '_ that only binds
                    // to an enclosing reference parameter.
                    localError != null
                        ? ": " + types.functionReturnOfFallible(v.t, localError)
                        : ": " + (isStaticRef ? types.of(v.t, false) : types.functionReturnOf(v.t));
                } else if (isNullType(v.t) && isInterfaceType(flattenNullable(v.t))) {
                    // A nullable interface local needs its Option trait
                    // object type before conditional inference runs. The
                    // declared type renders from the flattened inner type so
                    // a double-wrapped join carries exactly one Option
                    // layer. (DoubleNullableFlatten)
                    ": Option<" + types.of(flattenNullable(v.t), false) + ">";
                } else switch (v.t) {
                    case TInst(c, _) if (c.get().isInterface):
                        // An interface local carries its boxed trait object
                        // type so every conditional arm coerces into it.
                        ": " + types.of(v.t, false);
                    case TInst(c, _)
                        if (c.get().name == "SortedMapBuilder" || c.get().name == "SortedMap" || c.get().name == "SortedSetBuilder"
                            || c.get().name == "SortedSet"):
                        // A bare-value builder (or the table it builds)
                        // drops the Option layer from its value parameter.
                        // (BuilderValueNullability)
                        ": "
                        + (bareValueBuilders.exists(v.id) || builtBareTables.exists(v.id)
                            ? stripLastValueOption(types.of(v.t, false))
                            : types.of(v.t, false));
                    case _: "";
                };
                var explicitNullableNone = false;
                // A local declared with a non-nullable type but initialized
                // from the path an enclosing null guard proves present holds
                // the inner value: Haxe implicitly unwraps at the
                // declaration. Render the initializer from the guard's match
                // binding so later field reads do not address the Option
                // itself.
                // Covers the guarded-copy local family.
                final narrowedCopy = switch (stripWrap(init).expr) {
                    case TLocal(_) | TField(_, _):
                        isNullType(init.t) && !isNullType(v.t) ? narrowedSubject(init) : null;
                    case _: null;
                };
                if (narrowedCopy != null) {
                    optionNarrowingHitCount++;
                    final inner = getNullInnerType(init.t);
                    final owned = isTypeCopy(inner) ? "*" + narrowedCopy : "(*" + narrowedCopy + ").clone()";
                    recordDeclInit(v, owned);
                    return [indent(depth) + kw + " " + name + explicitType + " = " + owned + ";"];
                }
                // A nullable-typed local copied from a nullable field/local
                // that an enclosing guard narrowed holds the inner value
                // (the match binding), with the Option wrapper removed. The local keeps its
                // Null<T> Haxe type but its Rust value is the plain struct;
                // mark it collapsed so later field reads do not apply the
                // as_ref forcing read (E0599 on a plain struct).
                // Covers the narrowed nullable-copy local family.
                if (isNullType(init.t) && isNullType(v.t)) {
                    final narrowedCopy2 = switch (stripWrap(init).expr) {
                        case TLocal(_) | TField(_, _): narrowedSubject(init);
                        case _: null;
                    };
                    if (narrowedCopy2 != null) {
                        optionNarrowingHitCount++;
                        final inner = getNullInnerType(init.t);
                        final owned = isTypeCopy(inner) ? "*" + narrowedCopy2 : "(*" + narrowedCopy2 + ").clone()";
                        recordDeclInit(v, owned);
                        nullableCollapsedLocals.set(v.id, true);
                        return [indent(depth) + kw + " " + name + explicitType + " = " + owned + ";"];
                    }
                }
                // A non-null declared type initialized from a nullable
                // expression keeps Option storage at runtime; its later null
                // guard must be recognized. Covers the implicit-nullable-local family.
                if (isNullType(init.t) && !isNullType(v.t))
                    implicitNullableLocals.set(v.id, true);
                // A non-null local initialized to null literal (TNull) keeps
                // Option<T> storage; later non-null assignments must wrap.
                if (isTNull(init) && !isNullType(v.t))
                    noneInitializedLocals.set(v.id, true);
                // A non-null declared type initialized to the null literal
                // also keeps Option storage (var x:T = null lowers to
                // Option<T>); its null comparisons and field reads must treat
                // it as nullable. Covers the null-initialized-local family.
                if (!isNullType(v.t) && switch (stripWrap(init).expr) {
                    case TConst(TNull): true;
                    case _: false;
                })
                    implicitNullableLocals.set(v.id, true);
                // A proven-non-null local (early-exit guard) copied into a
                // non-null declaration holds the inner value. The guard
                // proved the source is Some; the declaration owns the unwrapped
                // value directly so later reads do not address the Option.
                // Covers the proven-non-null owned copy family.
                if (!isNullType(v.t)) {
                    final provenText = provenNonNullOwnedText(init);
                    if (provenText != null) {
                        recordDeclInit(v, provenText);
                        return [indent(depth) + kw + " " + name + explicitType + " = " + provenText + ";"];
                    }
                }
                // A nullable-typed local copied from a proven-non-null local
                // holds the inner value (the early-exit guard proved the
                // source is Some). The local keeps its Null<T> Haxe type but
                // its Rust value is the plain scalar/struct; mark it
                // collapsed so later reads do not re-apply the as_ref forcing
                // read. Covers the proven-non-null nullable-copy family.
                if (isNullType(v.t) && !cursorLocals.exists(v.id)) {
                    final provenText = provenNonNullOwnedText(init);
                    if (provenText != null) {
                        recordDeclInit(v, provenText);
                        nullableCollapsedLocals.set(v.id, true);
                        return [indent(depth) + kw + " " + name + explicitType + " = " + provenText + ";"];
                    }
                }
                // A local initialized from `map.get(key)` under a matching
                // `map.has(key)` guard holds the inner value (the has guard
                // proved presence). The get renders as Option<T>; unwrap it
                // so the local owns the plain value, and mark it collapsed so
                // later reads do not re-apply the as_ref forcing read.
                // Covers the has-guarded get local family.
                if (isNullType(init.t) && hasGuardedGetLocal(init)) {
                    nullableCollapsedLocals.set(v.id, true);
                    recordDeclInit(v, "(" + expr(init) + ").unwrap()");
                    return [indent(depth) + kw + " " + name + explicitType + " = " + "(" + expr(init) + ").unwrap()" + ";"];
                }
                var initStr = switch (init.expr) {
                    case TFunction(fn):
                        localFunctionErrorName = fallibleLocalFunctionErrors.get(v.id);
                        final text = functionValueLiteralNamed(v.name, fn, init.t);
                        localFunctionErrorName = null;
                        text;
                    case TConst(TInt(value)) if (isIntType(v.t)):
                        // An i32-domain literal binding keeps the signed
                        // domain at later assignments, so the assignment
                        // boundary reinterprets an unsigned source.
                        if (i32Locals.exists(v.id))
                            i32BindingLocals.set(v.id, true);
                        integerBindingLiteral(value, v.id);
                    case TConst(TNull) if (isNullType(v.t)):
                        explicitNullableNone = true;
                        "None";
                    default:
                        // The initializer of an i32-domain local renders its
                        // wrapping arithmetic in i32 so the binding infers i32.
                        final wrapInit = i32Locals.exists(v.id) && switch (init.expr) {
                            case TBinop(OpAdd | OpSub | OpMult, _, _): isIntType(init.t) && !isNullType(init.t);
                            case _: false;
                        };
                        if (wrapInit) {
                            i32BindingLocals.set(v.id, true);
                            i32InitializerTarget = true;
                            final text = expr(init);
                            i32InitializerTarget = false;
                            text;
                        } else {
                            expr(init);
                        }
                };
                var nullableType = explicitType;
                if (explicitNullableNone && explicitType == "")
                    nullableType = ": " + types.of(v.t, false);
                // A non-null Haxe local initialized to the null literal
                // keeps Option<T> storage (noneInitializedLocals); the
                // declaration must name that storage or later Some(...)
                // assignments leave the inner type unconstrained (E0282).
                if (nullableType == "" && isTNull(init) && !isNullType(v.t))
                    nullableType = ": Option<" + types.of(v.t, false) + ">";
                initStr = renderValueForType(v.t, init, initStr);
                // A sunk initializer crossed an assignment boundary, so it
                // renders through the same numeric adaptation an assignment
                // applies; without it a signed rendering would reach the
                // unsigned declaration unchanged (E0308). (DeadConstantInitSink)
                if (sunkInitVarIds.exists(v.id))
                    initStr = numericAssignmentValue(v.t, init, initStr, i32BindingLocals.exists(v.id) ? "i32" : null, !i32Locals.exists(v.id));
                switch (stripWrap(init).expr) {
                    case TIf(cond, _, _) if (nullGuardOf(cond) != null):
                        // A null-coalescing ternary initializer materializes
                        // the inner value into the local, so later reads of
                        // the local must not re-apply the as_ref forcing read.
                        // Covers the null-coalescing ternary initializer family.
                        // A null-arm ternary (`x == null ? null : value`)
                        // keeps the Option shape (the None arm stays None),
                        // so only the non-null-arm form narrows to the inner
                        // value.
                        // A guarded match whose arms both render Some(...)
                        // keeps the Option storage (the nullableResult rule
                        // wrapped each arm), so the local is not collapsed
                        // and a method receiver on it still unwraps the
                        // wrapper.
                        final optionShapedMatch = initStr.indexOf("match &(") == 0 && initStr.indexOf("=> Some(") >= 0;
                        if (!optionShapedMatch && (StringTools.startsWith(initStr, "Some(")
                            || (initStr.indexOf("match") >= 0 && initStr.indexOf("None => None") < 0))) {
                            nullableCollapsedLocals.set(v.id, true);
                            nonNullRenderedLocals.set(v.id, true);
                        }
                        // A coalescing-shadow alias (`var x = p == null ? d : p`
                        // on a registered default parameter) renders as the
                        // normalized parameter read: the unwrap_or_else
                        // normalization line already materialized the plain
                        // value into the parameter's own binding, so the
                        // alias holds the inner value and later arithmetic
                        // operands must not re-apply the unwrap_or forcing
                        // read (E0599 on the bare scalar). A null default
                        // keeps the Option shape and stays uncollapsed.
                        // Covers the coalescing-shadow alias family.
                        final coalescingValue = coalescingSiteValue(coalescingSiteFor(init));
                        if (coalescingValue != null && !containsNullDefault(coalescingValue)) {
                            nullableCollapsedLocals.set(v.id, true);
                            nonNullRenderedLocals.set(v.id, true);
                        }
                    case TIf(cond, _, _) if (hasGuardGetInfo(cond) != null):
                        // A has-guarded get ternary initializer (`map.has(k) ?
                        // map.get(k) : value`) renders the inner value (the
                        // has guard proved presence), so the local holds the
                        // plain value; arithmetic operands must not re-apply
                        // the unwrap_or forcing read.
                        hasGuardedTernaryLocals.set(v.id, true);
                    case TField(subj, FInstance(_, _, cf)) | TField(subj, FAnon(cf)):
                        switch (stripWrap(subj).expr) {
                            case TLocal(item) if ((borrowedLoopVarIds.exists(item.id) || readsAfterDeclaration.exists(item.id))
                                && !isTypeCopy(cf.get().type)):
                                initStr += ".clone()";
                            case _:
                        }
                        // A non-Copy field of an owned vec type moved into a
                        // local consumes the field's storage and leaves later
                        // uses (such as .len() calls) dangling. Clone protects
                        // the source. Covers the for-loop field-move family (E0382).
                        if (isOwnedVecType(v.t) && !isTypeCopy(v.t) && !StringTools.endsWith(initStr, ".clone()"))
                            initStr = "(" + initStr + ").clone()";
                    case TLocal(source) if (!isTypeCopy(v.t) && readsAfterDeclaration.exists(source.id)):
                        initStr = "(" + initStr + ").clone()";
                    case _:
                }
                switch (stripWrap(init).expr) {
                    case TCall(fn, _) if (isStringCharCodeAt(fn)):
                        if (!nullableSensitiveLocals.exists(v.id)) {
                            // renderValueForType already applies this fallback for
                            // a nullable call entering a non-null declaration.
                            // Preserve the local's non-null state without duplication.
                            if (!StringTools.endsWith(initStr, ".unwrap_or(0)"))
                                initStr += ".unwrap_or(0)";
                            nullableCollapsedLocals.set(v.id, true);
                        }
                    case TCall(ifn, iargs) if (isStringIndexOf(ifn) && iargs.length >= 1 && isIntType(v.t) && !isNullType(v.t)):
                        i32Locals.set(v.id, true);
                        // The indexOf lowering renders an i32 binding
                        // (narrowI32 on the found offset, -1 for absent);
                        // later assignments to the local keep the i32
                        // target override so they do not diverge from the
                        // declaration's domain.
                        i32BindingLocals.set(v.id, true);
                    case _:
                }
                // A String local owns its value; a literal initializer is
                // a &str, so the empty literal declares String::new() and
                // any other literal converts once at the declaration.
                if (isStringType(v.t)) {
                    switch (stripWrap(init).expr) {
                        case TConst(TString(s)):
                            initStr = s.length == 0 ? "String::new()" : initStr + ".to_string()";
                        case _:
                    }
                }
                // A nullable local holds an Option; a non-null initializer
                // whose own type is not nullable is a bare value and wraps
                // in Some once at the declaration. Null literals took the
                // None branch above, already-nullable initializers (reads
                // of other nullable locals) stay as they are, and a
                // name-keyed enum lookup already emits from_name's Option.
                final lookupInit = EnumQueryExpander.markerKind(init) == QLookup;
                switch (stripWrap(init).expr) {
                    case TIf(_, _, elseArm) if (elseArm != null && isTNull(elseArm)):
                        // The ternary renders as an Option shape (a null
                        // else arm); remember the local so non-null call
                        // slots unwrap it once. (NullElseTernaryLocals)
                        nullElseTernaryLocals.set(v.id, true);
                    case _:
                }
                // A copy of a continue-guarded subject (`let n = X;` after
                // `if (X == null) { continue; }`) inherits the non-null
                // proof: call slots expecting the inner value unwrap the
                // copy at the argument boundary. (ContinueNullGuards)
                switch (stripWrap(init).expr) {
                    case TLocal(_) | TField(_, _):
                        final initSubject = subjectTextOf(init);
                        if (provenContinueSubjects.exists(initSubject))
                            provenNonNullVarIds.set(v.id, true);
                    case _:
                }
                // An initializer that rendered through the forcing read
                // (unwrap_or) stores the inner value in the binding, so
                // returns of this local skip the nullable-unwrap rule
                // (ForcingReadLocals).
                if (initStr.indexOf(".unwrap_or(") >= 0 && !StringTools.startsWith(initStr, "if "))
                    forcingReadLocals.set(v.id, true);
                if (isNullType(v.t) && !isTNull(init) && !StaticFieldHelper.isNullableType(init.t) && !lookupInit) {
                    initStr = "Some(" + initStr + ")";
                }
                // A shared closure array lowers as Arc<Mutex<Vec>> so the
                // capturing closures observe one another's updates
                // (SharedClosureArrays). The outer binding stays immutable:
                // the Mutex carries the interior mutability.
                if (sharedClosureArrays.exists(v.id)) {
                    imports.require("std::sync::Arc");
                    imports.require("std::sync::Mutex");
                    final innerType = types.of(v.t, false);
                    recordDeclInit(v, "Arc::new(Mutex::new(Vec::new()))");
                    return [indent(depth) + "let " + name + ": Arc<Mutex<" + innerType + ">> = Arc::new(Mutex::new(Vec::new()));"];
                }
                // A shared closure scalar lowers as Arc<Mutex<T>>: the named
                // local function that assigns it is an Arc<dyn Fn>, whose
                // captured bindings are immutable (SharedClosureScalars).
                if (sharedClosureScalars.exists(v.id)) {
                    imports.require("std::sync::Arc");
                    imports.require("std::sync::Mutex");
                    final innerType = types.of(v.t, false);
                    final valueText = isTNull(init) ? "Default::default()" : expr(init);
                    recordDeclInit(v, "Arc::new(Mutex::new(" + valueText + "))");
                    return [indent(depth) + "let " + name + ": Arc<Mutex<" + innerType + ">> = Arc::new(Mutex::new(" + valueText + "));"];
                }
                // An empty array literal is an untyped `vec![]` in Rust; the
                // element reads and writes of an array local infer through
                // later uses, but an index read before any write leaves the
                // element type unknown (E0282). The declared Haxe Array
                // element type anchors the binding. `new Array<T>()` renders
                // the same bare `Vec::new()` and needs the same anchor.
                if (explicitType == "") {
                    switch (stripWrap(init).expr) {
                        case TArrayDecl(elems) if (elems.length == 0):
                            switch (Context.follow(v.t)) {
                                case TInst(c, _) if (c.get().name == "Array"):
                                    nullableType = ": " + types.of(v.t, false);
                                case _:
                            }
                        case TNew(c, _, args) if (args.length == 0 && isArrayClass(c.get())):
                            switch (Context.follow(v.t)) {
                                case TInst(c, _) if (c.get().name == "Array"):
                                    nullableType = ": " + types.of(v.t, false);
                                case _:
                            }
                        case _:
                    }
                }
                // Array values are owned Vecs.  Borrowing an array literal here
                // made every local initialized from an array a reference, even
                // though its Haxe type is Array<T>; that leaked into later calls
                // and produced &&Vec / immutable-borrow mismatches.  Borrow only
                // at the call sites whose declared parameter requires it.
                // A let initializer needs no outer parentheses; fully
                // wrapped lowerings such as Int64.make would otherwise
                // trip rustc's unused_parens lint at this position.
                if (StringTools.startsWith(initStr, "(") && StringTools.endsWith(initStr, ")") && matchingParens(initStr)) {
                    initStr = initStr.substr(1, initStr.length - 2);
                }
                // A bare-value builder construction binds the stripped
                // value type: the builder's own declaration already lost
                // the Option layer, so the constructor type arguments must
                // match. (BuilderValueNullability)
                if (bareValueBuilders.exists(v.id)) {
                    final mbIdx = initStr.indexOf("map_builder::<");
                    if (mbIdx >= 0) {
                        final start = initStr.indexOf(", Option<", mbIdx);
                        final paren = initStr.indexOf("(", start);
                        if (start >= 0 && paren >= 0) {
                            final inner = initStr.substring(start + ", Option<".length, paren);
                            initStr = initStr.substr(0, start) + ", " + inner.substr(0, inner.length - 1)
                                + initStr.substr(paren);
                        }
                    }
                }
#if boring_fold_debug
                if (initStr.indexOf("preferred_inline_object_boundary") >= 0 || initStr.indexOf("metric_decision_by_range") >= 0 || v.name.indexOf("annotation") >= 0)
                    emissionTrace("TVAR " + v.name + " init=[" + initStr.substr(0, initStr.length > 60 ? 60 : initStr.length) + "]", e.pos);
#end
                // A reassigned local whose constant initializer is never
                // read before the first reassignment declares bare: the
                // later assignments own the storage. (DeadConstantInitElision)
                // A never-read binding discards its value: `let _ = expr`
                // names no variable, so neither the unused warning nor the
                // mutability warning can fire. (UnusedLocalNaming)
                final declText = unusedLocalIds.exists(v.id)
                    ? "let _ = " + initStr + ";"
                    : '$kw $name$nullableType = $initStr;';
                // (NonNullSlotUnwrap)
                if (declText.indexOf(": Option<") >= 0
                    || StringTools.startsWith(initStr, "Some(")
                    || initStr == "None"
                    || (StringTools.startsWith(initStr, "match ") && initStr.indexOf("=> Some(") >= 0)
                    || (nullableType == ""
                        && isNullType(init.t)
                        && !nullableCollapsedLocals.exists(v.id)
                        && !hasGuardedTernaryLocals.exists(v.id)
                        && initStr.indexOf(".unwrap(") < 0
                        && initStr.indexOf(".unwrap_or(") < 0
                        && initStr.indexOf("get_or_insert_with") < 0
                        // A scalar local only stores an Option when the
                        // initializer visibly constructs one; scalar
                        // sentinel renders carry the null inside the
                        // numeric form itself. (NonNullSlotUnwrap)
                        && (!isScalarType(getNullInnerType(init.t)) || initStr.indexOf("Some(") >= 0)))
                    optionRenderedLocals.set(v.id, true);
                // A declaration whose initializer already unwrapped the
                // Option stores the inner value; later reads must not
                // force-read the wrapper again. (DeclaredNullableLocals)
                if (initStr.indexOf(".unwrap(") >= 0 || initStr.indexOf(".unwrap_or(") >= 0)
                    declaredNullableLocals.remove(v.id);
                recordDeclInit(v, initStr);
                return [indent(depth) + declText];
            case TVar(v, init) if (init == null):
                final name = RustImports.toSnakeCase(localName(v));
                if (tryCapturedAssignments.exists(v.id) && isNullType(v.t)) {
                    recordDeclInit(v, "None");
                    return [indent(depth) + "let mut " + name + ": " + types.of(v.t, false) + " = None;"];
                }
                final kw = "let ";
                return [indent(depth) + kw + name + ": " + types.of(v.t, false) + ";"];
            case TBlock(stmts):
                final out = [indent(depth) + "{"];
                for (l in blockLines(stmts, depth + 1))
                    out.push(l);
                out.push(indent(depth) + "}");
                return out;
            case TSwitch(_, _, _):
                // Statement position discards the switch value; the Haxe
                // `case X: null;` idiom makes null-literal arms, which the
                // arm renderer emits as empty blocks under the discard flag
                // so all arms share the unit type.
                final prev = discardingStatementSwitch;
                discardingStatementSwitch = true;
                final text = expr(e);
                discardingStatementSwitch = prev;
                return [indent(depth) + "let _ = " + text + ";"];
            case TIf(c, t, f):
                final guarded = guardedMatchStatements(c, t, f, depth);
                if (guarded != null)
                    return guarded;
                var condStr = nullableBoolOperand(c, expr(c));
                while (StringTools.startsWith(condStr, "(") && StringTools.endsWith(condStr, ")") && matchingParens(condStr)) {
                    condStr = condStr.substr(1, condStr.length - 2);
                }
                final proven = provenNonNullLocal(c);
                if (proven != null)
                    provenNonNullVarIds.set(proven.id, true);
                final mapHas = mapHasGuard(c);
                if (mapHas != null)
                    provenMapGets.push(mapHas);
                final provenChain = provenNonNullLocals(c);
                for (v in provenChain)
                    provenNonNullVarIds.set(v.id, true);
                final hasGuard = hasGuardGetInfo(c);
                if (hasGuard != null)
                    hasGuardedGets.push(hasGuard);
                final out = [indent(depth) + "if " + condStr + " {"];
                for (l in blockLines(statementsOf(t), depth + 1))
                    out.push(l);
                if (hasGuard != null)
                    hasGuardedGets.pop();
                for (v in provenChain)
                    provenNonNullVarIds.remove(v.id);
                if (proven != null)
                    provenNonNullVarIds.remove(proven.id);
                if (mapHas != null)
                    provenMapGets.pop();
                if (f != null) {
                    out.push(indent(depth) + "} else {");
                    for (l in blockLines(statementsOf(f), depth + 1))
                        out.push(l);
                }
                out.push(indent(depth) + "}");
                // `if (X == null) { X = <construct>; }` with no else proves
                // X non-null for the statements that follow: the rendered
                // order is the execution order, so the proof stays set.
                // (GuardedRebindProven)
                if (f == null)
                    switch (stripWrap(c).expr) {
                        case TBinop(OpEq, l, r) if (isTNull(l) || isTNull(r)):
                            final subject = isTNull(l) ? r : l;
                            switch (stripWrap(subject).expr) {
                                case TLocal(v) if (containsAssignTo(t, v.id)):
                                    provenNonNullVarIds.set(v.id, true);
                                case _:
                            }
                        case _:
                    }
                return out;
            case TWhile(c, b, true):
                var condStr = nullableBoolOperand(c, expr(c));
                while (StringTools.startsWith(condStr, "(") && StringTools.endsWith(condStr, ")") && matchingParens(condStr)) {
                    condStr = condStr.substr(1, condStr.length - 2);
                }
                // A literal true condition lowers to Rust's dedicated loop.
                final header = condStr == "true" ? "loop" : "while " + condStr;
                // A compared cursor local (`while cursor != None`) is proven
                // non-null inside the loop body: its field reads unwrap
                // through the guard. (CursorPattern)
                final whileSubject:Null<TypedExpr> = switch (stripWrap(c).expr) {
                    case TBinop(OpNotEq, l, r) if (isTNull(r)): l;
                    case TBinop(OpNotEq, l, r) if (isTNull(l)): r;
                    case _: null;
                };
                final provenId:Null<Int> = whileSubject == null ? null : switch (stripWrap(whileSubject).expr) {
                    case TLocal(v): v.id;
                    case _: null;
                };
                if (provenId != null)
                    provenNonNullVarIds.set(provenId, true);
                final out = [indent(depth) + header + " {"];
                for (l in blockLines(statementsOf(b), depth + 1))
                    out.push(l);
                out.push(indent(depth) + "}");
                if (provenId != null)
                    provenNonNullVarIds.remove(provenId);
                return out;
            case TWhile(_, _, false):
                return [fail(e, "do-while has no lowering in the subset")];
            case TReturn(ret) if (ret == null):
                if (isFallible) {
                    return [indent(depth) + "return Ok(());"];
                }
                return [indent(depth) + "return;"];
            case TReturn(ret) if (isTryRegion(ret)):
                return regionReturnLines(stripWrap(ret), depth);
            case TReturn(ret) if (isVariantSwitch(ret)):
                return matchReturnLines(stripWrap(ret), depth);
            case TReturn(ret):
                // An Int-returning function renders u32, while a length
                // expression renders usize; the return narrows once at the
                // boundary. Each length read keeps its native type; the conversion
                // occurs at the call boundary.
                var retStr = if (returnUnsigned && isUsizeExpr(ret)) {
                    RustConversions.truncate(expr(ret), "u32");
                } else {
                    renderValueForType(currentReturnType, ret, expr(ret));
                };
                // An i32-domain local (String.indexOf result, wrapping
                // binop) returned from a business u32 Int function
                // reinterprets its bits at the boundary; the return slot is
                // the module u32 domain.
                if (returnUnsigned && isIntType(ret.t) && !isNullType(ret.t) && i32LocalDomain(ret) && !isUsizeExpr(ret)) {
                    retStr = RustConversions.reinterpret(retStr, "u32");
                }
                while (StringTools.startsWith(retStr, "(") && StringTools.endsWith(retStr, ")") && matchingParens(retStr)) {
                    retStr = retStr.substr(1, retStr.length - 2);
                }
                // A parameter-typed read clones at the boundary: the
                // element stays owned by its array.
                switch (stripWrap(ret).expr) {
                    case TConst(TThis) if (!isTypeCopy(ret.t)):
                        retStr = "(" + retStr + ").clone()";
                    case TField(_, _) if (!isTypeCopy(ret.t)):
                        retStr = "(" + retStr + ").clone()";
                    case TLocal(v) if (isBorrowedLocal(v) && !isTypeCopy(ret.t) && isOwnedVecType(ret.t)
                        && (returnTypeName == null || !StringTools.startsWith(returnTypeName, "&"))):
                        // An owned Vec return slot receiving a borrowed array
                        // parameter clones the referent at the boundary. A
                        // borrowing return slot keeps the caller's view.
                        retStr = "(*" + retStr + ").clone()";
                    case _:
                }
                if (RustType.isTypeParam(ret.t)) {
                    switch (stripWrap(ret).expr) {
                        case TArray(_, _) | TField(_, _) | TLocal(_):
                            retStr = "(" + retStr + ").clone()";
                        case _:
                    }
                }
                // String-bearing returns adjust once at the boundary: a
                // String function owns its value while a literal is a &str,
                // and an Option<String> return (Null<String>) wraps a plain
                // String expression in Some. Expressions that already carry
                // the Null type lower to Option themselves, and TNull
                // already renders None, so neither wraps again.
                if (returnTypeName == "String") {
                    switch (stripWrap(ret).expr) {
                        case TConst(TString(s)): retStr = s.length == 0 ? "String::new()" : retStr + ".to_string()";
                        case TLocal(v) if (provenNonNullVarIds.exists(v.id) && isNullType(ret.t)):
                            // A null-checked Null<String> local owns its
                            // text; the view unwrap yields the value the
                            // guard proved present.
                            retStr = "(" + retStr + ").as_deref().unwrap_or(\"\").to_string()";
                        case TLocal(v) if (isBorrowedLocal(v) && !StringTools.endsWith(retStr, ".to_string()")):
                            // A borrowed String parameter renders as &str; the
                            // owned String return slot converts it once.
                            retStr = "(" + retStr + ").to_string()";
                        case _:
                    }
                } else if (StringTools.startsWith(returnTypeName, "Option<") && !isTNull(ret) && (!isNullType(ret.t) || isNullableCollapsedLocal(ret))) {
                    var payload = switch (stripWrap(ret).expr) {
                        case TLocal(v) if (borrowedLoopVarIds.exists(v.id)):
                            isTypeCopy(ret.t) ? "*" + retStr : ownedLoopItemCloneText(ret.t, retStr);
                        case TConst(TString(_)): retStr + ".to_string()";
                        case _: retStr;
                    };
                    // Rust does not infer an integer literal inside Some from
                    // an Option<f64> return slot, so widen at this boundary.
                    if (StringTools.startsWith(returnTypeName, "Option<f") && isIntType(emittedType(ret)))
                        payload = intToFloatText(payload);
                    retStr = "Some(" + payload + ")";
                } else if (StringTools.startsWith(returnTypeName, "Option<") && isIntType(ret.t) && !isNullType(ret.t) && !isTNull(ret)) {
                    // An Int expression returned from a Null<Int> function
                    // wraps once at the boundary; Null-typed expressions
                    // already lower to Option and TNull renders None.
                    retStr = "Some(" + retStr + ")";
                } else if (!StringTools.startsWith(returnTypeName, "Option<")) {
                    switch (stripWrap(ret).expr) {
                        case TLocal(v) if (provenNonNullVarIds.exists(v.id) && isNullType(ret.t)):
                            // A null-checked Null<T> local returned as T
                            // unwraps at the boundary: the guard proved the
                            // Option holds Some, so `.unwrap()` yields the
                            // inner value the return type expects. Option
                            // returns keep the Option wrapper, so skip when
                            // the return type is itself Option.
                            retStr = "(" + retStr + ").unwrap()";
                        case _:
                    }
                    // Any nullable expression returned through a
                    // non-nullable slot unwraps at the boundary like the
                    // proven-local form above: a conditional mixing a
                    // nullable local with the null literal renders an
                    // Option value the slot cannot take. The None case
                    // panics exactly where the Haxe source would
                    // null-deref. A forcing-read local or a narrowed copy
                    // already holds the inner value, and a clone-rendered
                    // read is a value, so those skip the unwrap.
                    // (NullableReturnUnwrap)
                    var unwrapSkip = false;
                    switch (stripWrap(ret).expr) {
                        case TLocal(v):
                            unwrapSkip = forcingReadLocals.exists(v.id)
                                || nullableCollapsedLocals.exists(v.id)
                                || narrowedSubject(ret) != null;
                        case _:
                    }
                    // A ternary whose else arm is the null literal renders
                    // an Option shape even when the typer unified it to the
                    // non-null sibling type (null folds into that type).
                    // (NullableReturnUnwrap)
                    final nullElseTernary = switch (stripWrap(ret).expr) {
                        case TIf(_, _, elseArm) if (elseArm != null && isTNull(elseArm)): true;
                        case _: false;
                    };
                    if ((isNullType(ret.t) || nullElseTernary) && !isNullType(currentReturnType)
                        && !StringTools.endsWith(retStr, ").unwrap()")
                        && !StringTools.endsWith(retStr, ").clone()")
                        // A charCodeAt render already null-coalesces through
                        // unwrap_or; the returned value is the bare scalar
                        // and a second unwrap would not compile (E0599).
                        && !StringTools.contains(retStr, ".unwrap_or(")
                        && !unwrapSkip)
                        retStr = "(" + retStr + ").unwrap()";
                }
                // A narrowed operand returned through an Option slot wraps in
                // Some: the match binding is the inner value while the slot
                // keeps the Option shape. (NarrowedNullableParam)
                if (StringTools.startsWith(returnTypeName, "Option<")
                    && StringTools.startsWith(retStr, "*") && !StringTools.startsWith(retStr, "*("))
                    retStr = "Some(" + retStr + ")";
                if (isFallible) {
                    final guard = staticGuardOf(ret);
                    if (guard != null)
                        retStr = "(" + guard + ").clone()";
                    return [indent(depth) + "return Ok(" + retStr + ");"];
                }
                return [indent(depth) + "return " + retStr + ";"];
            case TThrow(x):
                return [indent(depth) + "return Err(" + throwVariant(x) + ");"];
            case TTry(body, catches) if (catches.length == 1):
                return regionStatementLines(body, catches[0], depth);
            case TTry(_, _):
                return [fail(e, "try region handles exactly one exception domain")];
            case TBreak:
                return [indent(depth) + "break;"];
            case TContinue:
                return [indent(depth) + "continue;"];
            case TCall(fn, args) if (stringBufMutationParts(fn) != null):
                return stringBufMutationLines(fn, args, depth);
            case TCall(fn, args) if (isDiscardedUnitResultCall(e, fn)):
                // A discarded fallible call still has a Result expression in
                // Rust.  Keep the call in statement position, but make the
                // discarded value explicit so expression/block contexts do
                // not require the Result to be unit.  The propagated `?` (or
                // infallible unwrap) remains owned by expr(call), preserving
                // try-region and exception behavior.
                return [indent(depth) + "let _ = " + expr(e) + ";"];
            case TMeta(_, inner):
                return stmtLines(inner, depth);
            case TUnop(OpIncrement, _, subj):
                return [indent(depth) + expr(subj) + " += 1;"];
            case TUnop(OpDecrement, _, subj):
                return [indent(depth) + expr(subj) + " -= 1;"];
            case _:
                return [indent(depth) + expr(e) + ";"];
        }
    }

    function throwVariant(x:TypedExpr):String {
        final inner = stripWrap(x);
        final raw = switch (inner.expr) {
            case TNew(c, _, args) if (args.length == 1 && state.messageOnlyExceptions.exists(c.get().module)):
                imports.requireType(c.get().module, c.get().name);
                c.get().name + "::new(" + exceptionMessageArg(args[0]) + ")";
            case TNew(c, _, args) if (args.length == 1): exceptionVariant(c.get(), args[0]);
            case _: expr(x);
        };
        if (errorTypeName == null || !StringTools.endsWith(errorTypeName, "Fault"))
            return raw;
        // A function whose Result error is a synthetic union still throws
        // concrete exception types: wrap the payload in the matching union
        // variant. A message-only exception has no payload enum, so the
        // member is the class itself.
        final member:Null<{module:String, name:String}> = switch (inner.expr) {
            case TNew(c, _, args) if (args.length == 1):
                final payload = payloadEnumRef(args[0]);
                payload != null
                    ? {module: payload.get().module, name: payload.get().name}
                    : {module: c.get().module, name: c.get().name};
            case _: null;
        };
        if (member == null || errorTypeName == member.name)
            return raw;
        final variant = state.syntheticErrorVariant(errorTypeName, member);
        return errorTypeName + "::" + (variant != null ? variant : member.name + "Fault") + "(" + raw + ")";
    }

    /**
        The payload enum behind std.UStringException: every buffer check
        of stdlib/08 reports UnpairedSurrogate through it. Registers the
        import the hand-emitted Err arms need and returns the enum name,
        or null when the exception class is outside the module set.
    **/
    function stringBufFaultEnum():Null<String> {
        final enumModule = state.exceptionPayloads.get("std.UStringException");
        if (enumModule == null) {
            return null;
        }
        final name = state.payloadEnumNames.exists(enumModule) ? state.payloadEnumNames.get(enumModule) : enumModule.split(".").pop();
        final emitted = state.payloadEnumModules.get(enumModule);
        final emittedIn = emitted != null ? emitted : "std.UStringException";
        imports.requireType(emittedIn, name);
        return name;
    }

    /**
        The Err payload for a string-buffer pairing check. The buffer
        reports through its own payload enum (UStringFault); a function
        whose error enum differs converts the payload into its
        UStringFaultFault variant (the same rule throwVariant applies to
        thrown payloads).
    **/
    function stringBufErrPayload(fault:String, payload:String):String {
        if (errorTypeName != null && errorTypeName != fault && StringTools.endsWith(errorTypeName, "Fault"))
            return errorTypeName + "::" + fault + "Fault(" + payload + ")";
        return payload;
    }

    /**
        Recognizes `buf.add(part)` and `buf.addChar(unit)` on std.StringBuf;
        the pairing checks end the fallible owner through `return Err`, so
        these mutations lower as statements only.
    **/
    function stringBufMutationParts(fn:TypedExpr):Null<{name:String, subj:TypedExpr}> {
        return PolicyQueries.stringBufMutationParts(fn);
    }

    /**
        A StringBuf mutation writes through its receiver, so the receiver
        must be a mutable place. A field subject owned by a nullable
        wrapper opens the wrapper with `as_mut`; the plain field read
        renders through `as_ref` and cannot borrow the unit storage
        mutably. Covers the nullable buffer field mutation family. The
        owner's binding is marked mutable by scanLocals.
    **/
    function nullableBufferFieldMutationSubject(subj:TypedExpr):String {
        return switch (stripWrap(subj).expr) {
            case TField(base, FInstance(_, _, cf)) | TField(base, FAnon(cf)) if (isNullType(base.t) && receiverCarriesFallibleWrapper(base)):
                "(" + expr(base) + ").as_mut().unwrap()." + RustImports.toSnakeCase(cf.get().name);
            case _: expr(subj);
        }
    }

    /** Statement lowering of the two buffer mutations (stdlib/08). */
    function stringBufMutationLines(fn:TypedExpr, args:Array<TypedExpr>, depth:Int):Array<String> {
        final parts = stringBufMutationParts(fn);
        if (parts == null) {
            return [fail(fn, "not a string buffer mutation")];
        }
        if (!isFallible) {
            return [
                fail(fn,
                    "string buffer " + parts.name + " has no lowering outside a fallible function: route the mutation through a fallible helper (stdlib/08)")
            ];
        }
        final fault = stringBufFaultEnum();
        if (fault == null) {
            return [
                fail(fn, "string buffer checks require std.UStringException in the module set (stdlib/08)")
            ];
        }
        final buf = nullableBufferFieldMutationSubject(parts.subj);
        final out:Array<String> = [];
        if (parts.name == "add") {
            final part = expr(args[0]);
            out.push(indent(depth) + "if let Some(&unit) = " + buf + ".last() {");
            // A Rust &str is always well-formed, so no part can open with
            // the trail surrogate the contract would pair; the trail-start
            // clause of stdlib/08 folds away.
            out.push(indent(depth + 1) + "if unit >= 55296 && unit <= 56319 && !" + part + ".is_empty() {");
            out.push(indent(depth + 2) + "return Err(" + wrappedBufferFault(fault, fault + "::UnpairedSurrogate { unit: u32::from(unit) }") + ");");
            out.push(indent(depth + 1) + "}");
            out.push(indent(depth) + "}");
            out.push(indent(depth) + buf + ".extend(" + part + ".encode_utf16());");
        } else {
            final u = expr(args[0]);
            out.push(indent(depth) + "if " + u + " >= 56320 && " + u + " <= 57343 {");
            out.push(indent(depth + 1) + "match " + buf + ".last() {");
            out.push(indent(depth + 2) + "Some(&last) if last >= 55296 && last <= 56319 => {}");
            out.push(indent(depth + 2) + "_ => return Err(" + wrappedBufferFault(fault, fault + "::UnpairedSurrogate { unit: " + u + " }") + "),");
            out.push(indent(depth + 1) + "}");
            out.push(indent(depth) + "} else if let Some(&last) = " + buf + ".last() {");
            out.push(indent(depth + 1) + "if last >= 55296 && last <= 56319 {");
            out.push(indent(depth + 2) + "return Err(" + wrappedBufferFault(fault, fault + "::UnpairedSurrogate { unit: u32::from(last) }") + ");");
            out.push(indent(depth + 1) + "}");
            out.push(indent(depth) + "}");
            out.push(indent(depth) + buf + ".push(" + RustConversions.truncate(u, "u16") + ");");
        }
        return out;
    }

    function wrappedBufferFault(fault:String, raw:String):String {
        // A try-region temporarily selects its payload enum as the active
        // error type. Preserve the enclosing Result error when the buffer
        // payload is emitted inside that region; a direct UStringFault
        // function keeps the payload unchanged.
        final active = errorTypeName;
        final target = active == fault && declaredErrorTypeName != null
            ? declaredErrorTypeName
            : (active != null ? active : declaredErrorTypeName);
        if (target == null || !StringTools.endsWith(target, "Fault") || target == fault) {
            return raw;
        }
        final enumModule = state.exceptionPayloads.get("std.UStringException");
        final memberModule = enumModule != null ? enumModule : "std.UStringFault";
        final variant = state.syntheticErrorVariant(target, {module: memberModule, name: fault});
        return target + "::" + (variant != null ? variant : fault + "Fault") + "(" + raw + ")";
    }

    function exceptionVariant(cls:ClassType, payloadArg:TypedExpr):String {
        // Name the payload enum from the thrown variant itself: each exception
        // class pairs with exactly one payload enum, and the enum is emitted
        // inside the exception class's module file.  A message-only exception
        // still needs its concrete class as the Result payload type.
        final arg = stripWrap(payloadArg);
        final payloadEnum = payloadEnumRef(arg);
        final errType = payloadEnum != null ? payloadEnum.get().name : (state.errorName != null ? state.errorName : cls.name);
        final enumModule = payloadEnum != null ? payloadEnum.get().module : null;
        final emittedIn = enumModule != null
            && state.payloadEnumModules.exists(enumModule) ? state.payloadEnumModules.get(enumModule) : cls.module;
        imports.requireType(emittedIn, errType);
        switch (arg.expr) {
            case TField(_, FEnum(_, ef)):
                return errType + "::" + RustImports.toUpperCamelCase(ef.name);
            case TCall(fn, callArgs):
                switch (stripWrap(fn).expr) {
                    case TField(_, FEnum(_, ef)):
                        final efArgs = switch (ef.type) {
                            case TFun(fargs, _): fargs;
                            case _: [];
                        };
                        final parts = [];
                        for (i in 0...callArgs.length) {
                            final argName = i < efArgs.length ? RustImports.toSnakeCase(efArgs[i].name) : "arg" + i;
                            final argType = i < efArgs.length ? efArgs[i].t : null;
                            parts.push(argName + ": " + ownedConstructorArg(argType, callArgs[i]));
                        }
                        return errType + "::" + RustImports.toUpperCamelCase(ef.name) + " { " + parts.join(", ") + " }";
                    case _:
                }
            case _:
        }
        return payloadEnum == null
            && state.errorName == null ? errType + "::new(" + exceptionMessageArg(payloadArg) + ")" : errType + "::" + expr(payloadArg);
    }

    /**
        exceptionMessageArg: a message-only exception constructor takes a
        &str. A string literal keeps its static borrowing, a borrowed
        parameter is already a view, and every other String expression
        borrows through as_str.
    **/
    function exceptionMessageArg(arg:TypedExpr):String {
        return stringViewArg(arg);
    }

    /**
        stringViewArg: a Rust &str slot takes a Haxe String. A string literal
        keeps its static borrowing, a borrowed parameter is already a view,
        and every other String expression borrows through as_str.
    **/
    function stringViewArg(arg:TypedExpr):String {
        final rendered = expr(arg);
        if (!isStringType(arg.t))
            return rendered;
        return switch (stripWrap(arg).expr) {
            case TConst(TString(_)): rendered;
            case TLocal(v) if (isBorrowedParamLocal(v)): rendered;
            case _: rendered + ".as_str()";
        };
    }

    /**
        nullableStringViewArg: a nullable String read reaching a plain &str
        slot unwraps its Option view to the empty string, the same mapping
        the null-to-zero bridge gives a nullable scalar. A null guard or
        null-coalescing local already bound the inner value, so its read
        stays a str view. A guard-narrowed declared-nullable local keeps
        Option storage (the guard only narrowed the Haxe type), so it still
        unwraps at the &str boundary.
    **/
    function nullableStringViewArg(arg:TypedExpr):Bool {
        if (isNullType(arg.t) && narrowedSubject(arg) == null && !isNullableCollapsedLocal(arg))
            return true;
        // A `x != null && f(x)` guard narrows the call-site type of a
        // Null<String> local to String, but the local's Rust storage is
        // still Option<String>; the &str slot must unwrap the wrapper
        // (E0599 as_str on Option).
        return switch (stripWrap(arg).expr) {
            case TLocal(v): declaredNullableLocals.exists(v.id) && narrowedSubject(arg) == null && !isNullableCollapsedLocal(arg);
            case _: false;
        };
    }

    function stringConcatOperand(value:TypedExpr):String {
        final std = stdStringArg(value);
        return std != null ? stdString(std, true) : stdStringType(value.t, expr(value), true, value);
    }

    function collectStringConcatOperands(value:TypedExpr, out:Array<TypedExpr>):Void {
        switch (stripWrap(value).expr) {
            case TBinop(OpAdd, left, right) if (isStringType(left.t) || isStringType(right.t)):
                collectStringConcatOperands(left, out);
                collectStringConcatOperands(right, out);
            case _:
                out.push(value);
        }
    }

    function errorPropagationSuffix(c:Ref<ClassType>, cf:Ref<ClassField>, isStatic:Bool):String {
        if (!isFallible)
            return isFallibleCallee(c, cf, isStatic) ? ".unwrap()" : "";
        if (!isFallibleCallee(c, cf, isStatic))
            return "";
        final callee = state.funcErrorTypes.get(RustEmissionState.funcKey(c.get().module, cf.get().name, isStatic));
        if (callee == null || errorTypeName == null || callee.name == errorTypeName)
            return "?";
        final variant = state.syntheticErrorVariant(errorTypeName, callee);
        if (variant == null) {
            // The declared caller enum may carry growth variants registered
            // for callee faults merged beyond its declared set; `?` then maps
            // into a real constructor replacing a missing From impl.
            final growth = state.enumGrowthFor(errorTypeName);
            if (growth != null) {
                for (item in growth)
                    if (item.calleeName == callee.name)
                        return ".map_err(|e| " + errorTypeName + "::" + item.variant + "(e))?";
            }
            return "?";
        }
        return ".map_err(|e| " + errorTypeName + "::" + variant + "(e))?";
    }

    function payloadEnumRef(e:TypedExpr):Null<Ref<haxe.macro.Type.EnumType>> {
        return switch (stripWrap(e).expr) {
            case TField(_, FEnum(en, _)): en;
            case TCall(fn, _):
                switch (stripWrap(fn).expr) {
                    case TField(_, FEnum(en, _)): en;
                    case _: null;
                }
            case _: null;
        };
    }

    function fuseWithin(e:TypedExpr):TypedExpr {
        return switch (e.expr) {
            case TBlock(stmts):
                final nested = [for (s in stmts) fuseWithin(s)];
                final fused = fuseUninitializedVars(nested);
                final deadMatchFused = DeadInitializerMatchFusion.fuseDeadInitializerMatch(fused, stripCast, sunkInitVarIds);
                {expr: TBlock(deadMatchFused), pos: e.pos, t: e.t};
            case _:
                TypedExprTools.map(e, fuseWithin);
        }
    }

    function fuseUninitializedVars(stmts:Array<TypedExpr>):Array<TypedExpr> {
        final byDecl = new Map<Int, VarFusionPlan.VarFusionPlanEntry>();
        final removed = new Map<Int, Bool>();
        for (step in VarFusionPlan.plan(stmts, stripCast)) {
            byDecl.set(step.declIdx, step);
            removed.set(step.assignIdx, true);
        }
        final remaining = [for (i in 0...stmts.length) if (!removed.exists(i)) stmts[i]];
        final out:Array<TypedExpr> = [];
        for (i in 0...stmts.length) {
            if (removed.exists(i))
                continue;
            final step = byDecl.get(i);
            if (step == null) {
                out.push(stmts[i]);
                continue;
            }
            switch (stmts[i].expr) {
                case TVar(v, _):
                    out.push({expr: TVar(v, step.rhs), pos: stmts[i].pos, t: stmts[i].t});
                case _:
                    out.push(stmts[i]);
            }
        }
        return out;
    }

    /**
        When a mutable local is declared with a function reference initializer
        and the very next statement reassigns the same local from the same
        function reference, the initializer value is dead on arrival.  Strip
        the initializer so the declaration emits an uninit
        `let mut name: Type;` and avoids the unused-assignment lint.
    **/
    function stripDeadInits(stmts:Array<TypedExpr>):Array<TypedExpr> {
        final out:Array<TypedExpr> = [];
        var i = 0;
        while (i < stmts.length) {
            var stripped = false;
            switch (stmts[i].expr) {
                case TVar(v, init) if (init != null):
                    switch (stripCast(init).expr) {
                        case TField(_, FStatic(_, _) | FInstance(_, _, _)):
                            if (i + 1 < stmts.length) {
                                switch (stripWrap(stmts[i + 1]).expr) {
                                    case TBinop(OpAssign, lhs, rhs):
                                        switch [stripWrap(lhs).expr, stripCast(rhs).expr] {
                                            case [TLocal(assigned), TField(_, FStatic(_, _) | FInstance(_, _, _))]:
                                                if (assigned.id == v.id) {
                                                    out.push({expr: TVar(v, null), pos: stmts[i].pos, t: stmts[i].t});
                                                    stripped = true;
                                                    mutated.set(v.id, true);
                                                    #if boring_fold_debug
                                                    Sys.stderr().writeString("MSITE1 id=" + v.id + " name=" + v.name + "\n");
                                                    #end
                                                }
                                            case _:
                                        }
                                    case _:
                                }
                            }
                        case _:
                    }
                case _:
            }
            if (!stripped)
                out.push(stmts[i]);
            i += 1;
        }
        return out;
    }

    /**
        Fuses Haxe-decomposed array compound assignments back into a single
        Rust compound-assignment.  The Haxe typed AST decomposes
        `arr[idx] += rhs` into `var base = arr; var index = idx;
        base[index] += rhs`.  This pass inlines `base` and `index` back
        into the compound assignment so Rust receives a direct
        `arr[idx] += rhs` without moving the array or conflicting on
        mutable/immutable borrows of the same array.
    **/
    function fuseArrayCompoundAssign(stmts:Array<TypedExpr>):Array<TypedExpr> {
        final out:Array<TypedExpr> = [];
        var i = 0;
        while (i < stmts.length) {
            var fused = false;
            if (i + 2 < stmts.length) {
                switch (stmts[i].expr) {
                    case TVar(base, baseInit) if (baseInit != null):
                        switch (stripWrap(baseInit).expr) {
                            case TLocal(_) | TField(_, _):
                                if (isOwnedVecType(base.t)) {
                                    // Optional index temp
                                    switch (stmts[i + 1].expr) {
                                        case TVar(index, indexInit):
                                            if (indexInit != null
                                                && isCompoundAssignTarget(stmts[i + 2], base)
                                                && !restMentionsLocal(base.id, stmts, i + 3)) {
                                                    final subst = new Map<Int, TypedExpr>();
                                                    subst.set(base.id, baseInit);
                                                    subst.set(index.id, indexInit);
                                                    out.push(substituteLocals(stmts[i + 2], subst));
                                                    i += 3;
                                                    fused = true;
                                                }
                                        case _:
                                    }
                                    if (!fused
                                        && isCompoundAssignTarget(stmts[i + 1], base)
                                        && !restMentionsLocal(base.id, stmts, i + 2)) {
                                            final subst = new Map<Int, TypedExpr>();
                                            subst.set(base.id, baseInit);
                                            out.push(substituteLocals(stmts[i + 1], subst));
                                            i += 2;
                                            fused = true;
                                        }
                                }
                            case _:
                        }
                    case _:
                }
            }
            if (!fused) {
                out.push(stmts[i]);
                i++;
            }
        }
        return out;
    }

    function isCompoundAssignTarget(e:TypedExpr, base:TVar):Bool {
        final inner = stripWrap(e);
        return switch (inner.expr) {
            case TBinop(OpAssignOp(_), lhs, _):
                switch (stripWrap(lhs).expr) {
                    case TArray(_, _):
                        isAliasOfLoc(lhs, base.id);
                    case _: false;
                }
            case _: false;
        };
    }

    function isAliasOfLoc(expr:TypedExpr, id:Int):Bool {
        final arg = switch (stripWrap(expr).expr) {
            case TArray(arr, _): arr;
            case _: expr;
        };
        return switch (stripWrap(arg).expr) {
            case TLocal(v): v.id == id;
            case _: false;
        };
    }

    function restMentionsLocal(varId:Int, stmts:Array<TypedExpr>, start:Int):Bool {
        for (j in start...stmts.length) {
            if (mentionsLocalId(stmts[j], varId))
                return true;
        }
        return false;
    }

    function mentionsLocalId(e:TypedExpr, id:Int):Bool {
        var found = false;
        function scan(node:TypedExpr) {
            switch (node.expr) {
                case TLocal(v): if (v.id == id) found = true;
                case _:
            }
            if (!found) haxe.macro.TypedExprTools.iter(node, scan);
        }
        scan(e);
        return found;
    }

    function substituteLocals(e:TypedExpr, subst:Map<Int, TypedExpr>):TypedExpr {
        function replace(node:TypedExpr):TypedExpr {
            return switch (node.expr) {
                case TLocal(v) if (subst.exists(v.id)): subst.get(v.id);
                case _: haxe.macro.TypedExprTools.map(node, replace);
            };
        };
        return replace(e);
    }

    /**
        Locals that an early-exit null guard proves present for the rest of
        a statement list: an `if (x == null) return;` without an else arm
        ends the block whenever x is absent, so every later statement sees
        a present value. A guard whose local a later statement reassigns
        (impossible for a final binding) is excluded.
    **/
    function earlyExitGuardIds(stmts:Array<TypedExpr>):Array<Int> {
        final ids = [];
        for (i in 0...stmts.length) {
            final localId = earlyExitGuardLocal(stmts[i]);
            if (localId != null && !writesLocalAfter(stmts, i, localId))
                ids.push(localId);
        }
        return ids;
    }

    /** The local an early-exit null guard statement proves, or null. */
    function earlyExitGuardLocal(stmt:TypedExpr):Null<Int> {
        return switch (stripWrap(stmt).expr) {
            case TIf(cond, thenBody, null):
                final localId = nullEqLocal(cond);
                if (localId != null && TerminationAnalysis.alwaysTerminates(thenBody)) localId else null;
            case _: null;
        };
    }

    /** The local an `x == null` or `null == x` condition compares. */
    function nullEqLocal(cond:TypedExpr):Null<Int> {
        return switch (stripWrap(cond).expr) {
            case TBinop(OpEq, l, r):
                switch [stripWrap(l).expr, stripWrap(r).expr] {
                    case [TLocal(v), TConst(TNull)]: v.id;
                    case [TConst(TNull), TLocal(v)]: v.id;
                    case _: null;
                };
            case _: null;
        };
    }

    /** Whether any statement after `from` assigns through the local. */
    function writesLocalAfter(stmts:Array<TypedExpr>, from:Int, localId:Int):Bool {
        for (i in (from + 1)...stmts.length) {
            if (writesLocal(stmts[i], localId))
                return true;
        }
        return false;
    }

    /** Whether the statement assigns through the local anywhere. */
    function writesLocal(e:TypedExpr, localId:Int):Bool {
        return switch (stripWrap(e).expr) {
            case TBinop(OpAssign | OpAssignOp(_), t, _): targetMentions(t, localId);
            case TUnop(OpIncrement | OpDecrement, _, subj): targetMentions(subj, localId);
            case TBlock(stmts): anyWrites(stmts, localId);
            case TIf(_, t, f): writesLocal(t, localId) || (f != null && writesLocal(f, localId));
            case TWhile(_, b, _) | TFor(_, _, b): writesLocal(b, localId);
            case TVar(_, init): init != null && writesLocal(init, localId);
            case _: false;
        };
    }

    function anyWrites(stmts:Array<TypedExpr>, localId:Int):Bool {
        for (s in stmts) {
            if (writesLocal(s, localId))
                return true;
        }
        return false;
    }

    /** Whether the assignment target chain mentions the local. */
    function targetMentions(e:TypedExpr, localId:Int):Bool {
        return switch (stripWrap(e).expr) {
            case TLocal(v): v.id == localId;
            case TArray(arr, _): targetMentions(arr, localId);
            case TField(subj, _): targetMentions(subj, localId);
            case _: false;
        };
    }

    /** Expression-position block lowering (features/43). */
    function blockExpression(stmts:Array<TypedExpr>):String {
        stmts = ExpressionBlockNorm.normalize(stmts, (e, message) -> fail(e, message), _ -> "expression block must end in a value statement (features/43)",
            "expression block allows only declarations before its value statement (features/43)");
        final out = ["{"];
        for (s in stmts.slice(0, stmts.length - 1))
            for (line in stmtLines(s, 1))
                out.push(line);
        out.push(indent(1) + expr(stmts[stmts.length - 1]));
        out.push("}");
        return out.join("\n");
    }

    function blockLines(stmts:Array<TypedExpr>, depth:Int, tailScope:Bool = false):Array<String> {
        stmts = fuseUninitializedVars(stmts);
        stmts = stripDeadInits(stmts);
        stmts = fuseArrayCompoundAssign(stmts);
        stmts = regroupLoops(stmts);
        stmts = transformCountdownLoops(stmts);
        final out:Array<String> = [];
        final provenByGuard = earlyExitGuardIds(stmts);
        for (id in provenByGuard)
            provenNonNullVarIds.set(id, true);
        final fillBase = fillNarrowings.length;

        var i = 0;
        while (i < stmts.length) {
            if (TerminationAnalysis.alwaysTerminates(stmts[i])) {
                for (l in stmtLines(stmts[i], depth))
                    out.push(l);
                break;
            }
            final fused = fillFusion(stmts, i, depth);
            if (fused != null) {
                for (l in fused)
                    out.push(l);
                i += 2;
                continue;
            }
            final loop = matchInterval(stmts[i]);
            if (loop != null) {
                for (l in loopLines(loop, depth))
                    out.push(l);
                i += 1;
                continue;
            }
            for (l in stmtLines(stmts[i], depth))
                out.push(l);
            final fill = fillNarrowingOf(stmts[i]);
            if (fill != null)
                fillNarrowings.push(fill);
            i += 1;
        }

        if (tailScope && isFallible) {
            var endsWithReturn = false;
            if (stmts.length > 0) {
                switch (stmts[stmts.length - 1].expr) {
                    case TReturn(_) | TThrow(_):
                        endsWithReturn = true;
                    // A break-free while(true) never falls through; a trailing
                    // epilogue would be dead text.
                    case TWhile(c, b, true) if (isLiteralTrue(c) && !loopBodyBreaks(b)):
                        endsWithReturn = true;
                    case _:
                }
            }
            if (!endsWithReturn) {
                out.push(indent(depth) + (inTryClosure
                    || currentReturnType == null
                    || isVoidType(currentReturnType) ? "Ok(())" : "unreachable!();"));
            }
        }

        for (id in provenByGuard)
            provenNonNullVarIds.remove(id);
        while (fillNarrowings.length > fillBase)
            fillNarrowings.pop();
        return out;
    }

    function transformCountdownLoops(stmts:Array<TypedExpr>):Array<TypedExpr> {
        final out:Array<TypedExpr> = [];
        var i = 0;
        while (i < stmts.length) {
            if (i + 1 < stmts.length) {
                final cd = matchCountdownLoop(stmts[i], stmts[i + 1]);
                if (cd != null) {
                    mutated.set(cd.readVar.id, true);
                    final newDecl:TypedExpr = {
                        expr: TVar(cd.readVar, cd.base),
                        pos: stmts[i].pos,
                        t: stmts[i].t
                    };
                    out.push(newDecl);

                    final newCond = transformCountdownCond(cd.cond, cd.readVar.id);
                    final newBodyStmts = statementsOf(cd.body).map(s -> shiftIndexExpr(s, cd.readVar.id));
                    final newBody:TypedExpr = {
                        expr: TBlock(newBodyStmts),
                        pos: cd.body.pos,
                        t: cd.body.t
                    };
                    final newWhile:TypedExpr = {
                        expr: TWhile(newCond, newBody, true),
                        pos: stmts[i + 1].pos,
                        t: stmts[i + 1].t
                    };
                    out.push(newWhile);

                    for (k in (i + 2)...stmts.length) {
                        out.push(shiftIndexExpr(stmts[k], cd.readVar.id));
                    }
                    break;
                }
            }
            out.push(stmts[i]);
            i += 1;
        }
        return out;
    }

    function matchCountdownLoop(decl:TypedExpr, loop:TypedExpr):Null<{
        readVar:TVar,
        base:TypedExpr,
        cond:TypedExpr,
        body:TypedExpr
    }> {
        switch [decl.expr, loop.expr] {
            case [TVar(readVar, init), TWhile(cond, body, true)] if (init != null):
                if (!isIntType(init.t))
                    return null;
                if (!hasGteZeroCheck(cond, readVar.id)) {
                    return null;
                }
                if (!mentionsUnitDecrement(statementsOf(body), readVar.id)) {
                    return null;
                }
                // The guard becomes `> 0` and every body reference shifts
                // down by one, so the transformed loop must start one above
                // the initializer for the body to see the initializer's own
                // value on the first pass. An initializer of the exact shape
                // `X - 1` keeps the stripped `X` form; any other initializer
                // gets an explicit `+ 1`.
                final stripped = strippedUnitSub(init);
                final base = stripped != null ? stripped : {
                    expr: TBinop(OpAdd, init, {expr: TConst(TInt(1)), pos: init.pos, t: init.t}),
                    pos: init.pos,
                    t: init.t
                };
                return {
                    readVar: readVar,
                    base: base,
                    cond: cond,
                    body: body
                };
            case _:
                return null;
        }
    }

    // `X - 1` with a literal 1 on the right yields X.
    function strippedUnitSub(e:TypedExpr):Null<TypedExpr> {
        return switch (stripWrap(e).expr) {
            case TBinop(OpSub, b, r):
                switch (stripWrap(r).expr) {
                    case TConst(TInt(1)): b;
                    case _: null;
                };
            case _: null;
        };
    }

    function isLiteralTrue(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TConst(TBool(true)): true;
            case _: false;
        };
    }

    // A break lexically inside a nested loop or closure binds to that
    // construct; only direct breaks of this loop end it.
    function loopBodyBreaks(e:TypedExpr):Bool {
        switch (e.expr) {
            case TBreak:
                return true;
            case TWhile(_, _, _) | TFor(_, _, _) | TFunction(_):
                return false;
            case _:
                var found = false;
                TypedExprTools.iter(e, child -> {
                    if (!found && loopBodyBreaks(child))
                        found = true;
                });
                return found;
        }
    }

    function hasGteZeroCheck(cond:TypedExpr, varId:Int):Bool {
        final inner = stripWrap(cond);
        switch (inner.expr) {
            case TBinop(OpBoolAnd, l, _):
                return isGteZero(l, varId);
            case _:
                return isGteZero(inner, varId);
        }
    }

    function isGteZero(e:TypedExpr, varId:Int):Bool {
        final inner = stripWrap(e);
        return switch (inner.expr) {
            case TBinop(OpGte, l, r):
                switch [stripWrap(l).expr, stripWrap(r).expr] {
                    case [TLocal(v), TConst(TInt(0))] if (v.id == varId): true;
                    case _: false;
                };
            case TBinop(OpLte, l, r):
                switch [stripWrap(l).expr, stripWrap(r).expr] {
                    case [TConst(TInt(0)), TLocal(v)] if (v.id == varId): true;
                    case _: false;
                };
            case TBinop(OpGt, l, r):
                switch [stripWrap(l).expr, stripWrap(r).expr] {
                    case [TLocal(v), TConst(TInt(-1))] if (v.id == varId): true;
                    case _: false;
                };
            case _: false;
        }
    }

    function transformCountdownCond(cond:TypedExpr, varId:Int):TypedExpr {
        final inner = stripWrap(cond);
        switch (inner.expr) {
            case TBinop(OpBoolAnd, l, r) if (isGteZero(l, varId)):
                final v = findLocalVar(l, varId);
                final newL:TypedExpr = {
                    expr: TBinop(OpGt, {expr: TLocal(v), pos: l.pos, t: l.t}, {expr: TConst(TInt(0)), pos: l.pos, t: l.t}),
                    pos: l.pos,
                    t: l.t
                };
                final newR = shiftIndexExpr(r, varId);
                return {
                    expr: TBinop(OpBoolAnd, newL, newR),
                    pos: cond.pos,
                    t: cond.t
                };
            case _:
                if (isGteZero(inner, varId)) {
                    final v = findLocalVar(inner, varId);
                    return {
                        expr: TBinop(OpGt, {expr: TLocal(v), pos: inner.pos, t: inner.t}, {expr: TConst(TInt(0)), pos: inner.pos, t: inner.t}),
                        pos: cond.pos,
                        t: cond.t
                    };
                }
                return shiftIndexExpr(cond, varId);
        }
    }

    function findLocalVar(e:TypedExpr, varId:Int):TVar {
        var found:Null<TVar> = null;
        function walk(x:TypedExpr) {
            switch (x.expr) {
                case TLocal(v) if (v.id == varId):
                    found = v;
                case _:
            }
            TypedExprTools.iter(x, walk);
        }
        walk(e);
        return found;
    }

    function mentionsUnitDecrement(stmts:Array<TypedExpr>, varId:Int):Bool {
        var found = false;
        for (s in stmts) {
            function walk(x:TypedExpr) {
                switch (x.expr) {
                    // Only a unit step is transformable: the unsigned `> 0`
                    // guard exits exactly at zero, and a larger step would
                    // wrap below zero on the unsigned domain and keep
                    // looping.
                    case TBinop(OpAssignOp(OpSub), l, r) if (isTargetVar(l, varId) && isLiteralOne(r)):
                        found = true;
                    case TBinop(OpAssign, l, r) if (isTargetVar(l, varId)):
                        switch (stripWrap(r).expr) {
                            case TBinop(OpSub, subTarget, sub) if (isTargetVar(subTarget, varId) && isLiteralOne(sub)):
                                found = true;
                            case _:
                        }
                    case TUnop(OpDecrement, _, subj) if (isTargetVar(subj, varId)):
                        found = true;
                    case _:
                }
                TypedExprTools.iter(x, walk);
            }
            walk(s);
        }
        return found;
    }

    /** Whether the loop body decrements the variable by any step. */
    function mentionsAnyDecrement(stmts:Array<TypedExpr>, varId:Int):Bool {
        var found = false;
        for (s in stmts) {
            function walk(x:TypedExpr) {
                switch (x.expr) {
                    case TBinop(OpAssignOp(OpSub), l, _) if (isTargetVar(l, varId)):
                        found = true;
                    case TBinop(OpAssign, l, r) if (isTargetVar(l, varId)):
                        switch (stripWrap(r).expr) {
                            case TBinop(OpSub, subTarget, _) if (isTargetVar(subTarget, varId)):
                                found = true;
                            case _:
                        }
                    case TUnop(OpDecrement, _, subj) if (isTargetVar(subj, varId)):
                        found = true;
                    case _:
                }
                TypedExprTools.iter(x, walk);
            }
            walk(s);
        }
        return found;
    }

    function isLiteralOne(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TConst(TInt(1)): true;
            case _: false;
        };
    }

    function isTargetVar(e:TypedExpr, varId:Int):Bool {
        return switch (stripWrap(e).expr) {
            case TLocal(v) if (v.id == varId): true;
            case _: false;
        };
    }

    function shiftIndexExpr(e:TypedExpr, varId:Int):TypedExpr {
        switch (e.expr) {
            case TBinop(OpAdd, l, r):
                switch [stripWrap(l).expr, stripWrap(r).expr] {
                    case [TLocal(v), TConst(TInt(1))] if (v.id == varId):
                        return l;
                    case [TConst(TInt(1)), TLocal(v)] if (v.id == varId):
                        return r;
                    case _:
                }
            case TBinop(OpAssignOp(op), l, r) if (isTargetVar(l, varId)):
                return {
                    expr: TBinop(OpAssignOp(op), l, shiftIndexExpr(r, varId)),
                    pos: e.pos,
                    t: e.t
                };
            case TBinop(OpAssign, l, r) if (isTargetVar(l, varId)):
                return {
                    expr: TBinop(OpAssign, l, shiftAssignRhs(r, varId)),
                    pos: e.pos,
                    t: e.t
                };
            case TUnop(OpDecrement, post, subj) if (isTargetVar(subj, varId)):
                return e;
            case TLocal(v) if (v.id == varId):
                return {
                    expr: TBinop(OpSub, e, {expr: TConst(TInt(1)), pos: e.pos, t: e.t}),
                    pos: e.pos,
                    t: e.t
                };
            case _:
        }
        return TypedExprTools.map(e, x -> shiftIndexExpr(x, varId));
    }

    function shiftAssignRhs(r:TypedExpr, varId:Int):TypedExpr {
        final inner = stripWrap(r);
        switch (inner.expr) {
            case TBinop(OpSub, l, rightSub) if (isTargetVar(l, varId)):
                return {
                    expr: TBinop(OpSub, l, shiftIndexExpr(rightSub, varId)),
                    pos: r.pos,
                    t: r.t
                };
            case _:
                return shiftIndexExpr(r, varId);
        }
    }

    // ------------------------------------------------------------------
    // Counted loops
    // ------------------------------------------------------------------
    function regroupLoops(stmts:Array<TypedExpr>):Array<TypedExpr> {
        return PolicyQueries.regroupLoops(stmts);
    }

    function intervalCore(counterDecl:TypedExpr, boundDecl:TypedExpr, whileExpr:TypedExpr):Null<{
        index:TVar,
        start:TypedExpr,
        bound:TypedExpr,
        body:Array<TypedExpr>,
        counter:TVar
    }> {
        return PolicyQueries.intervalCore(counterDecl, boundDecl, whileExpr);
    }

    function matchInterval(e:TypedExpr):Null<{
        index:TVar,
        start:TypedExpr,
        bound:TypedExpr,
        body:Array<TypedExpr>,
        counter:TVar
    }> {
        return PolicyQueries.matchInterval(e);
    }

    function intervalShort(counterDecl:TypedExpr, whileExpr:TypedExpr):Null<{
        index:TVar,
        start:TypedExpr,
        bound:TypedExpr,
        body:Array<TypedExpr>,
        counter:TVar
    }> {
        return PolicyQueries.intervalShort(counterDecl, whileExpr);
    }

    function loopLines(loop, depth:Int):Array<String> {
        rangeLoopVars.set(loop.index.id, true);
        final raw = RustImports.toSnakeCase(loop.index.name);
        final name = unusedLocalIds.exists(loop.index.id) ? "_" + raw : raw;
        final sliceSubj = sliceIterationSubject(loop);
        if (sliceSubj != null) {
            final itemVar = sliceItemVar(loop.body, loop.index, sliceSubj);
            if (itemVar != null) {
                final itemName = RustImports.toSnakeCase(itemVar.name);
                final isScalar = switch (Context.follow(itemVar.t)) {
                    case TAbstract(a, _): final n = a.get().name; n == "Int" || n == "Bool" || n == "Float";
                    default: false;
                };
                // A name-keyed lookup is valid only for current-function parameters because argTypes accumulates across functions.
                final argType = switch (stripWrap(sliceSubj).expr) {
                    case TLocal(v): paramVarIds.exists(v.id) ? argTypes.get(v.name) : null;
                    default: null;
                };
                // A subject already rendered as a Rust reference needs no
                // extra borrow: a current-function or local-function
                // parameter arrives as a &Vec view, and a null-guard match
                // binding binds the borrowed Option payload. Only an owned
                // subject borrows for the loop. An owned parameter
                // (argType without &) is not already a reference and must
                // borrow the vec so the source stays alive for later uses.
                // A closure capture copy binds an owned clone even though
                // the outer binding is a parameter, so it borrows too.
                // (ClosureCaptureBorrow)
                final subjectLocalId = switch (stripWrap(sliceSubj).expr) {
                    case TLocal(v): v.id;
                    case _: -1;
                };
                final captureCloneSubject = subjectLocalId >= 0 && currentCaptureClones.exists(subjectLocalId);
                final referenceSubject = !captureCloneSubject
                    && ((argType != null && StringTools.startsWith(argType, "&"))
                    || isClosureParam(sliceSubj) || narrowedSubject(sliceSubj) != null);
                // A scalar loop over an owned local array borrows the array: the
                // pattern takes a reference and the array stays usable after the
                // loop. Parameters already arrive as rendered references.
                final ownedLocal = isScalar && !referenceSubject;
                final pattern = if (isScalar) {
                    if (argType != null && StringTools.startsWith(argType, "&mut")) {
                        "&mut " + itemName;
                    } else {
                        "&" + itemName;
                    }
                } else {
                    itemName;
                };
                if (referenceSubject)
                    borrowedLoopVarIds.set(itemVar.id, true);
                // An owned parameter (argType without a & prefix) is an owned
                // Vec value, so iterating it must borrow the subject the same way as
                // an owned local. Borrowed parameters are already &Vec views.
                final ownedParameter = paramVarIds.exists(subjectLocalId) && argType != null && !StringTools.startsWith(argType, "&");
                final nonScalarOwnedLocal = captureCloneSubject
                    || (!isScalar && !referenceSubject && (!paramVarIds.exists(subjectLocalId) || ownedParameter));
                if (nonScalarOwnedLocal)
                    borrowedLoopVarIds.set(itemVar.id, true);
                // A shared closure array iterates through its lock guard:
                // a leading & would borrow the MutexGuard itself, which is
                // not an iterator. (SharedClosureArrays)
                final sharedSubject = subjectLocalId >= 0
                    && (sharedClosureArrays.exists(subjectLocalId) || sharedClosureScalars.exists(subjectLocalId));
                final iterated = sharedSubject ? expr(sliceSubj) + ".iter()"
                    : (ownedLocal || nonScalarOwnedLocal) ? "&" + expr(sliceSubj) : expr(sliceSubj);
                switch (Context.follow(itemVar.t)) {
                    case TAbstract(a, _) if (a.get().name == "Int"):
                        // Array elements reach Rust as u32; remember the loop binding
                        // so negative-domain checks lower as upper-bound checks.
                        unsignedLocals.set(itemVar.id, true);
                    case _:
                }
                final remainingBody = loop.body.slice(1);
                final gb = matchGroupByBody(remainingBody);
                if (gb != null) {
                    final entryName = RustImports.toSnakeCase(gb.entryVar.name);
                    final entryExprStr = expr(gb.entryInit);
                    final builderStr = expr(gb.builderSubj);
                    final kGetExpr = sortedRefArg(gb.keyArg);
                    final kPutExpr = sortedRefArg(gb.keyArg);
                    // The fused put's value slot is the builder's applied V:
                    // a non-null value into a nullable-V slot wraps in Some;
                    // scalar-valued maps strip the Null at storage, so their
                    // slot is the plain scalar and no wrap applies.
                    // (SortedPutValueAdaptation)
                    final appliedV = switch (Context.follow(gb.builderSubj.t)) {
                        case TInst(_, params) if (params.length > 1): params[1];
                        case _: null;
                    };
                    final valElementType = if (appliedV != null && isNullType(appliedV)
                        && !isNumericScalarType(getNullInnerType(appliedV)))
                        appliedV
                    else
                        null;
                    final valStr = renderPushArg(gb.valArg, valElementType);
                    final out = [indent(depth) + "for " + pattern + " in " + iterated + " {"];
                    for (l in blockLines(gb.prefix, depth + 1))
                        out.push(l);
                    out.push(indent(depth + 1) + "let " + entryName + " = " + entryExprStr + ";");
                    out.push(indent(depth + 1) + "let mut pipeline_bucket = match " + builderStr + ".get(" + kGetExpr + ") {");
                    out.push(indent(depth + 2) + "Some(b) => b,");
                    out.push(indent(depth + 2) + "None => Vec::new(),");
                    out.push(indent(depth + 1) + "};");
                    out.push(indent(depth + 1) + "pipeline_bucket.push(" + valStr + ");");
                    out.push(indent(depth + 1) + builderStr + ".put(" + kPutExpr + ", &pipeline_bucket);");
                    out.push(indent(depth) + "}");
                    return out;
                }

                final out = [indent(depth) + "for " + pattern + " in " + iterated + " {"];
                for (l in blockLines(remainingBody, depth + 1))
                    out.push(l);
                out.push(indent(depth) + "}");
                return out;
            }
        }

        final startStr = expr(loop.start);
        final boundStr = loopBound(loop.bound);
        var readsIndex = false;
        for (statement in loop.body)
            if (mentionsLocal(statement, loop.index)) {
                readsIndex = true;
                break;
            }
        final loopName = readsIndex ? name : "_";
        final out = [indent(depth) + "for " + loopName + " in " + startStr + ".." + boundStr + " {"];
        for (l in blockLines(loop.body, depth + 1))
            out.push(l);
        out.push(indent(depth) + "}");
        return out;
    }

    function sliceIterationSubject(loop:{
        index:TVar,
        start:TypedExpr,
        bound:TypedExpr,
        body:Array<TypedExpr>
    }):Null<TypedExpr> {
        final innerStart = stripWrap(loop.start);
        final isStartZero = switch (innerStart.expr) {
            case TConst(TInt(0)): true;
            case _: false;
        };
        if (!isStartZero)
            return null;
        // The element-loop rewrite drops the counter binding.  Keep the
        // explicit range loop whenever the remaining body reads that counter.
        for (statement in loop.body.slice(1))
            if (mentionsLocal(statement, loop.index))
                return null;
        final innerBound = stripWrap(loop.bound);
        return switch (innerBound.expr) {
            case TField(subj, fa) if (fieldName(fa) == "length"):
                if (EnumQueryExpander.collectionEnum(subj) != null)
                    return null;
                switch (stripWrap(subj).expr) {
                    case TLocal(_): subj;
                    case _: null;
                }
            case _: null;
        };
    }

    function sliceItemVar(body:Array<TypedExpr>, indexVar:TVar, sliceSubj:TypedExpr):Null<TVar> {
        if (body.length == 0)
            return null;
        return switch (body[0].expr) {
            case TVar(itemVar, init) if (init != null):
                switch (stripWrap(init).expr) {
                    case TArray(subj, idx):
                        final subjOk = switch [stripWrap(subj).expr, stripWrap(sliceSubj).expr] {
                            case [TLocal(s1), TLocal(s2)]: s1.id == s2.id;
                            case _: false;
                        };
                        final idxOk = switch (stripWrap(idx).expr) {
                            case TLocal(iv): iv.id == indexVar.id;
                            case _: false;
                        };
                        if (subjOk && idxOk) itemVar else null;
                    case _: null;
                }
            case _: null;
        };
    }

    function loopBound(bound:TypedExpr):String {
        final inner = stripWrap(bound);
        switch (inner.expr) {
            case TField(subj, fa) if (fieldName(fa) == "length"):
                final enumCollection = EnumQueryExpander.collectionEnum(subj);
                if (enumCollection != null)
                    return Std.string(EnumQueryExpander.constructorCount(enumCollection));
                if (isNullType(subj.t) || isImplicitNullableLocal(subj) || isNoneInitializedLocal(subj)) {
                    final collapsed = switch (stripWrap(subj).expr) {
                        case TLocal(v): nullableCollapsedLocals.exists(v.id)
                            || hasGuardedTernaryLocals.exists(v.id);
                        case _: false;
                    };
                    final narrowed = narrowedSubject(subj);
                    if (collapsed)
                        return rustU32Length(expr(subj) + ".len()");
                    if (narrowed != null) {
                        optionNarrowingHitCount++;
                        return rustU32Length(narrowed + ".len()");
                    }
                    return "(" + expr(subj) + ").as_ref().map_or(0, |v| v.len())";
                }
                return rustU32Length(expr(subj) + ".len()");
            case _:
                final text = expr(bound);
                // A signed i32 range endpoint crosses into the u32 range
                // domain with a clamp: a negative bound yields an empty
                // range, the Haxe loop behavior for a negative bound.
                if (isIntType(bound.t) && !isNullType(bound.t) && i32LocalDomain(bound))
                    return "u32::try_from(" + text + ").unwrap_or(0)";
                return text;
        }
    }

    // ------------------------------------------------------------------
    // Counted fill (Vec::with_capacity)
    // ------------------------------------------------------------------

    function fillFusion(stmts:Array<TypedExpr>, i:Int, depth:Int):Null<Array<String>> {
        final alloc = FusionPlan.allocOf(stmts, i);
        if (alloc == null) {
            return null;
        }
        final loop = matchInterval(stmts[i + 1]);
        if (loop == null) {
            return null;
        }
        final plan = FusionPlan.plan(alloc, loop);
        if (plan == null) {
            return null;
        }

        final arrName = RustImports.toSnakeCase(localName(plan.arr));
        final arrElementType = arrayElementType(plan.arr.t);
        final capStr = capacityExpr(plan.loop.bound);
        final boundStr = loopBound(plan.loop.bound);
        final loopIndexName = RustImports.toSnakeCase(plan.loop.index.name);
        final loopVar = plan.readsIndex ? loopIndexName : "_";

        final out:Array<String> = [];
        out.push(indent(depth) + "let capacity = " + capStr + ";");
        out.push(indent(depth) + "let mut " + arrName + " = Vec::with_capacity(capacity);");
        out.push(indent(depth) + "for " + loopVar + " in 0.." + boundStr + " {");
        for (step in plan.steps) {
            switch (step) {
                case NonStoreBatch(batch):
                    for (l in blockLines(batch, depth + 1))
                        out.push(l);
                case StoreValue(value):
                    out.push(indent(depth + 1) + arrName + ".push(" + renderPushArg(value, arrElementType) + ");");
                case PushValue(arg):
                    out.push(indent(depth + 1) + arrName + ".push(" + renderPushArg(arg, arrElementType) + ");");
            }
        }
        out.push(indent(depth) + "}");
        return out;
    }

    function sortedKeyType(fn:TypedExpr):Null<haxe.macro.Type.Type> {
        return switch (fn.t) {
            case TFun(_, TInst(_, params)) if (params.length > 0): params[0];
            case _: null;
        };
    }

    function sortedValueType(fn:TypedExpr):Null<haxe.macro.Type.Type> {
        final v = switch (fn.t) {
            case TFun(_, TInst(_, params)) if (params.length > 1): params[1];
            case _: null;
        };
        if (v == null)
            return null;
        // Haxe erases Null for value types (Int, Float, Bool): a
        // SortedMap<K, Null<Float>> stores plain Float and its get()
        // returns Option<Float>. The builder's value slot must carry the
        // erased scalar so the map's value type and the get() Option
        // agree with the arithmetic consumers.
        if (isNullType(v) && isTypeCopy(getNullInnerType(v)))
            return getNullInnerType(v);
        return v;
    }

    /** Whether a SortedMap/SortedMapBuilder receiver's value type is Null-wrapped. */
    function sortedMapValueTypeIsNullable(subj:TypedExpr):Bool {
        final t = methodSubjectType(subj);
        return switch (Context.follow(t)) {
            case TInst(c, params) if (params.length > 1 && (c.get().name == "SortedMap" || c.get().name == "SortedMapBuilder")):
                // Haxe erases Null for value types (Int, Float, Bool): a
                // SortedMap<K, Null<Float>> stores plain Float and its get()
                // returns a single Option<Float>. The double-Option flatten
                // applies only to a Null-wrapped non-value type, which keeps
                // the extra Option layer.
                if (isNullType(params[1])) {
                    switch (Context.follow(getNullInnerType(params[1]))) {
                        case TAbstract(a, _):
                            final n = a.get().name;
                            n == "Int" || n == "Bool" || n == "Float" || n == "Int64" ? false : true;
                        case _: true;
                    };
                } else {
                    false;
                };
            case _: false;
        };
    }

    /**
        Comparator a builder site binds: the resident integer walk
        adapted to the unsigned business domain, the resident string
        walk, or the per-structure generated comparator.
    **/
    public function sortedComparator(kType:Null<haxe.macro.Type.Type>, pos:haxe.macro.Expr.Position):String {
        if (kType == null) {
            Context.error("sorted builder requires an explicit key type", pos);
        }
        return switch (RustType.classifyKey(kType, pos)) {
            case IntKey:
                imports.require("std::sync::Arc");
                "Arc::new(|a, b| SortedTable::sorted_table_compare_ints("
                + RustConversions.reinterpret("(*a)", "i32")
                + ", "
                + RustConversions.reinterpret("(*b)", "i32")
                + "))";
            case StringKey:
                imports.require("std::sync::Arc");
                "Arc::new(|a, b| SortedTable::sorted_table_compare_strings(a.as_str(), b.as_str()))";
            case StructKey(def, _):
                final cmpName = "compare_" + RustImports.toSnakeCase(def.name);
                imports.requireType(def.module, cmpName);
                imports.require("std::sync::Arc");
                "Arc::new(" + cmpName + ")";
            case DataClassKey(cls, _):
                final cmpName = "compare_" + RustImports.toSnakeCase(cls.name);
                imports.requireType(cls.module, cmpName);
                imports.require("std::sync::Arc");
                "Arc::new(" + cmpName + ")";
            case EnumKey(en):
                imports.requireType(en.module, "compare_" + RustImports.toSnakeCase(en.name));
                imports.require("std::sync::Arc");
                "Arc::new(compare_" + RustImports.toSnakeCase(en.name) + ")";
        };
    }

    /**
        Every table parameter borrows: keys and values arrive as
        references and the resident clones what it stores. String keys
        construct when the expression is a literal or a borrowed &str.
    **/
    function sortedRefArg(arg:TypedExpr):String {
        if (isStringType(arg.t)) {
            switch (stripWrap(arg).expr) {
                case TConst(TString(_)):
                    return "&(" + expr(arg) + ").to_string()";
                case TLocal(v):
                    final pt = types.of(v.t, true);
                    return pt == "&str" ? "&(" + expr(arg) + ").to_string()" : "&" + expr(arg);
                case _:
                    return "&" + expr(arg);
            }
        }
        // An implicit-nullable local (declared non-null but initialized from
        // a nullable expression) keeps Option storage; a table put borrows
        // the inner value, so the read unwraps the Option once. A
        // nullable-collapsed local holds the scalar domain and must not
        // unwrap here.
        if (isImplicitNullableLocal(arg) && !isNullableCollapsedLocal(arg))
            return "&(" + expr(arg) + ").as_ref().unwrap()";
        return "&(" + expr(arg) + ")";
    }

    function isNullableCollapsedLocal(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TLocal(v): nullableCollapsedLocals.exists(v.id);
            case _: false;
        };
    }

    /** A local declared with a non-null type but initialized from a nullable
        expression keeps Option storage at runtime. **/
    function isImplicitNullableLocal(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TLocal(v): implicitNullableLocals.exists(v.id);
            case _: false;
        };
    }

    function isNoneInitializedLocal(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TLocal(v): noneInitializedLocals.exists(v.id);
            case _: false;
        };
    }

    function isNonNullRenderedLocal(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TLocal(v): nonNullRenderedLocals.exists(v.id);
            case _: false;
        };
    }

    function isBorrowedLocal(v:haxe.macro.Type.TVar):Bool {
        // A closure parameter is rendered with the parameter mapping, so a
        // String, Array, or Bytes parameter is a reference view even though
        // it never enters the enclosing function's argument table.
        if (closureParamIds.exists(v.id))
            return StringTools.startsWith(types.of(v.t, true), "&");
        // argTypes accumulates across functions, so a name match alone can
        // read a previous function's parameter; only a current-function
        // parameter is borrowed.
        if (!paramVarIds.exists(v.id))
            return false;
        final stored = argTypes.get(v.name);
        return stored != null && StringTools.startsWith(stored, "&");
    }

    /**
        isBorrowedParamLocal: a current-function parameter keeps the borrow
        its declaration already decided, and a closure parameter borrows
        when its rendered parameter type is a reference view. The String
        conversion sites use this test so a borrowed parameter reaches an
        owned String slot through to_string.
    **/
    function isBorrowedParamLocal(v:haxe.macro.Type.TVar):Bool {
        if (closureParamIds.exists(v.id))
            return StringTools.startsWith(types.of(v.t, true), "&");
        return paramVarIds.get(v.id) == true;
    }

    /**
        borrowedArrayRead: an ordinary Array<T> parameter lowers to a &Vec<T>
        view whose storage stays with the caller. An owned Vec slot that
        receives the read (a return value, an assignment target, or an
        Option<Vec<T>> payload) must clone the referent once at that boundary.
        The named rule covers the census E0308 family that reported expected
        Vec<T> against found &Vec<T>; the borrowed-array boundary suite covers
        the call, return, and assignment positions.
    **/
    function borrowedArrayRead(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TLocal(v): isBorrowedLocal(v);
            case _: false;
        };
    }

    /**
        isBorrowedExpression: true when the Rust rendering of this expression
        produces a reference; an owned value is not produced. Covers borrowed
        parameters, loop variables, and reference-bearing fields. The caller
        clones a non-Copy field read when the access goes through a borrow,
        preventing E0507 move-out-of-reference errors.
    **/
    function isBorrowedExpression(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TLocal(v): isBorrowedLocal(v) || borrowedLoopVarIds.exists(v.id);
            case TField(inner, _): isBorrowedExpression(inner);
            case TArray(inner, _): isBorrowedExpression(inner);
            case TCast(inner, _) | TMeta(_, inner) | TParenthesis(inner): isBorrowedExpression(inner);
            case _: false;
        };
    }

    /**
        isOwnedVecType: both Array<T> and ReadOnlyArray<T> lower to an owned
        Vec<T> outside parameter position. The nullable and return boundaries
        that own their storage share this test.
    **/
    function isOwnedVecType(t:Null<Type>):Bool {
        return StaticFieldHelper.isArrayType(t) || StaticFieldHelper.isReadOnlyArrayType(t);
    }

    /**
        nullableArrayPayload: an Option<Vec<T>> slot owns its storage. A
        direct array static converts with to_vec; a reusable read (a borrowed
        parameter view or an owned local or field) clones so the slot owns the
        storage and the read stays usable; a fresh temporary already owns and
        passes through.
    **/
    function nullableArrayPayload(arg:TypedExpr, argStr:String):String {
        if (isDirectArrayStaticRead(arg))
            return argStr + ".to_vec()";
        if ((isReusableOwnedRead(arg) || borrowedArrayRead(arg))
            && !StringTools.endsWith(argStr, ".clone()") && !StringTools.endsWith(argStr, ".to_vec()"))
            return ownedNullableReadText(argStr);
        return argStr;
    }

    /**
        isReusableNullableRead: an Option slot owns a non-Copy payload. A
        reusable read (a local or field, borrowed or owned) clones once at the
        boundary so the Option owns the value and the read stays usable; a
        freshly constructed value passes through. This covers arrays and
        resident containers that enter nullable parameters.
    **/
    function isReusableNullableRead(pt:Type, arg:TypedExpr, argStr:String):Bool {
        final inner = getNullInnerType(pt);
        return !isTypeCopy(inner) && !isStringType(inner)
            && (isReusableOwnedRead(arg) || borrowedArrayRead(arg))
            && !StringTools.endsWith(argStr, ".clone()")
            && !StringTools.endsWith(argStr, ".to_vec()");
    }

    function ownedNullableReadText(argStr:String):String {
        return StringTools.startsWith(argStr, "&") ? "(*" + argStr + ").clone()" : "(" + argStr + ").clone()";
    }

    /**
        reusableReadText: a rendered expression that names a reusable value
        (an identifier or a field path). Fresh temporaries end in a call,
        index, block, or literal delimiter and keep their ownership.
    **/
    function reusableReadText(text:String):Bool {
        if (text == "None" || text == "true" || text == "false" || text.length == 0)
            return false;
        return switch (text.charAt(text.length - 1)) {
            case ")" | "]" | "}" | "\"": false;
            case _: true;
        };
    }

    function renderPushArg(arg:TypedExpr, elementType:Null<Type> = null):String {
        var argStr = expr(arg);
        // A narrowed binding deref carries the signed i32 inner domain; a
        // business Int element slot holds u32, so the value reinterprets
        // once at the push boundary. (SortedPutValueAdaptation)
        if (elementType != null && isIntType(elementType)
            && narrowedSubject(arg) != null && isIntType(getNullInnerType(arg.t)))
            argStr = RustConversions.reinterpret(argStr, "u32");
        // A non-null value pushed into a nullable-element array (Array<Null<T>>
        // lowers to Vec<Option<T>>) wraps in Some so the element slot matches.
        // The null literal already renders None and stays bare.
        if (elementType != null && isNullType(elementType) && !isNullType(arg.t) && !isTNull(arg)) {
            return "Some(" + argStr + ")";
        }
        // A nullable value pushed into a nullable-element array already
        // carries the Option the slot expects; pass it through unchanged.
        // Unwrapping it here would strip the Option a Vec<Option<T>> slot
        // requires (E0308). Owned inners clone so the array owns its element.
        if (elementType != null && isNullType(elementType) && isNullType(arg.t) && !isTNull(arg)) {
            if (!isTypeCopy(getNullInnerType(arg.t))) {
                if (!StringTools.endsWith(argStr, ".clone()")
                    && !StringTools.endsWith(argStr, ".to_vec()")
                    && !StringTools.endsWith(argStr, ".to_string()")) {
                    argStr = argStr + ".clone()";
                }
            }
            return argStr;
        }
        // An i32-domain value pushed into a business u32 array reinterprets
        // its bits; the element slot is the u32 domain.
        if (!isNullType(arg.t) && !RuntimeResidents.isResident(imports.selfModule) && i32LocalDomain(arg))
            argStr = RustConversions.reinterpret(argStr, "u32");
        // A narrowed read already lowers to the match binding, a reference
        // to the inner value: the push dereferences it for Copy inners and
        // clones for the owned kinds, with no Option left to unwrap.
        if (isNullType(arg.t)) {
            final narrowed = narrowedSubject(arg);
            if (narrowed != null) {
                return isTypeCopy(getNullInnerType(arg.t)) ? "*" + narrowed : "(" + narrowed + ").clone()";
            }
        }
        if (isNullType(arg.t) && !(switch (stripWrap(arg).expr) {
            case TLocal(v): nullableCollapsedLocals.exists(v.id);
            case _: false;
        })) {
            // A null literal already renders `None`; unwrapping it would
            // produce the invalid `None.unwrap()`. Only a non-null nullable
            // value (a Some-carrying Option) unwraps into the element slot.
            if (isTNull(arg)) {
                return argStr;
            }
            argStr = argStr + ".unwrap()";
            if (!isTypeCopy(getNullInnerType(arg.t))) {
                if (!StringTools.endsWith(argStr, ".clone()")
                    && !StringTools.endsWith(argStr, ".to_vec()")
                    && !StringTools.endsWith(argStr, ".to_string()")) {
                    argStr = argStr + ".clone()";
                }
            } else if (isIntType(getNullInnerType(arg.t)) && (parseIntLocals.exists(switch (stripWrap(arg).expr) {
                case TLocal(v): v.id;
                case _: -1;
            }) || isStdParseIntCall(arg))) {
                // A nullable parseInt or i32-domain Int unwraps to i32 while
                // the array element slot is the business u32 domain.
                argStr = RustConversions.reinterpret(argStr, "u32");
            }
            return argStr;
        }
        if (!isTypeCopy(arg.t)) {
            switch (stripWrap(arg).expr) {
                // The base constant renderer emits a bare &str literal, so
                // pushing one into a String array needs an owned conversion.
                case TConst(TString(_)):
                    argStr = argStr + ".to_string()";
                case TNew(_, _, _):
                case TLocal(v) if (isBorrowedLocal(v)):
                    // The local holds a reference (a borrowed parameter).
                    // A String parameter is &str, which owns through
                    // to_string(); any other reference clones the referent
                    // so the array owns its element.
                    argStr = isStringType(arg.t) ? argStr + ".to_string()" : "(*" + argStr + ").clone()";
                case TLocal(_) | TField(_) | TArray(_, _):
                    if (!StringTools.endsWith(argStr, ".clone()")
                        && !StringTools.endsWith(argStr, ".to_vec()")
                        && !StringTools.endsWith(argStr, ".to_string()")) {
                        argStr = argStr + ".clone()";
                    }
                default:
            }
        }
        return argStr;
    }

    function capacityExpr(bound:TypedExpr):String {
        // Constant and length bounds cannot overflow; every other bound needs
        // the overflow variant of the resolved error enum.
        final inner = stripWrap(bound);
        switch (inner.expr) {
            case TConst(TInt(n)) if (n >= 0):
                return Std.string(n);
            case TField(subj, fa) if (fieldName(fa) == "length"):
                if (isNullType(subj.t) || isImplicitNullableLocal(subj) || isNoneInitializedLocal(subj)) {
                    final collapsed = switch (stripWrap(subj).expr) {
                        case TLocal(v): nullableCollapsedLocals.exists(v.id)
                            || hasGuardedTernaryLocals.exists(v.id);
                        case _: false;
                    };
                    final narrowed = narrowedSubject(subj);
                    if (collapsed)
                        return expr(subj) + ".len()";
                    if (narrowed != null) {
                        optionNarrowingHitCount++;
                        return narrowed + ".len()";
                    }
                    return "(" + expr(subj) + ").as_ref().map_or(0, |v| v.len())";
                }
                return expr(subj) + ".len()";
            case _:
                if (errorTypeName == null || countOverflowVariant == null) {
                    // Haxe Int is u32; the T3 index form widens it to usize
                    // infallibly, so an Int bound in a function without an
                    // error enum needs no overflow variant.
                    if (isIntType(bound.t))
                        return usizeIndex(expr(bound));
                    Context.error("cannot lower fallible capacity expression: missing error enum or overflow variant", bound.pos);
                    return "0";
                }
                final errVariant = errorTypeName + "::" + countOverflowVariant;
                return "usize::try_from(" + expr(bound) + ").map_err(|_| " + errVariant + ")?";
        }
    }

    // ------------------------------------------------------------------
    // Expressions
    // ------------------------------------------------------------------

    function nullGuardOf(e:TypedExpr):Null<{subject:TypedExpr, noneWhenTrue:Bool}> {
        switch (stripWrap(e).expr) {
            case TBinop(OpEq, left, right) if (nullableGuardSubject(left) && isTNull(right)):
                return {subject: left, noneWhenTrue: true};
            case TBinop(OpEq, left, right) if (nullableGuardSubject(right) && isTNull(left)):
                return {subject: right, noneWhenTrue: true};
            case TBinop(OpNotEq, left, right) if (nullableGuardSubject(left) && isTNull(right)):
                return {subject: left, noneWhenTrue: false};
            case TBinop(OpNotEq, left, right) if (nullableGuardSubject(right) && isTNull(left)):
                return {subject: right, noneWhenTrue: false};
            case _:
        }
        return null;
    }

    /** A guard subject is nullable when its type is Null<T>, or when a
        non-null local is backed by a nullable initializer (its Rust storage
        is Option<T>). **/
    function nullableGuardSubject(subject:TypedExpr):Bool {
        if (isNullType(subject.t))
            return true;
        return switch (stripWrap(subject).expr) {
            case TLocal(v): implicitNullableLocals.exists(v.id);
            case _: false;
        };
    }

    function subjectTextOf(subject:TypedExpr):String {
        return switch (stripWrap(subject).expr) {
            case TLocal(v): subst.exists(v.id) ? subst.get(v.id) : RustImports.toSnakeCase(localName(v));
            case TField(receiver, FInstance(_, _, cf)) | TField(receiver, FAnon(cf)):
                // A nullable receiver holds Option<T>; the field path must
                // open it before the member read, or the path addresses the
                // Option itself (E0609). A narrowed receiver already binds
                // the inner value (the match binding), so the path uses the
                // binding directly, matching the field() read path. A
                // proven-non-null or wrapper-backed receiver unwraps through
                // the same forcing read field() uses.
                final recv = if (narrowedSubject(receiver) != null) narrowedSubject(receiver)
                    else if (provenNonNullLocalSubject(receiver) != null) provenNonNullLocalSubject(receiver)
                    else if (fieldReceiverCarriesFallibleWrapper(receiver)) expr(receiver) + ".as_ref().unwrap()"
                    else expr(receiver);
                recv + "." + RustImports.toSnakeCase(cf.get().name);
            case _: expr(subject);
        };
    }

    /**
        Renders a boolean operand. When the Haxe type is Null<Bool>,
        unwraps with .unwrap_or(false) because null is falsy in Haxe.
    **/
    function nullableBoolOperand(e:TypedExpr, text:String):String {
        if (isNullType(e.t) && isBoolType(getNullInnerType(e.t))) {
            // A nullable-collapsed local holds the inner bool (its
            // null-coalescing initializer materialized the value), so the
            // unwrap_or(false) forcing read must not re-apply.
            if (switch (stripWrap(e).expr) {
                case TLocal(v): nullableCollapsedLocals.exists(v.id);
                case _: false;
            })
                return text;
            return text + ".unwrap_or(false)";
        }
        return text;
    }

    function narrowedSubject(subject:TypedExpr):Null<String> {
        return narrowedText(subjectTextOf(subject));
    }

    /**
        Field reads in a null-guarded boolean chain use the match binding of
        their receiver. This covers `value != null && value.field` after the
        receiver narrowing has been registered, while complete guarded paths
        continue to use narrowedSubject directly. A read below a non-null
        member keeps that member on the path, so the binding replaces only
        the narrowed base of the chain.
    **/
    function narrowedReceiverSubject(subject:TypedExpr):Null<String> {
        return switch (stripWrap(subject).expr) {
            case TField(receiver, FInstance(_, _, cf)) | TField(receiver, FAnon(cf)):
                final base = switch (narrowedSubject(receiver)) {
                    case null: narrowedReceiverSubject(receiver);
                    case text: text;
                };
                base == null ? null : base + "." + RustImports.toSnakeCase(cf.get().name);
            case _:
                null;
        };
    }

    function narrowedText(text:String):Null<String> {
        for (i in 0...optionNarrowings.length) {
            final narrowing = optionNarrowings[optionNarrowings.length - 1 - i];
            if (narrowing.subjectText == text)
                return narrowing.name;
        }
        return null;
    }

    /** The owned inner value a `Null<T>` assignment receives from a `T` right side. */
    function ownedNullAssignValue(r:TypedExpr):String {
        if (isTypeCopy(r.t))
            return expr(r);
        return switch (stripWrap(r).expr) {
            // A literal is a &str while the Null target owns
            // Option<String>; clone does not exist on str.
            case TConst(TString(_)): expr(r) + ".to_string()";
            // A borrowed String parameter is a &str view; the owned
            // Option<String> slot converts its text once.
            case TLocal(v) if (isBorrowedLocal(v) && isStringType(r.t)):
                final borrowed = expr(r);
                StringTools.endsWith(borrowed, ".to_string()") ? borrowed : borrowed + ".to_string()";
            case _:
                final s = expr(r);
                if (!StringTools.endsWith(s, ".clone()")
                    && !StringTools.endsWith(s, ".to_vec()")
                    && !StringTools.endsWith(s, ".to_string()")) {
                    s + ".clone()";
                } else {
                    s;
                }
        };
    }

    /** The owned inner value a `Null<Interface>` assignment receives from a concrete `T` right side. */
    function ownedNullInterfaceAssignValue(r:TypedExpr):String {
        final s = expr(r);
        return "Box::new(" + normalizeConstructorResult(r, s) + ")";
    }

    /**
        A `if (x == null) x = fill;` statement with no else arm registers the
        fill for the rest of its block: after the statement the local holds
        the filled value, so a later forcing read of `x` reuses the fill as
        the `get_or_insert_with` closure body. Only a plain
        local assigned exactly once in the arm qualifies.
    **/
    function fillNarrowingOf(e:TypedExpr):Null<{subjectText:String, fillBody:String}> {
        switch (e.expr) {
            case TIf(c, t, f) if (f == null):
                final info = nullGuardOf(c);
                if (info == null || !info.noneWhenTrue)
                    return null;
                switch (stripWrap(info.subject).expr) {
                    case TLocal(_):
                    case _: return null;
                }
                final body = statementsOf(t);
                if (body.length != 1)
                    return null;
                switch (stripWrap(body[0]).expr) {
                    case TBinop(OpAssign, l, r):
                        switch [stripWrap(l).expr, stripWrap(info.subject).expr] {
                            case [TLocal(assigned), TLocal(subject)] if (assigned.id == subject.id):
                                if (isNullType(r.t) || isTNull(r))
                                    return null;
                                return {subjectText: subjectTextOf(info.subject), fillBody: ownedNullAssignValue(r)};
                            case _:
                        }
                    case _:
                }
            case _:
        }
        return null;
    }

    function filledSubjectOf(subject:TypedExpr):Null<String> {
        final text = subjectTextOf(subject);
        for (i in 0...fillNarrowings.length) {
            final fill = fillNarrowings[fillNarrowings.length - 1 - i];
            if (fill.subjectText == text)
                return fill.fillBody;
        }
        return null;
    }

    function nullGuardPrefix(e:TypedExpr):Null<{info:{subject:TypedExpr, noneWhenTrue:Bool}, tail:TypedExpr}> {
        return switch (stripWrap(e).expr) {
            case TBinop(OpBoolAnd, left, right):
                final info = nullGuardOf(left);
                info == null || info.noneWhenTrue ? null : {info: info, tail: right};
            case _:
                null;
        };
    }

    /**
        A ternary `map.has(k) ? map.get(k) : value` narrows the get: the
        has guard proves the key is present, so the get's Option unwraps to
        the inner value and the fallback stays plain. Without this, the get
        renders as Option<T> and the fallback wraps in Some, leaving an
        Option<T> that later arithmetic/argument slots reject (E0277/E0308).
        Covers the has-guarded get value-flow family.
    **/
    function hasGuardGetInfo(cond:TypedExpr):Null<{subj:String, key:String}> {
        return switch (stripWrap(cond).expr) {
            case TCall(fn, args) if (args.length == 1):
                switch (stripWrap(fn).expr) {
                    case TField(subj, FInstance(_, _, cf)) if (cf.get().name == "has" && (isSortedTable(subj) || isSortedBuilder(subj))):
                        {subj: subjectTextOf(subj), key: subjectTextOf(args[0])};
                    case _: null;
                };
            case _: null;
        };
    }

    /** Whether a local initialized from `map.get(key)` is under a matching
        `map.has(key)` guard, so it holds the inner value. **/
    function hasGuardedGetLocal(init:TypedExpr):Bool {
        final getInfo = switch (stripWrap(init).expr) {
            case TCall(fn, args) if (args.length == 1):
                switch (stripWrap(fn).expr) {
                    case TField(subj, FInstance(_, _, cf)) if (cf.get().name == "get" && (isSortedTable(subj) || isSortedBuilder(subj))):
                        {subj: subjectTextOf(subj), key: subjectTextOf(args[0])};
                    case _: null;
                };
            case _: null;
        };
        if (getInfo == null)
            return false;
        for (i in 0...hasGuardedGets.length) {
            final guard = hasGuardedGets[hasGuardedGets.length - 1 - i];
            if (guard.subj == getInfo.subj && guard.key == getInfo.key)
                return true;
        }
        return false;
    }

    /** Whether an expression is `map.get(key)` under a matching `map.has(key)`
        guard, so it holds the inner value. **/
    function hasGuardedGetExpr(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TCall(fn, args) if (args.length == 1):
                switch (stripWrap(fn).expr) {
                    case TField(subj, FInstance(_, _, cf)) if (cf.get().name == "get" && (isSortedTable(subj) || isSortedBuilder(subj))):
                        final getInfo = {subj: subjectTextOf(subj), key: subjectTextOf(args[0])};
                        var found = false;
                        for (i in 0...hasGuardedGets.length) {
                            final guard = hasGuardedGets[hasGuardedGets.length - 1 - i];
                            if (guard.subj == getInfo.subj && guard.key == getInfo.key) {
                                found = true;
                                break;
                            }
                        }
                        found;
                    case _: false;
                };
            case _: false;
        };
    }

    /** Strips balanced outer parentheses from a rendered expression so
        arm-to-subject text comparisons see through wrapper renders.
        (NoneZeroFold) */
    function stripRenderedParens(text:String):String {
        var cur = text;
        while (StringTools.startsWith(cur, "(") && StringTools.endsWith(cur, ")") && matchingParens(cur))
            cur = cur.substr(1, cur.length - 2);
        return cur;
    }

    /** Extracts the compared subject and polarity from a `s == null` /
        `s != null` condition. The null literal may stand on either side.
        (NoneZeroFold) */
    function nullComparisonParts(cond:TypedExpr):Null<{subject:TypedExpr, inverted:Bool}> {
        return switch (stripWrap(cond).expr) {
            case TBinop(OpEq, s, {expr: TConst(TNull)}): {subject: s, inverted: false};
            case TBinop(OpEq, {expr: TConst(TNull)}, s): {subject: s, inverted: false};
            case TBinop(OpNotEq, s, {expr: TConst(TNull)}): {subject: s, inverted: true};
            case TBinop(OpNotEq, {expr: TConst(TNull)}, s): {subject: s, inverted: true};
            case _: null;
        };
    }

    function hasGuardedGetTernary(cond:TypedExpr, ifTrue:TypedExpr, ifFalse:TypedExpr, resultType:Type):Null<String> {
        // The condition must be `map.has(key)`.
        final hasInfo = switch (stripWrap(cond).expr) {
            case TCall(fn, args) if (args.length == 1):
                switch (stripWrap(fn).expr) {
                    case TField(subj, FInstance(_, _, cf)) if (cf.get().name == "has" && (isSortedTable(subj) || isSortedBuilder(subj))):
                        {subj: subj, key: args[0]};
                    case _: null;
                };
            case _: null;
        };
        if (hasInfo == null)
            return null;
        // The true branch must be `map.get(key)` on the same receiver/key.
        final getInfo = switch (stripWrap(ifTrue).expr) {
            case TCall(fn, args) if (args.length == 1):
                switch (stripWrap(fn).expr) {
                    case TField(subj, FInstance(_, _, cf)) if (cf.get().name == "get" && (isSortedTable(subj) || isSortedBuilder(subj))):
                        {subj: subj, key: args[0]};
                    case _: null;
                };
            case _: null;
        };
        if (getInfo == null)
            return null;
        if (Context.getPosInfos(cond.pos).min > 0 && StringTools.startsWith(Std.string(currentMethodName), "unknown") == false) {}
        final hSubj = subjectTextOf(hasInfo.subj);
        final gSubj = subjectTextOf(getInfo.subj);
        final hKey = subjectTextOf(hasInfo.key);
        final gKey = subjectTextOf(getInfo.key);
        if (hSubj != gSubj)
            return null;
        if (hKey != gKey)
            return null;
        // The get renders as Option<T>; unwrap it since has proved presence.
        // The fallback value stays plain (not Some-wrapped).
        final getText = expr(ifTrue);
        final fallback = isFloatType(emittedType(ifTrue)) && isIntType(emittedType(ifFalse))
            ? intToFloatText(expr(ifFalse))
            : expr(ifFalse);
        // The fallback must be a concrete non-null value so both arms of the
        // unwrapped ternary share the inner value type. A null literal keeps
        // the Option shape and must not be unwrapped here. A nullable macro
        // type is not disqualifying by itself: a nested guarded ternary
        // already unwrapped its own get(), so its rendered text carries the
        // inner value even though the macro type still reads Null. A block
        // wrapped nested ternary never ends in .unwrap(), so the test is a
        // containment check with a None-render guard.
        if (isTNull(ifFalse))
            return null;
        if (isNullType(ifFalse.t)
            && !(StringTools.contains(fallback, ").unwrap()") && fallback.indexOf("None") < 0)
            && !StringTools.startsWith(fallback, "*"))
            return null;
        return "if "
            + expr(cond)
            + " { "
            + "("
            + getText
            + ").unwrap()"
            + " } else { "
            + fallback
            + " }";
    }

    function guardedMatchExpression(guard:TypedExpr, ifTrue:TypedExpr, ifFalse:TypedExpr, resultType:Type):Null<String> {
        final prefix = nullGuardPrefix(guard);
        final info = prefix == null ? nullGuardOf(guard) : prefix.info;
        if (info == null)
            return null;
        final name = freshRegionName("__option");
        final countBefore = optionNarrowingHitCount;
        optionNarrowings.push({subjectText: subjectTextOf(info.subject), name: name});
        // The narrowed arm renders inside the narrowing scope so its
        // subject reads substitute the match binding; the None arm
        // renders after the scope because the binding does not exist
        // there.
        final narrowedBranch = info.noneWhenTrue ? ifFalse : ifTrue;
        final noneBranch = info.noneWhenTrue ? ifTrue : ifFalse;
        // A nullable result wraps both arms only when a sibling branch is
        // the null literal, so the arms reach the Option result shape. A
        // non-null sibling branch keeps the unwrapped value shape for both
        // arms. Wrapping runs inside the narrowing scope so a narrowed read
        // still binds the match name.
        final nullableResult = resultType != null && isNullType(resultType)
            && (isTNull(narrowedBranch) || isTNull(noneBranch)
                || (isInterfaceType(getNullInnerType(resultType))
                    && (isConcreteConstructor(narrowedBranch) || isConcreteConstructor(noneBranch))));
        var narrowedText = nullableResult ? wrapBranchForNullableResult(narrowedBranch, resultType, noneBranch)
            : conditionalBranchText(narrowedBranch, noneBranch, resultType);
        final tailText = prefix == null ? null : expr(prefix.tail);
        final hit = optionNarrowingHitCount > countBefore;
        optionNarrowings.pop();
        if (!hit)
            return null;
        // An arm that reads only the binding is a reference to the inner
        // value while the sibling arm yields the value itself: the arm
        // dereferences for Copy inners and clones for the owned kinds. A
        // nullable interface result keeps the Option shape, so the binding
        // read wraps in Some.
        if (narrowedText == name) {
            final innerType = getNullInnerType(info.subject.t);
            narrowedText = isTypeCopy(innerType) ? "*" + name : "(*" + name + ").clone()";
            if (nullableResult && isInterfaceType(innerType))
                narrowedText = "Some(" + narrowedText + ")";
        } else if (narrowedText == "(*" + name + ").clone()"
            && nullableResult && isInterfaceType(getNullInnerType(info.subject.t))) {
            // A narrowed field read renders the dereference and clone at the
            // read site (the full-path substitution in field()), so the arm
            // text never equals the bare binding name above. A nullable
            // interface result still needs the Some wrapper on this arm to
            // match the sibling constructor arm's Option shape.
            narrowedText = "Some(" + narrowedText + ")";
        }
        var noneText = nullableResult ? wrapBranchForNullableResult(noneBranch, resultType, narrowedBranch)
            : conditionalBranchText(noneBranch, narrowedBranch, resultType);
        if (tailText != null)
            narrowedText = "if " + tailText + " { " + narrowedText + " } else { " + noneText + " }";
        final branchTarget = conditionalNumericTarget(narrowedBranch, noneBranch, resultType);
        if (branchTarget != null) {
            narrowedText = normalizeNumericBranch(narrowedBranch, branchTarget, narrowedText);
            noneText = normalizeNumericBranch(noneBranch, branchTarget, noneText);
        }
        narrowedText = interfaceConditionalBranch(resultType, narrowedBranch, narrowedText);
        noneText = interfaceConditionalBranch(resultType, noneBranch, noneText);
        // The mirrored form: a dereferenced binding arm (`*name`) against a
        // sibling arm that renders an Option value (the null literal or a
        // Some-wrapped value). The dereferenced arm wraps in Some so both
        // arms carry Option<T>. A sibling rendering a bare inner value means
        // the slot is non-null and must not wrap. (NarrowedNullableParam)
        if (isNullType(resultType) && StringTools.startsWith(narrowedText, "*")
            && !StringTools.startsWith(narrowedText, "*(")
            && !StringTools.startsWith(narrowedText, "Some(")
            && (noneText == "None" || StringTools.startsWith(noneText, "Some(")))
            narrowedText = "Some(" + narrowedText + ")";
        // A field-read arm moves the field out of its base struct, but the
        // base stays owned by the caller and remains readable after the
        // coalescing; Haxe assignment keeps both sides alive, so a
        // non-Copy field-read arm clones. (OwnershipArmClone)
        function armOwnershipClone(branch:TypedExpr, text:String):String {
            if (isTypeCopy(branch.t))
                return text;
            final isFieldRead = switch (stripWrap(branch).expr) {
                case TField(_, FInstance(_, _, _)) | TField(_, FAnon(_)): true;
                case _: false;
            };
            return isFieldRead && !StringTools.endsWith(text, ".clone()") ? "(" + text + ").clone()" : text;
        }
        noneText = armOwnershipClone(noneBranch, noneText);
        narrowedText = armOwnershipClone(narrowedBranch, narrowedText);
        // Arms of one match must agree in shape. The match's own type
        // names the target; the minority arm adapts on its already
        // rendered text; the pass performs no speculative re-rendering.
        // (TypedSlotBoundary, ShapeParse)
        // An arm text outside the parser's coverage falls back to the
        // arm's own expression: a bare match-binding dereference reads as
        // the payload, a local reads through its declaration shape.
        // (ShapeParse)
        function armShapeOf(branch:TypedExpr, text:String):RustShape {
            final fromText = RustShapeParse.shapeOf(text);
            if (fromText != RustShape.ShapeUnknown)
                return fromText;
            if (StringTools.startsWith(StringTools.trim(text), "*"))
                return RustShape.ShapeBare;
            return switch (stripWrap(branch).expr) {
                case TLocal(v): declInitShape(v);
                case _: RustShape.ShapeUnknown;
            };
        }
        final armThen = armShapeOf(narrowedBranch, narrowedText);
        final armElse = armShapeOf(noneBranch, noneText);
        if ((armThen == RustShape.ShapeOption || armThen == RustShape.ShapeBare)
            && (armElse == RustShape.ShapeOption || armElse == RustShape.ShapeBare)
            && armThen != armElse) {
            final optionIsNarrowed = armThen == RustShape.ShapeOption;
            final optionText = optionIsNarrowed ? narrowedText : noneText;
            final bareText = optionIsNarrowed ? noneText : narrowedText;
            if (isNullType(resultType)) {
                final wrapped = "Some(" + bareText + ")";
                narrowedText = optionIsNarrowed ? narrowedText : wrapped;
                noneText = optionIsNarrowed ? wrapped : noneText;
            } else {
                final unwrapped = postfixAdapt(optionText, ".unwrap()");
                narrowedText = optionIsNarrowed ? unwrapped : narrowedText;
                noneText = optionIsNarrowed ? noneText : unwrapped;
            }
        }
        final subjectText = subjectTextOf(info.subject);
        final matchText = info.noneWhenTrue ? "match &("
            + subjectText
            + ") { None => "
            + noneText
            + ", Some("
            + name
            + ") => "
            + narrowedText
            + " }" : "match &("
            + subjectText
            + ") { Some("
            + name
            + ") => "
            + narrowedText
            + ", None => "
            + noneText
            + " }";
        // A nullable result wraps the whole match in Some(...) when both
        // arms are non-null values (the same rule
        // wrapBranchForNullableResult applies to plain ternaries); an arm
        // that already yields None/Some keeps the Option shape. A
        // Arms must share the Option shape: a concrete-constructor arm
        // renders Some(Box::new(...)) while the destructured arm renders
        // the bare payload clone; align the bare arm so both sides carry
        // Some and the match unifies on Option<T>.
        if (isNullType(resultType) && !isNullType(narrowedBranch.t) && !StaticFieldHelper.isNullableType(narrowedBranch.t)
            && !StringTools.startsWith(narrowedText, "Some(")
            && StringTools.startsWith(noneText, "Some("))
            narrowedText = "Some(" + narrowedText + ")";
        // The mirrored form: a dereferenced binding arm (`*name`) against a
        // sibling arm that renders an Option value (a nullable local passed
        // through). The dereferenced arm wraps in Some so both arms carry
        // Option<T>. (NarrowedNullableParam)
        if (isNullType(resultType) && StringTools.startsWith(narrowedText, "*")
            && !StringTools.startsWith(narrowedText, "*(")
            && !StringTools.startsWith(narrowedText, "Some("))
            narrowedText = "Some(" + narrowedText + ")";
        // concrete-constructor arm of a Null<Interface> result already
        // wraps in Some(Box::new(...)) inside the match, so the outer
        // wrap must not re-apply.
        if (isNullType(resultType) && !isNullType(narrowedBranch.t) && !StaticFieldHelper.isNullableType(narrowedBranch.t)
            && !isNullType(noneBranch.t) && !StaticFieldHelper.isNullableType(noneBranch.t)
            && !(isInterfaceType(getNullInnerType(resultType))
                && (isConcreteConstructor(narrowedBranch) || isConcreteConstructor(noneBranch))))
            return "Some(" + matchText + ")";
        return matchText;
    }

    function guardedMatchStatements(guard:TypedExpr, ifTrue:TypedExpr, ifFalse:Null<TypedExpr>, depth:Int):Null<Array<String>> {
        final prefix = nullGuardPrefix(guard);
        final info = prefix == null ? nullGuardOf(guard) : prefix.info;
        if (info == null)
            return null;
        // A guard without an else arm narrows only the arm that exists;
        // an `x == null` guard keeps its narrowed code in the missing else
        // arm, so no narrowing region exists and the plain if survives.
        final narrowedBranch = info.noneWhenTrue ? ifFalse : ifTrue;
        if (narrowedBranch == null)
            return null;
        final name = freshRegionName("__option");
        final countBefore = optionNarrowingHitCount;
        optionNarrowings.push({subjectText: subjectTextOf(info.subject), name: name});
        var narrowed = blockLines(statementsOf(narrowedBranch), depth + 2);
        if (prefix != null) {
            narrowed = [indent(depth + 2) + "if " + expr(prefix.tail) + " {"]
                .concat(narrowed)
                .concat([indent(depth + 2) + "}"]);
        }
        final hit = optionNarrowingHitCount > countBefore;
        optionNarrowings.pop();
        if (!hit)
            return null;
        final otherBranch = info.noneWhenTrue ? ifTrue : ifFalse;
        final other = otherBranch == null ? [] : blockLines(statementsOf(otherBranch), depth + 2);
        final subjectText = expr(info.subject);
        final out = [indent(depth) + "match &(" + subjectText + ") {"];
        function arm(tag:String, lines:Array<String>):Void {
            out.push(indent(depth + 1) + tag + " => {");
            for (line in lines)
                out.push(line);
            out.push(indent(depth + 1) + "}");
        }
        if (info.noneWhenTrue) {
            arm("None", other);
            arm("Some(" + name + ")", narrowed);
        } else {
            arm("Some(" + name + ")", narrowed);
            arm("None", other);
        }
        out.push(indent(depth) + "}");
        return out;
    }

    function expr(e:TypedExpr):String {
        final int64Expr = int64Expression(e);
        if (int64Expr != null)
            return int64Expr;
        final wrapperValue = ValueTypeSupport.syntheticValue(e);
        if (wrapperValue != null)
            return valueTypeSynthetic(e, wrapperValue);
        final query = enumQuery(e);
        if (query != null)
            return query;
        switch (e.expr) {
            case TConst(c):
                switch (c) {
                    case TInt(v):
                        // Haxe Int is 32-bit two's-complement; the business
                        // module real is u32, so a negative literal carries
                        // the same bits as its wrapped unsigned decimal with
                        // an explicit u32 suffix: the suffix keeps boundary
                        // casts to i32 bit-preserving. Resident modules keep
                        // the signed i32 rendering.
                        if (v < 0 && !RuntimeResidents.isResident(imports.selfModule)) {
                            // A comparison against an i32-domain operand keeps
                            // the signed literal so both sides share one type.
                            if (i32ComparisonTarget)
                                return Std.string(v) + "i32";
                            return Std.string(v + 4294967296) + "u32";
                        }
                        return Std.string(v);
                    case TFloat(f):
                        final s = Std.string(f);
                        // Rust requires float literals to have an integer part; Haxe
                        // permits `.001` and `-.1` which the AST carries verbatim,
                        // so prepend the missing `0` before the decimal-point guard.
                        final withIntPart = s.length > 0
                            && s.charAt(0) == "." ? "0" + s : (s.length > 2
                                && s.charAt(0) == "-"
                                && s.charAt(1) == "." ? "-0" + s.substr(1) : s);
                        final padded = withIntPart.indexOf(".") >= 0
                            || withIntPart.indexOf("e") >= 0
                            || withIntPart.indexOf("E") >= 0 ? (StringTools.endsWith(withIntPart, ".") ? withIntPart + "0" : withIntPart) : withIntPart + ".0";
                        // Mark both precision configurations so method calls on a
                        // literal (for example `is_nan`) never leave its
                        // type to Rust inference.
                        if (FloatPrecision.isF32()) {
                            // A literal outside the f32 domain renders as the
                            // f32 value it rounds to: overflow renders as the
                            // signed infinity, underflow to zero as zero. Rust
                            // denies the out-of-range literal form itself.
                            // (Float32LiteralRange)
                            final v = Std.parseFloat(padded);
                            final abs = Math.abs(v);
                            if (abs > 3.4028234663852886e38)
                                return v < 0 ? "-f32::INFINITY" : "f32::INFINITY";
                            if (v != 0 && abs < 1.401298464324817e-45)
                                return "0.0f32";
                            return padded + "f32";
                        }
                        return padded + "f64";
                    case TString(s): return quoteString(s);
                    case TBool(b): return b ? "true" : "false";
                    case TNull: return "None";
                    case TThis: return thisBindingName;
                    case TSuper: return "super";
                    case _: return fail(e, "constant has no Rust lowering");
                }
            case TLocal(v):
                if (optionNarrowings.length > 0) {
                    final narrowed = narrowedSubject(e);
                    if (narrowed != null) {
                        optionNarrowingHitCount++;
                        // match &(opt) { Some(name) => ... } binds name as
                        // &T; dereference Copy inners so index and arithmetic
                        // expressions receive the owned scalar.
                        if (isTypeCopy(getNullInnerType(e.t)))
                            return "*" + narrowed;
                        return narrowed;
                    }
                }
                // A shared closure array read dereferences through the
                // mutex guard; index writes and pushes on the guard resolve
                // through DerefMut (SharedClosureArrays).
                if (sharedClosureArrays.exists(v.id))
                    return RustImports.toSnakeCase(localName(v)) + ".lock().unwrap()";
                // A shared closure scalar read dereferences through the
                // guard explicitly: binary operators do not auto-deref the
                // MutexGuard, so every value read needs the leading star.
                // Assignment targets place the same dereference through
                // assignTarget (SharedClosureScalars).
                if (sharedClosureScalars.exists(v.id)) {
                    // Copy scalars read through an explicit dereference
                    // (binary operators do not auto-deref the MutexGuard);
                    // non-Copy bindings read as method receivers on the
                    // guard, since a dereferenced read would move out of
                    // it. (SharedClosureScalars)
                    final star = isTypeCopy(v.t) ? "*" : "";
                    return star + RustImports.toSnakeCase(localName(v)) + ".lock().unwrap()";
                }
                if (subst.exists(v.id)) {
                    return subst.get(v.id);
                }
                // A capture copy converted to its owned String form reads
                // as a borrowed view: the body's &str consumers borrow the
                // closure's own copy.
                // (ClosureCaptureOwnedCopy)
                if (captureOwnedStringCopies.exists(v.id))
                    return RustImports.toSnakeCase(localName(v)) + ".as_str()";
                return RustImports.toSnakeCase(localName(v));
            case TArray(arr, idx):
                final mapReceiver = mapBackingReceiver(arr);
                if (mapReceiver != null) {
                    return expr(mapReceiver) + ".get(&" + rustMapKey(idx) + ").cloned()";
                }
                final staticGuard = staticGuardOf(arr);
                if (staticGuard != null) {
                    final base = staticGuard + "[" + staticIndex(idx) + "]";
                    return !isTypeCopy(e.t) ? "(" + base + ").clone()" : base;
                }
                final base = optionContainerIndexAccess(arr, idx, false);
                // Reading a String element moves it out of the Vec, so a
                // value read renders as a clone. Borrow consumers go
                // through arrayArgBorrow and skip the copy.
                // Reads from an owned Haxe Array must not move its element out of
                // the Rust Vec. Clone non-Copy values at the indexing boundary;
                // this is the value semantics promised by Haxe arrays.
                return !isTypeCopy(e.t) ? "(" + base + ").clone()" : base;
            case TBinop(op, l, r):
                return binop(e, op, l, r);
            case TUnop(op, post, subj):
                return unop(e, op, post, subj);
            case TField(subj, fa):
                return field(subj, fa);
            case TTypeExpr(t):
                return typeExpr(t);
            case TParenthesis(inner):
                return "(" + expr(inner) + ")";
            case TObjectDecl(fields):
                return objectLiteral(e, fields);
            case TArrayDecl(elems):
                final elemType = switch (Context.follow(e.t)) {
                    case TInst(c, params) if (c.get().name == "Array" && params.length > 0): params[0];
                    case _: null;
                };
                final isStringElem = elemType != null && isStringType(elemType);
                final isNullableElem = elemType != null && StaticFieldHelper.isNullableType(elemType);
                final elemFloat = isFloatType(elemType);
                // A non-Copy struct/enum element owns its storage; a Vec<T>
                // literal must clone each value so later uses of the source
                // binding stay alive (Haxe array literals are value-semantic).
                final elemNeedsClone = elemType != null && !isTypeCopy(elemType)
                    && !isStringType(elemType) && !isNullableElem;
                final rendered = [
                    for (x in elems) {
                        var inner = if (isStringElem) {
                            switch (stripWrap(x).expr) {
                                case TConst(TString(_)):
                                    expr(x) + ".to_string()";
                                case TLocal(v) if (isBorrowedParamLocal(v)):
                                    expr(x) + ".to_string()";
                                case _:
                                    expr(x) + ".clone()";
                            }
                        } else {
                            elemNeedsClone && !StringTools.endsWith(expr(x), ".clone()") ? "(" + expr(x) + ").clone()" : expr(x);
                        };
                        if (elemFloat && isIntType(emittedType(x))) inner = intToFloatText(inner);
                        // An i32-domain element in a business u32 array
                        // reinterprets its bits at the literal boundary.
                        if (!elemFloat && elemType != null && isIntType(elemType) && types.of(elemType, false) == "u32"
                            && i32LocalDomain(x) && !isNullType(x.t)) inner = RustConversions.reinterpret(inner, "u32");
                        if (isNullableElem && !isTNull(x) && !StaticFieldHelper.isNullableType(x.t)) {
                            "Some(" + inner + ")";
                        } else {
                            inner;
                        }
                    }
                ];
                return renderArrayLiteral(rendered, true);
            case TCall(fn, args):
                return call(fn, args);
            case TNew(c, params, args):
                return newExpr(c, params, args);
            case TMeta(_, inner):
                return expr(inner);
            case TCast(inner, target):
                // A cast from a Box<dyn Trait> to a concrete implementor
                // needs a downcast; the trait carries as_any for it. The
                // cast is guarded by an isOfType check in the source, so the
                // unwrap is safe.
                final targetCls = switch (target) {
                    case TClassDecl(ref): ref.get();
                    case _: null;
                };
                if (targetCls != null && !targetCls.isInterface) {
                    final innerType = Context.follow(inner.t);
                    final fromIface = switch (innerType) {
                        case TInst(ic, _): ic.get().isInterface;
                        case _: false;
                    };
                    if (fromIface)
                        return "(" + expr(inner) + ").as_any().downcast_ref::<" + targetCls.name + ">().unwrap()";
                }
                // A cast out of a nullable value into a non-null class
                // extracts the payload: the paired Std.isOfType fold proved
                // the value present, and the deferred or typed slot
                // receives the owned inner value.
                // (ProvenNonNullSlotUnwrap)
                if (targetCls != null && isNullType(inner.t)) {
                    final innerText = expr(inner);
                    if (RustShapeParse.shapeOf(innerText) != RustShape.ShapeBare) {
                        final ref = "(" + innerText + ").as_ref().unwrap()";
                        return isTypeCopy(getNullInnerType(inner.t)) ? "*" + ref : ref + ".clone()";
                    }
                }
                return expr(inner);
            case TEnumParameter(se, ef, index):
                // A collapsed single-case switch reads the payload outside
                // any match arm; a one-construct enum folds the read into an
                // exhaustive match, and anything wider stays in arms.
                final en = switch (Context.follow(se.t)) {
                    case TEnum(r, _): r.get();
                    case _: return fail(e, "payload read subject is not a variant value");
                };
                if (Lambda.count(en.constructs) != 1) {
                    return fail(e, "payload read of a multi-variant enum lowers inside a match arm only");
                }
                requireEnum(en.module, en.name);
                final pname = payloadName(ef, index);
                return "match "
                    + expr(se)
                    + " { "
                    + en.name
                    + "::"
                    + RustImports.toUpperCamelCase(ef.name)
                    + " { "
                    + pname
                    + ", .. } => "
                    + pname
                    + " }";
            case TEnumIndex(_):
                return fail(e, "enum index only lowers inside a variant switch");
            case TFunction(f):
                return functionValueLiteral(f, e.t);
            case TIf(c, t, f) if (f != null):
                // `if (S.is_none()) { zero } else { S }` folds to
                // S.unwrap_or(zero): the None branch contributes the numeric
                // zero of Haxe's null semantics. The zero-like arms are
                // matched against a small closed set of renders.
                // (NoneZeroFold)
                {
                    final condText = expr(c);
#if boring_fold_debug
                    Context.warning("CONDTXT [" + condText + "]", e.pos);
#end
                    if (StringTools.endsWith(condText, ".is_none()")) {
                        var subjectText = condText.substr(0, condText.length - ".is_none()".length);
                        while (StringTools.startsWith(subjectText, "(") && StringTools.endsWith(subjectText, ")")
                            && matchingParens(subjectText))
                            subjectText = subjectText.substr(1, subjectText.length - 2);
                        final thenText = expr(t);
                        final elseText = expr(f);
                        final zeroLike = (thenText == "0" || thenText == "0.0f64"
                            || thenText == "0.0" || thenText == "(0.0f64)"
                            || thenText == "(0 as f64)" || thenText == "0 as f64");
                        if (zeroLike && (elseText == subjectText || StringTools.startsWith(elseText, subjectText)))
                            return "(" + subjectText + ").unwrap_or(" + thenText + ")";
                    }
                }
                // The typed-AST form of the same fold: the Haxe condition is
                // `s == null` / `s != null` (the textual `.is_none()` render
                // only appears later, in boolean operand position).
                // (NoneZeroFold)
                {
                    final cmp = nullComparisonParts(c);
#if boring_fold_debug
                    Context.warning("FOLD3 t=" + Std.string(stripWrap(t).expr).substr(0, 70) + " f=" + Std.string(stripWrap(f).expr).substr(0, 70) + " cmp=" + (cmp != null), e.pos);
#end
                    // The fold renders no arm until pure AST checks pass. A
                    // speculative render of a composite arm routes the
                    // nested expression through the block validator
                    // (features/43) before any zero-text check can reject
                    // it: stripWrap does not unwrap a TBlock, and
                    // ExpressionBlockNorm fails a block whose tail is a
                    // TIf. The zero arm must be a literal zero constant in
                    // the AST, the subject a nullable numeric payload, and
                    // the other arm's text must equal the subject text.
                    // (NoneZeroFold, ShapeParse)
                    // A local subject's Haxe type can lie: an optional
                    // parameter declared Null<T> may hold a bare Rust value
                    // once the boundary consumed its Option. A local read
                    // folds only on positive declaration-shape evidence; a
                    // call or field read falls back to the Haxe type.
                    final subjectNullable = cmp != null && (switch (stripWrap(cmp.subject).expr) {
                        case TLocal(v):
                            declInitShape(v) == RustShape.ShapeOption
                                && isNumericScalarType(getNullInnerType(v.t));
                        case _:
                            isNullType(cmp.subject.t)
                                && isNumericScalarType(getNullInnerType(cmp.subject.t));
                    });
                    final inverted = cmp != null && cmp.inverted;
                    final zeroArm = stripWrap(inverted ? f : t);
                    final innerType = cmp != null ? getNullInnerType(cmp.subject.t) : null;
                    final zeroText:Null<String> = switch (zeroArm.expr) {
                        case TConst(TInt(v)) if (v == 0):
                            innerType != null && isFloatType(innerType)
                                ? (FloatPrecision.isF32() ? "0.0f32" : "0.0f64") : "0";
                        case TConst(TFloat(v)) if (v == "0" || v == "0.0"):
                            FloatPrecision.isF32() ? "0.0f32" : "0.0f64";
                        case _:
                            null;
                    };
                    if (subjectNullable && zeroText != null) {
                        final subjectText = stripRenderedParens(expr(cmp.subject));
                        final subjectArmText = stripRenderedParens(expr(stripWrap(inverted ? t : f)));
                        if (subjectArmText == subjectText)
                            return "(" + subjectText + ").unwrap_or(" + zeroText + ")";
#if boring_fold_debug
                        Context.warning("FOLDDBG nofold subj=[" + subjectArmText + "] vs [" + subjectText + "] inv=" + inverted, e.pos);
#end
                    }
                }
                final coalescing = coalescingSiteFor(e);
                if (coalescing != null)
                    return expr(coalescing.valueExpr);
                final guarded = guardedMatchExpression(c, t, f, e.t);
                if (guarded != null)
                    return guarded;
                final hasGet = hasGuardedGetTernary(c, t, f, e.t);
                if (hasGet != null)
                    return hasGet;
                final optional = optionalIf(c, t, f, e.t);
                if (optional != null)
                    return optional;
                final condStr = switch (stripWrap(c).expr) {
                    case _: nullableBoolOperand(stripWrap(c), expr(stripWrap(c)));
                };
                final branchTarget = conditionalNumericTarget(t, f, e.t);
                return "if "
                    + condStr
                    + " { "
                    + interfaceConditionalBranch(e.t, t, conditionalNumericBranch(t, f, e.t, branchTarget, wrapBranchForNullableResult(t, e.t, f)))
                    + " } else { "
                    + interfaceConditionalBranch(e.t, f, conditionalNumericBranch(f, t, e.t, branchTarget, wrapBranchForNullableResult(f, e.t, t)))
                    + " }";
            case TSwitch(_, _, _):
                return matchExpression(e);
            case TTry(_, catches) if (catches.length != 1):
                return fail(e, "try region handles exactly one exception domain");
            case TTry(_, _):
                // Region lowering needs the statement context (features/06):
                // statement position and initializer position render in
                // stmtLines, return position in TReturn.
                return fail(e, "try region lowers at statement, initializer, or return position");
            case TBlock(stmts):
                return blockExpression(stmts);
            case _:
                return fail(e, "expression has no Rust lowering in the subset: " + Std.string(e.expr));
        }
    }

    function optionalIf(c:TypedExpr, ifTrue:TypedExpr, ifFalse:TypedExpr, resultType:Type):Null<String> {
        var value:Null<TVar> = null;
        var trueIsNone = false;
        switch (stripWrap(c).expr) {
            case TBinop(OpEq, left, right):
                if (isTNull(right)) {
                    switch (stripWrap(left).expr) {
                        case TLocal(v):
                            value = v;
                            trueIsNone = true;
                        case _:
                    }
                } else if (isTNull(left)) {
                    switch (stripWrap(right).expr) {
                        case TLocal(v):
                            value = v;
                            trueIsNone = true;
                        case _:
                    }
                }
            case TBinop(OpNotEq, left, right):
                if (isTNull(right)) {
                    switch (stripWrap(left).expr) {
                        case TLocal(v):
                            value = v;
                            trueIsNone = false;
                        case _:
                    }
                } else if (isTNull(left)) {
                    switch (stripWrap(right).expr) {
                        case TLocal(v):
                            value = v;
                            trueIsNone = false;
                        case _:
                    }
                }
            case _:
        }
        if (value == null) {
            return null;
        }
        final selected = trueIsNone ? ifFalse : ifTrue;
        if (nullableCollapsedLocals.exists(value.id)) {
            final noneExpr = trueIsNone ? ifTrue : ifFalse;
            final localName = RustImports.toSnakeCase(value.name);
            return "if " + localName + " == 0 { " + expr(noneExpr) + " } else { " + localName + " }";
        }
        switch (stripWrap(selected).expr) {
            case TLocal(v) if (v.id == value.id):
                final noneExpr = trueIsNone ? ifTrue : ifFalse;
                final noneText = expr(noneExpr);
                final typedNoneText = isStringType(resultType) ? noneText + ".to_string()" : noneText;
                final localName = RustImports.toSnakeCase(value.name);
                return "match " + localName + " { None => " + typedNoneText + ", Some(ref " + localName + ") => " + localName + ".clone() }";
            case _:
        }
        return null;
    }

    /** Lowers an abstract implementation block to a Rust newtype value. */
    function valueTypeSynthetic(wrapper:TypedExpr, value:TypedExpr):String {
        final plan = ValueTypePlan.planValueTypeSynthetic(wrapper, value, {
            markedAbstractOfType: ValueTypeSupport.markedAbstractOfType,
            localValues: valueTypeLocalValues,
            activeAbstract: () -> currentClass == null ? null : ValueTypeSupport.markedAbstractOfClass(currentClass),
            activeField: (a, n) -> n == null ? null : ValueTypeSupport.memberField(a, n),
            activeFieldName: () -> currentMethodName,
            stripValue: stripWrap,
            wrapNative: true
        });
        final abs = plan.abstractType;
        if (abs == null)
            return expr(value);
        imports.requireType(abs.module, abs.name);
        final wrapperName = abs.name;
        final locals = plan.locals;
        final nativeOperator = plan.nativeOperator;
        return switch (plan.kind) {
            case ValueTypeBinary(op, left, right):
                final field = plan.field;
                if (field == null) expr(value) else {final asRepresentation = nativeOperator && field.name == currentMethodName;
                    final rendered = valueTypeOperand(left, locals, abs, asRepresentation) + " " + opStr(op) + " "
                        + valueTypeOperand(right, locals, abs, asRepresentation);
                    plan.wrapperRequired ? wrapperName
                        + "("
                        + rendered
                        + ")" : rendered;
                }
            case ValueTypeUnary(op, subject):
                final field = plan.field;
                if (field == null) expr(value) else {final asRepresentation = nativeOperator && field.name == currentMethodName;
                    final rendered = "-" + valueTypeOperand(subject, locals, abs, asRepresentation);
                    plan.wrapperRequired ? wrapperName
                        + "("
                        + rendered
                        + ")" : rendered;
                }
            case _:
                // A value-type constructor whose representation is Float can
                // receive an Int after Haxe's numeric unification. The Rust
                // tuple struct stores the module real, so convert this
                // representation boundary explicitly.
                final narrowedOperand = valueTypeNarrowedInlineValue(value, locals);
                final operand = narrowedOperand != null ? narrowedOperand : valueTypeOperand(value, locals, abs);
                final valueText = ValueTypeSupport.isFloatRepresentation(abs) && isIntType(emittedType(value))
                    ? intToFloatText(operand)
                    : operand;
                wrapperName + "(" + valueText + ")";
        };
    }

    /**
        The call-site value of an inline value-type constructor parameter that
        an enclosing null guard narrowed. The typer drops the inline local and
        keeps the narrowed parameter type, so the wrapper would otherwise read
        the missing local name. Resolving the initializer to the guard's match
        binding keeps the value in scope at the call site.
    **/
    function valueTypeNarrowedInlineValue(value:TypedExpr, locals:Map<Int, TypedExpr>):Null<String> {
        final resolved = switch (stripWrap(value).expr) {
            case TLocal(v) if (locals.exists(v.id)): locals.get(v.id);
            case _: null;
        };
        if (resolved == null || isNullType(value.t) || !isNullType(resolved.t))
            return null;
        final binding = narrowedText(subjectTextOf(resolved));
        if (binding == null)
            return null;
        optionNarrowingHitCount++;
        final inner = getNullInnerType(resolved.t);
        return isTypeCopy(inner) ? "*" + binding : "(*" + binding + ").clone()";
    }

    function valueTypeLocalValues(wrapper:TypedExpr):Map<Int, TypedExpr> {
        return PolicyQueries.valueTypeLocalValues(wrapper);
    }

    function valueTypeOperand(value:TypedExpr, locals:Map<Int, TypedExpr>, ?abs:AbstractType, asRepresentation:Bool = false):String {
        var source = value;
        var wrapperOperand = false;
        var decorated = true;
        while (decorated) {
            if (abs != null) {
                final sourceAbs = ValueTypeSupport.markedAbstractOfType(source.t);
                if (sourceAbs != null && ValueTypeSupport.sameAbstract(sourceAbs, abs))
                    wrapperOperand = true;
            }
            switch (source.expr) {
                case TCast(inner, _):
                    source = inner;
                case TMeta(_, inner):
                    source = inner;
                case _:
                    decorated = false;
            }
        }
        switch (stripWrap(value).expr) {
            case TLocal(v) if (locals.exists(v.id)):
                return expr(locals.get(v.id));
            case _:
        }
        final rendered = expr(value);
        final alreadyRepresentation = switch (stripWrap(value).expr) {
            case TLocal(v) if (subst.exists(v.id) && StringTools.endsWith(subst.get(v.id), ".0")): true;
            case _: false;
        };
        return asRepresentation && wrapperOperand && !alreadyRepresentation ? rendered + ".0" : rendered;
    }

    function enumQuery(e:TypedExpr):Null<String> {
        return switch (PolicyQueries.enumQueryPlan(e)) {
            case null: null;
            case LengthCount(count): Std.string(count);
            case AliasIndex(subj, index): expr(subj) + "[" + expr(index) + "]";
            case EntryIndex(en, index):
                requireEnum(en.module, en.name);
                en.name + "::ALL[" + expr(index) + "]";
            case EnumKindQuery(kind, en, args):
                requireEnum(en.module, en.name);
                switch (kind) {
                    case QCollection: en.name + "::ALL";
                    case QName: expr(args[0]) + ".name().to_string()";
                    case QLookup: en.name + "::from_name(&(" + expr(args[1]) + "))";
                }
        }
    }

    // ------------------------------------------------------------------
    // Variant switches and try regions (features/01, features/06)
    // ------------------------------------------------------------------

    function isTryRegion(e:TypedExpr):Bool {
        return PolicyQueries.isTryRegion(e);
    }

    /** True when the expression is an enum switch over variant indices. */
    function isVariantSwitch(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TSwitch(_, _, _): true;
            case _: false;
        };
    }

    /** Return-position variant switch: the match value returns through the function edge. */
    function matchReturnLines(sw:TypedExpr, depth:Int):Array<String> {
        final lines = matchExpression(sw).split("\n");
        final out = [indent(depth) + (isFallible ? "return Ok(" : "return ") + lines[0]];
        for (i in 1...lines.length) {
            out.push(indent(depth) + lines[i]);
        }
        out[out.length - 1] += isFallible ? ");" : ";";
        return out;
    }

    /**
        On a catch variable, the payload field of the exception class (the
        enum-typed field whose enum the region catches) reads as the bound
        enum value itself; the exception class is unavailable for this target
        (features/06 catch-site lowering).
    **/
    function catchPayloadAccess(subj:TypedExpr, name:String):Null<String> {
        switch (stripWrap(subj).expr) {
            case TLocal(v) if (catchVars.exists(v.id)):
                switch (Context.follow(v.t)) {
                    case TInst(c, _):
                        final cls = c.get();
                        final enumModule = state.exceptionPayloads.get(cls.module);
                        if (enumModule != null) {
                            for (f in cls.fields.get()) {
                                if (f.name == name) {
                                    switch (f.type) {
                                        case TEnum(en, _):
                                            if (en.get().module == enumModule) {
                                                return RustImports.toSnakeCase(localName(v));
                                            }
                                        case _:
                                    }
                                }
                            }
                        }
                    case _:
                }
            case _:
        }
        return null;
    }

    /**
        A `message` or `get_message` read on a folded exception. The sealed
        fold keeps the Display impl as the message carrier, so any read maps
        to `format!("{}", value)` whether or not the value sits in a
        catch-variable position (features/06 message lowering). Without this,
        a read outside a catch emits the runtime-dependent `get_message()`
        accessor, which the folded enum lacks.
    **/
    function foldedExceptionMessage(subj:TypedExpr, name:String):Null<String> {
        if (name != "message" && name != "get_message") {
            return null;
        }
        switch (Context.follow(subj.t)) {
            case TInst(c, _):
                if (!RustDecl.isExceptionSubclass(c.get())) {
                    return null;
                }
                return "format!(\"{}\", " + expr(subj) + ")";
            case TEnum(en, _):
                final owner = state.payloadEnumOwners.get(en.get().module);
                if (owner == null) {
                    return null;
                }
                return "format!(\"{}\", " + expr(subj) + ")";
            case _:
                return null;
        }
    }

    /** The payload enum of the exception class a region catches, or null. */
    function caughtPayloadEnum(c:{v:TVar, expr:TypedExpr}):Null<{name:String, module:String}> {
        switch (Context.follow(c.v.t)) {
            case TInst(cls, _):
                final messageOnly = state.messageOnlyExceptions.get(cls.get().module);
                if (messageOnly != null)
                    return {name: messageOnly, module: cls.get().module};
                final enumModule = state.exceptionPayloads.get(cls.get().module);
                if (enumModule == null) {
                    return null;
                }
                final name = state.payloadEnumNames.exists(enumModule) ? state.payloadEnumNames.get(enumModule) : enumModule.substr(enumModule.lastIndexOf(".") + 1);
                return {name: name, module: enumModule};
            case _:
                return null;
        }
    }

    function requireEnum(enumModule:String, enumName:String):Void {
        final emittedIn = state.payloadEnumModules.exists(enumModule) ? state.payloadEnumModules.get(enumModule) : enumModule;
        imports.requireType(emittedIn, enumName);
    }

    function freshRegionName(prefix:String):String {
        var index = 0;
        var name = prefix;
        while (usedNames.exists(name)) {
            index += 1;
            name = prefix + index;
        }
        usedNames.set(name, true);
        return name;
    }

    /**
        Renders the region body as an immediately invoked closure returning
        `Result<value, enum>`. The trailing value expression is rewrapped as a
        return so the existing fallible return edge rules (String ownership,
        Option wrapping) apply at the `Ok` tail; the fallibility flag is set
        for the closure body only, so `Ok` wrapping holds even when the
        enclosing function absorbed the domain.
    **/
    function regionClosureLines(body:TypedExpr, regionType:Null<Type>, enumName:String, depth:Int):Array<String> {
        var stmts = statementsOf(body);
        // A top-level throw ends the region: the tail after it is dead in
        // every target, so the closure stops at the throwing edge.
        for (i in 0...stmts.length) {
            switch (stmts[i].expr) {
                case TThrow(_):
                    stmts = stmts.slice(0, i + 1);
                    break;
                case _:
            }
        }
        final tail = regionTailValue(stmts);
        var bodyStmts = stmts;
        if (tail != null) {
            final rewrapped:TypedExpr = {expr: TypedExprDef.TReturn(tail), t: tail.t, pos: tail.pos};
            bodyStmts = stmts.slice(0, stmts.length - 1).concat([rewrapped]);
        }
        final savedFallible = isFallible;
        final savedError = errorTypeName;
        final savedOverflow = countOverflowVariant;
        final savedTryClosure = inTryClosure;
        isFallible = true;
        inTryClosure = true;
        errorTypeName = enumName;
        countOverflowVariant = null;
        final lines = blockLines(bodyStmts, depth, true);
        isFallible = savedFallible;
        errorTypeName = savedError;
        countOverflowVariant = savedOverflow;
        inTryClosure = savedTryClosure;
        // the forced fallible flag, and a rewrapped tail already returns it.
        return lines;
    }

    /**
        The trailing value of a region body: an expression statement whose
        value leaves the region. Declarations, control flow, assignments,
        and blocks never carry the tail value.
    **/
    function regionTailValue(stmts:Array<TypedExpr>):Null<TypedExpr> {
        if (stmts.length == 0) {
            return null;
        }
        final last = stmts[stmts.length - 1];
        return switch (last.expr) {
            case TReturn(_) | TThrow(_) | TVar(_, _) | TIf(_, _, _) | TWhile(_, _, _) | TFor(_, _, _) | TBlock(_) | TBreak | TContinue |
                TBinop(OpAssign, _, _) | TBinop(OpAssignOp(_), _, _):
                null;
            case _:
                isVoidType(last.t) ? null : last;
        }
    }

    function isVoidType(t:Null<Type>):Bool {
        if (t == null) {
            return true;
        }
        return switch (Context.follow(t)) {
            case TAbstract(a, _): a.get().name == "Void";
            case TEnum(en, _): en.get().name == "Void";
            case _: false;
        };
    }

    /** Return-position region: the match value returns through the function edge. */
    function regionReturnLines(region:TypedExpr, depth:Int):Array<String> {
        final parts = switch (stripWrap(region).expr) {
            case TTry(body, catches): {body: body, c: catches[0]};
            case _: return [fail(region, "not a try region")];
        }
        final payload = caughtPayloadEnum(parts.c);
        if (payload == null) {
            return [fail(parts.c.expr, "try region catch type carries no payload enum")];
        }
        if (regionTailValue(statementsOf(parts.body)) == null) {
            return [fail(region, "try region body has no value")];
        }
        requireEnum(payload.module, payload.name);
        final valueBinding = freshRegionName("__value");
        // The annotated return type keeps the error enum readable at the
        // closure head; handler arms alone cannot always infer it.
        final valueType = types.of(regionTailValue(statementsOf(parts.body)).t);
        final opener = "(|| -> Result<" + valueType + ", " + payload.name + "> {";
        final prefix = isFallible ? "return Ok(match " + opener : "return match " + opener;
        final out = [indent(depth) + prefix];
        for (l in regionClosureLines(parts.body, region.t, payload.name, depth + 1))
            out.push(l);
        out.push(indent(depth) + (isFallible ? "})() {" : "})() {"));
        out.push(indent(depth) + "    Ok(" + valueBinding + ") => " + valueBinding + ",");
        catchVars.set(parts.c.v.id, true);
        final arm = armBlock(parts.c.expr);
        catchVars.remove(parts.c.v.id);
        for (i in 0...arm.length) {
            final suffix = i == arm.length - 1 ? "," : "";
            out.push(indent(depth) + "    Err(" + RustImports.toSnakeCase(localName(parts.c.v)) + ") => " + arm[i] + suffix);
        }
        out.push(indent(depth) + (isFallible ? "});" : "};"));
        return out;
    }

    /** Statement-position region: run the closure, act on the Err arm only. */
    function regionStatementLines(body:TypedExpr, c:{v:TVar, expr:TypedExpr}, depth:Int):Array<String> {
        final payload = caughtPayloadEnum(c);
        if (payload == null) {
            return [fail(c.expr, "try region catch type carries no payload enum")];
        }
        requireEnum(payload.module, payload.name);
        final outcome = freshRegionName("__outcome");
        final tail = regionTailValue(statementsOf(body));
        final valueType = tail != null ? tail.t : null;
        final out = [indent(depth)
            + 'let $outcome: Result<'
            + (valueType == null ? "()" : types.of(valueType))
            + ', '
            + payload.name
            + "> = (|| {"];
        for (l in regionClosureLines(body, valueType, payload.name, depth + 1))
            out.push(l);
        out.push(indent(depth) + "})();");
        out.push(indent(depth) + 'match $outcome {');
        out.push(indent(depth) + "    Ok(_) => {}");
        // A handler that never reads the caught value binds the wildcard.
        final catchBinding = mentionsLocal(c.expr, c.v) ? RustImports.toSnakeCase(localName(c.v)) : "_";
        out.push(indent(depth) + "    Err(" + catchBinding + ") => {");
        catchVars.set(c.v.id, true);
        final handler = blockLines(statementsOf(c.expr), depth + 2);
        catchVars.remove(c.v.id);
        for (l in handler)
            out.push(l);
        out.push(indent(depth) + "    }");
        out.push(indent(depth) + "}");
        return out;
    }

    /** Initializer-position region: the match yields the bound value. */
    function regionInitializerLines(v:TVar, region:TypedExpr, depth:Int):Array<String> {
        final parts = switch (stripWrap(region).expr) {
            case TTry(body, catches): {body: body, c: catches[0]};
            case _: return [fail(region, "not a try region")];
        }
        final payload = caughtPayloadEnum(parts.c);
        if (payload == null) {
            return [fail(parts.c.expr, "try region catch type carries no payload enum")];
        }
        if (regionTailValue(statementsOf(parts.body)) == null) {
            return [fail(region, "try region body has no value")];
        }
        requireEnum(payload.module, payload.name);
        final name = RustImports.toSnakeCase(localName(v));
        final valueBinding = freshRegionName("__value");
        final out = [
            indent(depth) + 'let $name: ' + types.of(v.t) + ' = match (|| -> Result<' + types.of(v.t) + ', ' + payload.name + '> {'
        ];
        for (l in regionClosureLines(parts.body, v.t, payload.name, depth + 1))
            out.push(l);
        out.push(indent(depth) + "})() {");
        out.push(indent(depth) + "    Ok(" + valueBinding + ") => " + valueBinding + ",");
        catchVars.set(parts.c.v.id, true);
        final arm = armBlock(parts.c.expr);
        catchVars.remove(parts.c.v.id);
        for (i in 0...arm.length) {
            final suffix = i == arm.length - 1 ? "," : "";
            out.push(indent(depth) + "    Err(" + RustImports.toSnakeCase(localName(parts.c.v)) + ") => " + arm[i] + suffix);
        }
        out.push(indent(depth) + "};");
        return out;
    }

    function numericBranchType(e:TypedExpr):String {
        final t = isNullType(e.t) ? getNullInnerType(e.t) : e.t;
        if (isFloatType(t))
            return FloatPrecision.isF32() ? "f32" : "f64";
        if (isNegativeIntLiteral(e))
            return "i32";
        return resolveExprType(e);
    }

    function numericTargetForBranches(first:TypedExpr, second:TypedExpr, resultType:Null<Type>):Null<String> {
        final firstInner = isNullType(first.t) ? getNullInnerType(first.t) : first.t;
        final secondInner = isNullType(second.t) ? getNullInnerType(second.t) : second.t;
        if (!isIntType(firstInner) && !isFloatType(firstInner)
            && !isIntType(secondInner) && !isFloatType(secondInner))
            return null;
        if (isFloatType(firstInner) || isFloatType(secondInner))
            return FloatPrecision.isF32() ? "f32" : "f64";
        // Both arms are business Int. An arm that renders in the signed i32
        // domain (a negation, an index result) beside an unsigned arm must
        // agree on the conditional's Rust type, so the conditional targets
        // the business u32 slot and the signed arm reinterprets at the
        // branch. Two signed arms already share the i32 type and keep it.
        if (!RuntimeResidents.isResident(imports.selfModule)
            && (rendersSignedIntExpr(first) || rendersSignedIntExpr(second))
            && !(rendersSignedIntExpr(first) && rendersSignedIntExpr(second)))
            return "u32";
        return null;
    }

    function conditionalNumericTarget(first:TypedExpr, second:TypedExpr, resultType:Null<Type>):Null<String> {
        return numericTargetForBranches(first, second, resultType);
    }

    function containsNegativeInt(e:TypedExpr):Bool {
        var found = false;
        function scan(x:TypedExpr) {
            if (isNegativeIntLiteral(x))
                found = true;
            if (!found)
                TypedExprTools.iter(x, scan);
        }
        scan(e);
        return found;
    }

    function matchNumericTarget(cases:Array<Dynamic>, resultType:Null<Type>):Null<String> {
        if (cases.length == 0)
            return null;
        var target:Null<String> = null;
        var sawFloat = false;
        var sawNegative = false;
        for (c in cases) {
            final t:Type = c.expr.t;
            final inner = isNullType(t) ? getNullInnerType(t) : t;
            if (isFloatType(inner))
                sawFloat = true;
            if (containsNegativeInt(c.expr))
                sawNegative = true;
            if (target == null && (isIntType(inner) || isFloatType(inner)))
                target = numericBranchType(c.expr);
        }
        if (sawFloat)
            return FloatPrecision.isF32() ? "f32" : "f64";
        return null;
    }

    function normalizeNumericBranch(branch:TypedExpr, target:String, text:String):String {
        final nullable = isNullType(branch.t);
        final inner = nullable ? getNullInnerType(branch.t) : branch.t;
        if (StringTools.startsWith(text, "Some(") && StringTools.endsWith(text, ")")) {
            final payload = text.substr(5, text.length - 6);
            if (isIntType(inner) && (target == "f32" || target == "f64"))
                return "Some(" + intToFloatText(payload) + ")";
            return text;
        }
        if (isIntType(inner) && (target == "f32" || target == "f64"))
            return intToFloatText(text);
        // A signed i32 arm entering the business u32 conditional slot
        // reinterprets its bits so both Rust arms carry one type.
        if (target == "u32" && isIntType(inner) && !nullable
            && (i32LocalDomain(branch) || rendersSignedIntExpr(branch)))
            return RustConversions.reinterpret(text, "u32");
        return text;
    }

    function conditionalNumericBranch(branch:TypedExpr, sibling:TypedExpr, resultType:Null<Type>, target:Null<String>, text:String):String {
        final normalized = target == null ? text : normalizeNumericBranch(branch, target, text);
        final borrowed = cloneBorrowedReceiverBranch(branch, resultType, normalized);
        // A bare local arm of owned non-Copy type moves the local; a later
        // mention in statement order still reads it, so the arm clones.
        // (BranchArmMoveClone)
        return switch (stripWrap(branch).expr) {
            case TLocal(l) if (branchArmMoveReadsAfter.exists(l.id)):
                StringTools.endsWith(borrowed, ".clone()") ? borrowed : "(" + borrowed + ").clone()";
            case _: borrowed;
        };
    }

    /**
        A method receiver is emitted as `&self`; the value it names stays owned
        by the caller. An owned result slot therefore clones the referent when
        a conditional arm reads the receiver. Nullable result slots keep their
        Option wrapper, so a branch already wrapped in Some stays unchanged.
    **/
    function cloneBorrowedReceiverBranch(branch:TypedExpr, resultType:Null<Type>, text:String):String {
        if (resultType == null || isTypeCopy(resultType) || StringTools.startsWith(text, "Some("))
            return text;
        return switch (stripWrap(branch).expr) {
            case TConst(TThis):
                StringTools.endsWith(text, ".clone()") ? text : "(" + text + ").clone()";
            case _: text;
        };
    }

    /**
        interfaceConditionalBranch: a conditional arm entering an interface
        result slot boxes its concrete value; an arm already typed as the
        interface keeps its box. A null arm keeps the null literal.
    **/
    function interfaceConditionalBranch(expected:Null<Type>, branch:TypedExpr, text:String):String {
        if (expected == null || isNullType(expected) || !isInterfaceType(expected) || isTNull(branch) || text == "None")
            return text;
        return renderValueForType(expected, branch, text);
    }

    /**
        Renders an enum switch as a `match` expression. The typer hands the
        switch over with the subject wrapped in TEnumIndex and case values as
        construct-index constants; payload captures arrive as TEnumParameter
        initializations in the arm block, so each arm pattern binds the
        captured payloads as named fields and represents the remaining fields with `..`.
    **/
    function matchExpression(sw:TypedExpr):String {
        final parts = switch (sw.expr) {
            case TSwitch(subj, cases, def): {subj: subj, cases: cases, def: def};
            case _: return fail(sw, "not a switch");
        }
        if (parts.def != null) {
            return fail(sw, "variant switch carries a default arm (V15)");
        }
        final subj = stripWrap(parts.subj);
        final se = switch (subj.expr) {
            case TEnumIndex(inner): inner;
            case _: return fail(sw, "switch subject is not a variant index");
        }
        final subjStr = expr(se);
        final en = switch (se.t) {
            case TEnum(enumRef, _): enumRef.get();
            case _: return fail(sw, "variant switch subject is not a variant value");
        }
        requireEnum(en.module, en.name);
        final table = new Map<Int, EnumField>();
        for (constructName => ef in en.constructs) {
            table.set(ef.index, ef);
        }
        final out = ["match " + subjStr + " {"];
        for (c in parts.cases) {
            // A Haxe case may group several constructors with `|` (for
            // example `case CjkText | CjkPunctuation:`). Every value is a
            // constant enum index; each becomes its own Rust pattern arm,
            // joined by `|` so the grouped case stays exhaustive (E0004).
            // The payload shape is identical across a grouped case, so the
            // first value's construct drives the capture bindings.
            final indices = [for (v in c.values) switch (v.expr) {
                case TConst(TInt(i)): i;
                case _: return fail(sw, "variant switch case is not a constant index");
            }];
            final ef = table.get(indices[0]);
            if (ef == null) {
                return fail(sw, "variant switch case index has no construct");
            }
            final argCount = switch (ef.type) {
                case TFun(args, _): args.length;
                case _: 0;
            };
            // Payload captures bind as named fields of the variant pattern;
            // uncaptured payloads use `..`; unused ones use a
            // leading underscore binding.
            final subjectLocal = switch (se.expr) {
                case TLocal(l): l.id;
                case _: -1;
            };
            final captures:Array<{vid:Int, idx:Int}> = [];
            function collect(stmts:Array<TypedExpr>) {
                for (s in stmts) {
                    switch (s.expr) {
                        case TVar(v, init) if (init != null):
                            switch (stripWrap(init).expr) {
                                case TEnumParameter(se2, _, idx):
                                    switch (se2.expr) {
                                        case TLocal(l2) if (l2.id == subjectLocal):
                                            if (Lambda.find(captures, function(c) return c.idx == idx) == null) {
                                                captures.push({vid: v.id, idx: idx});
                                            }
                                        case _:
                                    }
                                // The typer binds the pattern variable from
                                // the extraction temp; usage tracking follows
                                // the pattern variable, so a payload the arm
                                // value never reads stays out of the pattern.
                                case TLocal(src):
                                    for (cap in captures) {
                                        if (cap.vid == src.id) {
                                            cap.vid = v.id;
                                        }
                                    }
                                case _:
                            }
                        case TBlock(bs):
                            collect(bs);
                        case _:
                    }
                }
            }
            collect(statementsOf(c.expr));
            function localIsRead(vid:Int):Bool {
                // TypedExprTools.iter visits direct children only, so the
                // read scan must recurse through the callback (mentionsLocal
                // pattern); payload reads sit under TVar initializers.
                var found = false;
                function scan(x:TypedExpr) {
                    switch (x.expr) {
                        case TLocal(l) if (l.id == vid):
                            found = true;
                        case _:
                    }
                    TypedExprTools.iter(x, scan);
                }
                scan(c.expr);
                return found;
            }
            final usedIndices = [for (cap in captures) if (localIsRead(cap.vid)) cap.idx];
            var lastUsed = -1;
            for (idx in usedIndices) {
                if (idx > lastUsed) {
                    lastUsed = idx;
                }
            }
            var pattern = [for (idx in indices) en.name + "::" + RustImports.toUpperCamelCase(table.get(idx).name)].join(" | ");
            if (argCount > 0) {
                final bindings:Array<String> = [];
                for (idx in 0...argCount) {
                    if (Lambda.has(usedIndices, idx) || idx < lastUsed) {
                        // A used payload binds under a reserved name so an
                        // arm body cannot shadow an outer local with the
                        // pattern binding; an unused payload before a used
                        // one binds the same way, and the leading underscore
                        // keeps the binding warning-free.
                        bindings.push(payloadName(ef, idx) + ": _p" + idx);
                    } else {
                        // Everything from the first unused tail payload on
                        // represents the remaining fields with the rest pattern.
                        bindings.push("..");
                        break;
                    }
                }
                pattern = [for (idx in indices) en.name + "::" + RustImports.toUpperCamelCase(table.get(idx).name) + " { " + bindings.join(", ") + " }"].join(" | ");
            }
            final armTarget = matchNumericTarget(parts.cases, sw.t);
            final arm = armBlock(c.expr, armTarget, sw.t);
            for (i in 0...arm.length) {
                var armText = arm[i];
                // Under the statement-discard flag a null-literal arm (a
                // whole-arm render of the single line "None") becomes an
                // empty block, unifying with the side-effect block arms.
                if (discardingStatementSwitch && arm.length == 1 && armText == "None") {
                    armText = "{}";
                }
                // A match whose result type is nullable (Null<T>) must wrap
                // a non-null arm value in Some; the payload read arms return
                // the bare inner value while the null arms already render
                // None. Only adapt when the arm value is not already an
                // Option/None literal.
                if (isNullType(sw.t) && !isNullType(c.expr.t)
                    && armText != "None" && !StringTools.startsWith(armText, "Some(")) {
                    armText = "Some(" + armText + ")";
                }
                final suffix = i == arm.length - 1 ? "," : "";
                out.push("    " + pattern + " => " + armText + suffix);
            }
        }
        out.push("}");
        return out.join("\n");
    }

    /**
        Renders one switch arm (or one region handler in value position).
        Payload captures fold into field reads on the subject; other
        declarations stay; the trailing statement is the arm value. A
        single-expression arm renders inline, anything longer renders as a
        block.
    **/
    function armBlock(e:TypedExpr, numericTarget:Null<String> = null, resultType:Null<Type> = null):Array<String> {
        final decls:Array<String> = [];
        final sideStmts:Array<String> = [];
        var value:Null<String> = null;
        var sawReturn = false;
        function walk(stmts:Array<TypedExpr>) {
            for (s in stmts) {
                switch (s.expr) {
                    case TVar(v, init):
                        if (init == null) {
                            Context.error("rust target: declaration without initializer has no lowering", s.pos);
                        }
                        switch (stripWrap(init).expr) {
                            case TEnumParameter(_, ef, index):
                                // The variant pattern binds every payload
                                // under its reserved name, so the capture
                                // reads it bare.
                                subst.set(v.id, "_p" + index);
                            case TLocal(source) if (subst.exists(source.id)):
                                subst.set(v.id, subst.get(source.id));
                            case _:
                                decls.push("let " + RustImports.toSnakeCase(localName(v)) + " = " + expr(init) + ";");
                        }
                    case TBlock(bs):
                        walk(bs);
                    case TMeta(_, inner):
                        walk([inner]);
                    case TReturn(_):
                        sawReturn = true;
                    case _:
                        // Every side-effect statement renders: an earlier
                        // assignment demotes to a plain statement so a
                        // multi-write arm keeps all its writes.
                        // (MultiStatementArm)
                        if (value != null) {
                            // A non-final statement in a block needs its
                            // terminator. (MultiStatementArm)
                            sideStmts.push(StringTools.endsWith(value, ";") ? value : value + ";");
                        }
                        value = expr(s);
                        if (isStringType(e.t) && isStringLiteral(s))
                            value = value + ".to_string()";
                }
            }
        }
        walk(statementsOf(e));
        if (sawReturn) {
            return [fail(e, "return inside a value arm lowers at statement position only")];
        }
        var valueText = value;
        if (value != null && isStringType(e.t) && isStringLiteral(e)) {
            valueText = value + ".to_string()";
        }
        if (valueText != null && numericTarget != null)
            valueText = normalizeNumericBranch(e, numericTarget, valueText);
        if (valueText != null && resultType != null && isNullType(resultType)) {
            // A nullable match result wraps a non-null arm value in
            // Some(...) so every arm produces the same Option shape (the
            // same rule wrapBranchForNullableResult applies to if-else
            // branches).
            if (!isTNull(e) && !isNullType(e.t) && !StaticFieldHelper.isNullableType(e.t))
                valueText = "Some(" + valueText + ")";
        }
        if (sideStmts.length == 0 && decls.length == 0) {
            return [valueText];
        }
        final out = ["{"];
        for (d in decls) {
            out.push("    " + d);
        }
        for (st in sideStmts) {
            out.push("    " + st);
        }
        out.push("    " + valueText);
        out.push("}");
        return [out.join("\n")];
    }

    function isStringType(t:Type):Bool {
        if (t == null)
            return false;
        return switch (Context.follow(t)) {
            case TInst(c, _): c.get().name == "String";
            case _: false;
        };
    }

    /**
        stringLikeType: a plain String or an abstract whose underlying type is
        String. Both lower to an owned String in value position and a &str
        view in parameter position, so call boundaries adapt them the same
        way.
    **/
    function stringLikeType(t:Null<Type>):Bool {
        if (t == null)
            return false;
        if (isStringType(t))
            return true;
        return switch (Context.follow(t)) {
            case TAbstract(a, _) if (!ValueTypeSupport.isMarkedAbstract(a.get())):
                switch (Context.follow(a.get().type)) {
                    case TInst(c, _): c.get().name == "String";
                    case _: false;
                };
            case _: false;
        };
    }

    /**
        A loop over an Array binds a scalar item through the pattern
        (`for &x in ..`), so the binding is a value; every other item is bound
        as a Rust reference. This reads the same split the loop pattern uses.
    **/
    function isBorrowedLoopReference(v:TVar):Bool {
        if (!borrowedLoopVarIds.exists(v.id))
            return false;
        return switch (Context.follow(v.t)) {
            case TAbstract(a, _): final n = a.get().name; n != "Int" && n != "Bool" && n != "Float";
            default: true;
        };
    }

    /**
        borrowedComparableLoopItem: a loop over an Array parameter binds its
        item as a Rust reference, and an enum or String element (unlike a
        scalar, which the pattern destructures) is not unwrapped by the
        pattern. Comparing that reference with an owned value needs the
        referent, so the equality lowering dereferences the Copy/String loop
        binding. Non-Copy record items keep their field-wise equality path.
    **/
    function borrowedComparableLoopItem(e:TypedExpr):Null<TVar> {
        return switch (stripWrap(e).expr) {
            case TLocal(v): isBorrowedLoopReference(v) && (isTypeCopy(v.t) || isStringType(v.t)) ? v : null;
            default: null;
        };
    }

    function isSortedBuilder(subj:TypedExpr):Bool {
        final t = methodSubjectType(subj);
        return switch (Context.follow(t)) {
            case TInst(c, _): final n = c.get().name; n == "SortedMapBuilder" || n == "SortedSetBuilder" || n == "SortedTableBuilder" || n == "SortedMapTableBuilder" || n == "SortedSetTableBuilder";
            case _: false;
        };
    }

    function isSortedTable(subj:TypedExpr):Bool {
        final t = methodSubjectType(subj);
        return switch (Context.follow(t)) {
            case TInst(c, _): final n = c.get().name; n == "SortedMap" || n == "SortedSet" || n == "SortedTable" || n == "SortedMapTable" || n == "SortedSetTable";
            case _: false;
        };
    }

    /** The std generic tables are handwritten runtime residents whose
        key/value parameters borrow as &K and &V (runtime/sorted_table.rs),
        so a String slot there is &String; the &str convention of business
        signatures does not apply. The generated samples name them either through the
        std.SortedMap aliases or directly as the runtime.SortedTable
        residents (SortedMapTable and friends). (AppliedReceiverParams) */
    function isStdTableType(t:Null<Type>):Bool {
        if (t == null)
            return false;
        return switch (Context.follow(t)) {
            case TInst(c, _):
                final cls = c.get();
                (StringTools.startsWith(cls.module, "std.") || StringTools.startsWith(cls.module, "runtime."))
                    && (StringTools.startsWith(cls.name, "SortedMap") || StringTools.startsWith(cls.name, "SortedSet"));
            case _: false;
        };
    }

    // The type a method-call receiver dispatches on: a nullable subject
    // (Option<T>) calls methods on its inner value, so the collection and
    // string classifiers look through the Null wrapper.
    function methodSubjectType(subj:TypedExpr):Type {
        return isNullType(subj.t) ? getNullInnerType(subj.t) : subj.t;
    }

    // A Haxe Array receiver lowers to a Rust Vec; the classifier also looks
    // through a Null wrapper so a nullable Vec field dispatches correctly.
    function isVecType(subj:TypedExpr):Bool {
        final t = methodSubjectType(subj);
        return isArrayType(t);
    }

    /** Whether the type lowers to a Haxe Array. */
    function isArrayType(t:Type):Bool {
        return switch (Context.follow(t)) {
            case TInst(c, _): c.get().name == "Array";
            case _: false;
        };
    }

    /** Whether a class is the Haxe Array type. */
    function isArrayClass(c:ClassType):Bool {
        return c.name == "Array";
    }

    /** The element type of an Array<T> type, when known. */
    function arrayElementType(t:Null<Type>):Null<Type> {
        if (t == null)
            return null;
        return switch (Context.follow(t)) {
            case TInst(c, params) if (c.get().name == "Array" && params.length > 0): params[0];
            case TAbstract(a, params) if (a.get().name == "ReadOnlyArray" && params.length > 0): params[0];
            case TType(d, params) if (d.get().name == "ReadOnlyArray" && params.length > 0): params[0];
            case _: null;
        };
    }

    // A nullable receiver calls its method on the inner value. Mutable
    // collection mutations (push, put, shift, ...) borrow the inner storage
    // mutably; reads borrow it immutably. Some Haxe Null<T> types are emitted
    // as a plain Rust struct without an Option<T> wrapper, so only unwrap an
    // actual Rust fallible wrapper.
    // Whether the Rust rendering of a Haxe Null<T> is a fallible wrapper
    // (Option or Result). Null<Struct> renders as the plain struct, so the
    // as_ref/unwrap forcing read only applies to wrapper-backed types.
    // Covers the plain-struct nullable receiver family.
    function rendersRustFallibleWrapper(t:Type):Bool {
        // Anonymous structure types cannot be translated by the Rust type
        // renderer, and they never render as an Option/Result wrapper, so
        // exclude them before the translation call. The receiver guard
        // reaches this helper for every indexed subject, including inline
        // anonymous structures that carry no Null<T> wrapper.
        if (t == null || isAnonymousStructType(t))
            return false;
        switch (Context.follow(t)) {
            case TAnonymous(_): return false;
            case _:
        }
        final rustType = types.of(t, false);
        return StringTools.startsWith(rustType, "Option<") || StringTools.startsWith(rustType, "Result<");
    }

    /**
        A structural type renders through its named typedef as a plain Rust
        struct, never as a fallible wrapper. The wrapper probe reads the
        emitted type text, so it must not force a name for an anonymous
        structure that a pipeline expansion has not yet typed through its
        typedef.
    **/
    function isAnonymousStructType(t:Type):Bool {
        if (t == null)
            return false;
        return switch (Context.follow(t)) {
            case TAnonymous(_): true;
            case _: false;
        };
    }

    // Whether a receiver still renders as a Rust fallible wrapper at the
    // method and field boundaries: a wrapper-backed Null<T> that the body
    // pre-pass has not narrowed it to a plain local. A collapsed local already
    // holds the inner value, so the as_ref forcing read must not re-apply.
    // Covers the collapsed-parameter receiver family.
    function receiverCarriesFallibleWrapper(subj:TypedExpr):Bool {
        // A null-guarded ternary whose arms are both non-null renders a
        // plain value (guardedMatchExpression materializes the inner
        // struct), never an Option; the as_ref forcing read would ask the
        // plain struct for AsRef (E0599).
        if (isNonNullRenderedConditional(subj))
            return false;
        // Nullable container indexing can arrive through a typed field or an
        // abstracted receiver whose macro type is no longer Null<T>, while
        // its emitted Rust type remains Option<Vec<_>>. Use the emitted type
        // as the boundary contract so every index path extracts the container
        // before applying Vec indexing.
        if (rendersRustFallibleWrapper(subj.t) && !isNullableCollapsedLocal(subj))
            return true;
        // A non-null declared type initialized to null or from a nullable
        // expression keeps Option storage at runtime even though its macro
        // type is not Null<T>; its method receivers must unwrap the wrapper.
        return isImplicitNullableLocal(subj) && !isNullableCollapsedLocal(subj);
    }

    /**
        A field receiver may retain its emitted Option wrapper after macro type
        following has hidden the Null abstract. Force that wrapper before the
        member read; plain struct receivers remain unchanged. This named rule
        covers the Option-backed field receiver family.
    **/
    function fieldReceiverCarriesFallibleWrapper(subj:TypedExpr):Bool {
        // Anonymous structure types cannot be translated by the Rust type
        // renderer, and they never render as an Option wrapper, so exclude
        // them before the translation call. A field receiver can be an
        // inline anonymous structure whose macro type carries no Null<T>.
        // A Null-wrapped anonymous structure (Option<AnonStruct>) still
        // needs the unwrap, so only the non-null form is excluded. An
        // implicit-nullable local (declared non-null but initialized to
        // null or from a nullable call) also keeps Option storage even
        // though its macro type follows to an anonymous structure.
        if (subj.t == null || (!isNullType(subj.t) && isAnonymousStructType(subj.t) && !isImplicitNullableLocal(subj)))
            return false;
        switch (Context.follow(subj.t)) {
            case TAnonymous(_) if (!isNullType(subj.t)): return false;
            case _:
        }
        final rustType = types.of(subj.t, false);
        if (StringTools.startsWith(rustType, "Option<") && !isNullableCollapsedLocal(subj))
            return true;
        // A non-null declared type initialized to null or from a nullable
        // expression keeps Option storage at runtime even though its macro
        // type is not Null<T>; its field reads must unwrap the wrapper.
        return isImplicitNullableLocal(subj) && !isNullableCollapsedLocal(subj);
    }
    function nullableMethodReceiver(subj:TypedExpr, mutable:Bool):String {
        // A has-guarded ternary local holds the bare inner value (its
        // declaration unwrapped the Option); reads must not force-read
        // again. (HasGuardedTernaryLocals)
        final guardedCollapse = switch (stripWrap(subj).expr) {
            case TLocal(v): nullableCollapsedLocals.exists(v.id)
                || hasGuardedTernaryLocals.exists(v.id);
            case _: false;
        };
        if ((!isNullType(subj.t) && !isImplicitNullableLocal(subj)) || guardedCollapse)
            return expr(subj);
        final previousReceiverContext = renderingMethodReceiver;
        if (mutable) renderingMethodReceiver = true;
        final base = expr(subj);
        renderingMethodReceiver = previousReceiverContext;
        // A null guard or a null-coalescing match already bound the inner
        // value; the binding holds the inner reference itself, so the
        // forcing read would ask Rust to find AsRef on the table type.
        // Covers the narrowed sorted-table receiver family.
        final narrowed = narrowedSubject(subj);
        if (narrowed != null) {
            optionNarrowingHitCount++;
            return narrowed;
        }
        if (!receiverCarriesFallibleWrapper(subj))
            return base;
        // A borrowed static/container expression is already the inner table
        // view. Calling as_ref on it asks Rust to find AsRef for
        // &SortedMapTable/&SortedSetTable and produces E0599. Keep the
        // existing wrapper extraction for value-shaped Option receivers
        // (BorrowedSortedTableReceiver).
        if (borrowedSortedTableReceiver(base))
            return base;
        return mutable ? "(" + base + ").as_mut().unwrap()" : "(" + base + ").as_ref().unwrap()";
    }

    /**
        A static sorted table is rendered through a borrowed LazyLock value,
        so its receiver already has the inner table reference type. This
        avoids the E0599 `as_ref` family while leaving Option receivers on
        the wrapper extraction path.
    **/
    function borrowedSortedTableReceiver(base:String):Bool {
        return base.indexOf("&*") >= 0;
    }

    function isRecordValueType(t:Type):Bool {
        return switch (Context.follow(t)) {
            case TAnonymous(_): true;
            case TType(d, _): switch (d.get().type) {
                    case TAnonymous(_): true;
                    case _: false;
                };
            case TInst(c, _): c.get().meta.has(":dataClass");
            case _: false;
        }
    }

    /**
        The emitted struct type when `t` is a non-interface business class
        whose fields cannot all derive PartialEq (StructFieldEq). A bare
        `==` on that struct would not compile, so the comparison lowers
        field-wise. Structs whose fields all implement PartialEq retain the
        native operator and return null here.
    **/
    function structFieldEq(t:Type):Null<ClassType> {
        // A Null-wrapped struct is Option<T> in Rust; field access on it
        // would be E0609, so the nullable path (nullableStructFieldEq) owns
        // the comparison and this gate must not follow through the wrapper.
        if (isNullType(t))
            return null;
        return switch (Context.follow(t)) {
            case TInst(c, _) if (!c.get().isInterface
                && RustDecl.isRecordModule(c.get().module)
                && !RustType.isPartialEqType(t)): c.get();
            case _: null;
        };
    }

    /**
        The emitted struct type when `t` is a Null-wrapped non-PartialEq
        business class (StructFieldEq). The Option<T> comparison matches
        both options and compares present values field-wise.
    **/
    function nullableStructFieldEq(t:Type):Null<ClassType> {
        if (!isNullType(t))
            return null;
        return structFieldEq(getNullInnerType(t));
    }

    /**
        The plain-class inner type when `t` is a Null-wrapped class that is
        neither a data class nor PartialEq (OptionPlainClassPresenceEq).
        Haxe class == is reference equality; the Option boundary never
        shares a reference, so the comparison reduces to presence.
    **/
    function nullablePlainClassEq(t:Type):Null<ClassType> {
        if (!isNullType(t))
            return null;
        return switch (Context.follow(getNullInnerType(t))) {
            case TInst(c, _) if (!c.get().meta.has(":dataClass")
                && !c.get().isInterface
                && RustDecl.isRecordModule(c.get().module)
                && !RustType.isPartialEqType(getNullInnerType(t))): c.get();
            case _: null;
        };
    }

    /**
        Field-wise equality text for an emitted struct with non-PartialEq
        fields (StructFieldEq). Each instance field compares with `==` when
        its type is PartialEq; an interface field compares by its haxe type
        name (the Box<dyn Trait> carries __haxe_type_name, matching the
        sameRole dispatch of the source); a nested struct recurses. The
        pieces join with `&&` in field declaration order.
    **/
    function structEqText(t:Type, left:String, right:String):String {
        final cls = structFieldEq(t);
        if (cls == null)
            return left + " == " + right;
        final parts = [];
        for (f in cls.fields.get()) {
            switch (f.kind) {
                case FVar(_, _):
                    final snake = RustImports.toSnakeCase(f.name);
                    final l = "(" + left + ")." + snake;
                    final r = "(" + right + ")." + snake;
                    if (RustType.isPartialEqType(f.type)) {
                        parts.push(l + " == " + r);
                    } else if (isNullableInterfaceType(f.type)) {
                        // NullableInterfaceFieldEq compares the trait objects
                        // inside Option without requiring PartialEq on them.
                        parts.push(nullableInterfaceFieldEqText(l, r));
                    } else if (isInterfaceType(f.type)) {
                        parts.push(l + ".__haxe_type_name() == " + r + ".__haxe_type_name()");
                    } else if (structFieldEq(f.type) != null) {
                        parts.push(structEqText(f.type, l, r));
                    }
                    // A field of any other non-PartialEq shape (function
                    // value, foreign class) is skipped: it cannot compare
                    // and the source's own equality helper covers it.
                case _:
            }
        }
        return parts.length > 0 ? parts.join(" && ") : "true";
    }

    /** Whether a Null<T> field lowers to Option<Box<dyn Trait>> (NullableInterfaceFieldEq). */
    function isNullableInterfaceType(t:Type):Bool {
        return isNullType(t) && isInterfaceType(getNullInnerType(t));
    }

    /** Compare nullable interface fields by presence and dynamic Haxe type name. */
    function nullableInterfaceFieldEqText(left:String, right:String):String {
        return "match (&" + left + ", &" + right + ") { (Some(__left), Some(__right)) => __left.__haxe_type_name() == __right.__haxe_type_name(), (None, None) => true, _ => false }";
    }

    function isTypeCopy(t:Type):Bool {
        if (t == null)
            return false;
        return switch (Context.follow(t)) {
            case TAbstract(a, _): final n = a.get().name; n == "Int" || n == "Bool" || n == "Float" || n == "Int64";
            case TAnonymous(anon):
                isAllCopy(anon.get().fields);
            case TType(d, _):
                switch (d.get().type) {
                    case TAnonymous(anon):
                        isAllCopy(anon.get().fields);
                    case _: false;
                }
            case TLazy(fn):
                isTypeCopy(fn());
            case TEnum(en, _):
                var copy = true;
                for (ef in en.get().constructs)
                    switch (Context.follow(ef.type)) {
                        case TFun(args, _) if (args.length > 0): copy = false;
                        case _:
                    }
                copy;
            case _: false;
        };
    }

    function isAllCopy(fields:Array<ClassField>):Bool {
        for (f in fields) {
            if (!isTypeCopy(f.type))
                return false;
        }
        return true;
    }

    /**
        The inner value of an Option comparison arm. A String inner must be
        owned: the Some of an Option<String> cannot hold a &str literal or a
        borrowed parameter's view.
    **/
    function optionSomeInner(e:TypedExpr):String {
        if (!isStringType(e.t))
            return expr(e);
        return switch (stripWrap(e).expr) {
            case TConst(TString(_)): expr(e) + ".to_string()";
            case TLocal(v) if (isBorrowedLocal(v)): expr(e) + ".to_string()";
            case TLocal(_): expr(e) + ".clone()";
            case _: expr(e);
        };
    }

    function binop(e:TypedExpr, op:Binop, l:TypedExpr, r:TypedExpr):String {
        final fromBe = tryMatchFromBeBytes(e);
        if (fromBe != null) {
            return fromBe;
        }
        switch (op) {
            case OpEq | OpNotEq if (isNullableCollapsedLocal(l) || isNullableCollapsedLocal(r)):
                // A collapsed Float local is a scalar; the other side's
                // integer literal widens into the Float domain so the two
                // Rust operands share one type.
                var collapsedLeft = expr(l);
                var collapsedRight = expr(r);
                if (isIntType(emittedType(l)) && isFloatType(emittedType(r)))
                    collapsedLeft = intToFloatText(collapsedLeft);
                else if (isIntType(emittedType(r)) && isFloatType(emittedType(l)))
                    collapsedRight = intToFloatText(collapsedRight);
                return collapsedLeft + " " + symbolOf(op) + " " + collapsedRight;
            case OpEq | OpNotEq if (nullableEnumComparedWithEnum(l.t, r.t) || nullableEnumComparedWithEnum(r.t, l.t)):
                // A narrowed operand renders the dereferenced match binding
                // even though its macro type is still Null<T>, so the
                // isNullType test alone leaves it bare against the sibling's
                // Option shape. A leading dereference marks the inner value
                // and wraps in Some like a non-null sibling.
                // (NarrowedNullableParam)
                final leftText = expr(l);
                final rightText = expr(r);
                final left = isNullType(l.t) ? (StringTools.startsWith(leftText, "*") ? "Some(" + leftText + ")" : leftText) : "Some(" + leftText + ")";
                final right = isNullType(r.t) ? (StringTools.startsWith(rightText, "*") ? "Some(" + rightText + ")" : rightText) : "Some(" + rightText + ")";
                return left + " " + symbolOf(op) + " " + right;
            // A nullable operand compared against the null literal lowers
            // to a predicate call: Option equality against None would
            // require PartialEq on the inner type, which the emitted
            // structs do not carry.
            case OpEq | OpNotEq if (isNullType(l.t) && !isNullType(r.t) && !isTNull(r) && narrowedSubject(l) != null):
                // Inside an option-narrowing match the nullable operand is
                // substituted by its scalar binding; the comparison uses the
                // bare value on both sides.
                return expr(l) + " " + symbolOf(op) + " " + expr(r);
            case OpEq | OpNotEq if (isNullType(r.t) && !isNullType(l.t) && !isTNull(l) && narrowedSubject(r) != null):
                return expr(r) + " " + symbolOf(op) + " " + expr(l);
            case OpEq | OpNotEq if (isNullType(l.t) && !isNullType(r.t) && !isTNull(r)):
                final test = expr(l) + ".as_ref().map_or(false, |v| v == &(" + optionSomeInner(r) + "))";
                return op == OpEq ? test : "!(" + test + ")";
            case OpEq | OpNotEq if (isNullType(r.t) && !isNullType(l.t) && !isTNull(l)
                && !(switch (stripWrap(r).expr) {
                    // A has-guarded ternary initializer materialized the
                    // inner scalar; the comparison is a plain scalar pair
                    // (HasGuardedTernaryLocals).
                    case TLocal(v): hasGuardedTernaryLocals.exists(v.id);
                    case _: false;
                })):
                final test = expr(r) + ".as_ref().map_or(false, |v| v == &(" + optionSomeInner(l) + "))";
                return op == OpEq ? test : "!(" + test + ")";
            // A non-nullable operand compared against null is a tautology:
            // the value can never be None, so the comparison emits a literal
            // consistent with the parameter declaration (== null is false,
            // != null is true). The predicate checks the emitted Rust type,
            // not the Haxe type, so implicit-nullable locals (Option in Rust)
            // keep their real comparison.
            // Covers the non-null-null-compare family.
            case OpEq | OpNotEq if (isTNull(r) && nonNullableInRust(l)):
                return op == OpEq ? "false" : "true";
            case OpEq | OpNotEq if (isTNull(l) && nonNullableInRust(r)):
                return op == OpEq ? "false" : "true";
            case OpEq | OpNotEq if ((isNullType(l.t) && isTNull(r)) || (isNullType(r.t) && isTNull(l))):
                final nullable = isNullType(l.t) ? l : r;
                return expr(nullable) + (op == OpEq ? ".is_none()" : ".is_some()");
            // Borrowed loop items render as references in Rust.
            case OpEq | OpNotEq if (borrowedComparableLoopItem(l) != null || borrowedComparableLoopItem(r) != null):
                final left = borrowedComparableLoopItem(l) != null ? "*" + expr(l) : expr(l);
                final right = borrowedComparableLoopItem(r) != null ? "*" + expr(r) : expr(r);
                return left + " " + symbolOf(op) + " " + right;
            // A trait-object operand (interface type) compares by its haxe
            // type name: the Box<dyn Trait> carries __haxe_type_name, and a
            // concrete singleton read (Solid.instance, Fill.instance) lowers
            // to its concrete value, so a direct `==` would compare
            // incompatible types. Both operands name the same trait object
            // when either is interface-typed (InterfaceEq).
            case OpEq | OpNotEq if (isInterfaceType(l.t) || isInterfaceType(r.t)):
                final left = expr(l);
                final right = expr(r);
                final eq = left + ".__haxe_type_name() == " + right + ".__haxe_type_name()";
                return op == OpEq ? eq : "!(" + eq + ")";
            // A struct whose fields cannot all derive PartialEq (for
            // example, an interface field lowers to Box<dyn Trait>) compares
            // field-wise: comparable fields use ==, interface fields compare
            // by their haxe type name, and nested structs recurse. The
            // conjunction is the == result; != negates it (StructFieldEq).
            // A Null-wrapped struct (Option<T>) matches both options: Some
            // pairs compare field-wise, both None are equal, and mixed
            // presence differs.
            case OpEq | OpNotEq if (structFieldEq(l.t) != null && structFieldEq(r.t) != null):
                final eq = structEqText(l.t, expr(l), expr(r));
                return op == OpEq ? eq : "!(" + eq + ")";
            case OpEq | OpNotEq if (nullableStructFieldEq(l.t) != null && nullableStructFieldEq(r.t) != null):
                final innerType = getNullInnerType(l.t);
                final leftName = freshRegionName("__left");
                final rightName = freshRegionName("__right");
                final eq = structEqText(innerType, leftName, rightName);
                final match = "match (&" + expr(l) + ", &" + expr(r) + ") { (Some(" + leftName + "), Some(" + rightName + ")) => " + eq
                    + ", (None, None) => true, _ => false }";
                return op == OpEq ? match : "!(" + match + ")";
            // An Option of a plain (non-data-class) class compares by
            // presence: Haxe class == is reference equality, and the
            // Option boundary never shares a reference, so equal means
            // both absent and unequal means any presence difference
            // (OptionPlainClassPresenceEq).
            case OpEq | OpNotEq if (nullablePlainClassEq(l.t) != null && nullablePlainClassEq(r.t) != null):
                final match = "match (&" + expr(l) + ", &" + expr(r) + ") { (None, None) => true, _ => false }";
                return op == OpEq ? match : "!(" + match + ")";
            case OpBoolAnd:
                // The typer folds `a && b && c` left-associatively, so the
                // single-term match below would narrow only the first
                // following term. Flatten the chain once: a null guard at
                // the left end proves its subject for every term after it,
                // and the whole chain renders inside one narrowing match.
                // (GuardedChainNarrowing)
                final chain:Array<TypedExpr> = [];
                function flattenChain(x:TypedExpr):Void {
                    switch (stripWrap(x).expr) {
                        case TBinop(OpBoolAnd, ll, rr): flattenChain(ll); flattenChain(rr);
                        case _: chain.push(x);
                    }
                }
                flattenChain(l);
                flattenChain(r);
                final chainGuard = nullGuardOf(chain[0]);
                if (chain.length >= 2 && chainGuard != null && !chainGuard.noneWhenTrue) {
                    final name = freshRegionName("__option");
                    optionNarrowings.push({subjectText: subjectTextOf(chainGuard.subject), name: name});
                    // Terms render in chain order, and a null check proves its
                    // subject only for the terms after it, exactly like the
                    // unflattened proven-chain rule. Proven subjects release
                    // once the match closes. (GuardedChainNarrowing)
                    final terms:Array<String> = [];
                    final provenNow:Array<TVar> = [];
                    for (i in 1...chain.length) {
                        terms.push(expr(chain[i]));
                        final midGuard = nullGuardOf(chain[i]);
                        if (midGuard != null)
                            switch (stripWrap(midGuard.subject).expr) {
                                case TLocal(v):
                                    provenNonNullVarIds.set(v.id, true);
                                    provenNow.push(v);
                                case _:
                            }
                    }
                    final hit = narrowedSubject(chainGuard.subject) != null;
                    optionNarrowings.pop();
                    for (v in provenNow)
                        provenNonNullVarIds.remove(v.id);
                    if (hit)
                        return "(match &(" + expr(chainGuard.subject) + ") { Some(" + name + ") => " + terms.join(" && ") + ", None => false })";
                }
                final guard = nullGuardOf(l);
                if (guard != null && !guard.noneWhenTrue) {
                    final name = freshRegionName("__option");
                    optionNarrowings.push({subjectText: subjectTextOf(guard.subject), name: name});
                    final right = expr(r);
                    final hit = narrowedSubject(guard.subject) != null;
                    optionNarrowings.pop();
                    if (hit)
                        return "(match &(" + expr(guard.subject) + ") { Some(" + name + ") => " + right + ", None => false })";
                }
                final proven = provenNonNullLocal(l);
                if (proven != null) {
                    provenNonNullVarIds.set(proven.id, true);
                    final right = expr(r);
                    provenNonNullVarIds.remove(proven.id);
                    return expr(l) + " && " + right;
                }
                // A `&&` chain of `!= null` checks proves every checked
                // local for the right operand; the single-local form above
                // covers the common case, this covers the chain.
                final provenChain = provenNonNullLocals(l);
                if (provenChain.length > 0) {
                    for (v in provenChain)
                        provenNonNullVarIds.set(v.id, true);
                    final right = expr(r);
                    for (v in provenChain)
                        provenNonNullVarIds.remove(v.id);
                    return expr(l) + " && " + right;
                }
                return nullableBoolOperand(l, expr(l)) + " && " + nullableBoolOperand(r, expr(r));
            case OpBoolOr:
                final guard = nullGuardOf(l);
                if (guard != null && guard.noneWhenTrue) {
                    final name = freshRegionName("__option");
                    optionNarrowings.push({subjectText: subjectTextOf(guard.subject), name: name});
                    final right = expr(r);
                    final hit = narrowedSubject(guard.subject) != null;
                    optionNarrowings.pop();
                    if (hit)
                        return "(match &(" + expr(guard.subject) + ") { None => true, Some(" + name + ") => " + right + " })";
                }
                // A `||` chain of `== null` checks proves every checked
                // local for the right operand: the chain is true when any
                // checked local is null, so reaching the right operand means
                // all checked locals hold Some. Covers the null-or-chain
                // guard family (an early-exit `if (a == null || b == null ||
                // ...) return;` proves a and b for the rest of the block).
                final orChain = provenNonNullOrChain(l);
                if (orChain.length > 0) {
                    for (v in orChain)
                        provenNonNullVarIds.set(v.id, true);
                    final right = expr(r);
                    for (v in orChain)
                        provenNonNullVarIds.remove(v.id);
                    return nullableBoolOperand(l, expr(l)) + " || " + right;
                }
                return nullableBoolOperand(l, expr(l)) + " || " + nullableBoolOperand(r, expr(r));
            case OpAssign:
                final map = mapAssignment(l);
                if (map != null) {
                    return expr(map.receiver) + ".insert(" + rustMapKey(map.key) + ", " + rustMapValue(r) + ")";
                }
                // A RefCell guard static assigns inside the with-closure:
                // the borrow_mut guard must not outlive it.
                // (RefCellStaticGuardScope)
                final refCellPath = refCellGuardStaticPath(l);
                if (refCellPath != null) {
                    final staticValue = if (StaticFieldHelper.isNullableType(l.t)) {
                        isTNull(r) ? "None" : (isInterfaceType(getNullInnerType(l.t)) && (isConcreteConstructor(r) || !isInterfaceType(r.t))
                            ? "Some(" + ownedNullInterfaceAssignValue(r) + ")"
                            : "Some(" + staticOwnedValue(r) + ")");
                    } else if (StaticFieldHelper.isStringType(l.t)) {
                        staticOwnedValue(r);
                    } else {
                        expr(r);
                    };
                    if (rhsMentionsGuardStatic(r)) {
                        final temp = freshRegionName("__rhs_value");
                        return "{ let " + temp + " = " + staticValue + "; " + refCellPath + ".with(|c| *c.borrow_mut() = " + temp + "); }";
                    }
                    return refCellPath + ".with(|c| *c.borrow_mut() = " + staticValue + ");";
                }
                final staticTarget = staticAssignmentTarget(l);
                if (staticTarget != null) {
                    final staticValue = if (StaticFieldHelper.isNullableType(l.t)) {
                        isTNull(r) ? "None" : (isInterfaceType(getNullInnerType(l.t)) && (isConcreteConstructor(r) || !isInterfaceType(r.t))
                            ? "Some(" + ownedNullInterfaceAssignValue(r) + ")"
                            : "Some(" + staticOwnedValue(r) + ")");
                    } else if (StaticFieldHelper.isStringType(l.t)) {
                        staticOwnedValue(r);
                    } else {
                        expr(r);
                    };
                    // The assignment target locks the guard mutex; a right
                    // side that reads any guard static holds its own guard
                    // until the end of the statement, so the target's lock
                    // would deadlock. Evaluate the right side into a fresh
                    // local first.
                    if (rhsMentionsGuardStatic(r)) {
                        final temp = freshRegionName("__rhs_value");
                        return "{ let " + temp + " = " + staticValue + "; " + staticTarget + " = " + temp + "; }";
                    }
                    return staticTarget + " = " + staticValue;
                }
                final rhs = if (isNullType(l.t) && !isNullType(r.t) && !isTNull(r) && !isNullableCollapsedLocal(l)) {
                    // Haxe unifies a concrete constructor's type to the
                    // interface even in a Null<Interface> assignment slot;
                    // recover the concrete class so the implementor still
                    // boxes into the Option<Box<dyn Trait>>.
                    if (isInterfaceType(getNullInnerType(l.t)) && (isConcreteConstructor(r) || !isInterfaceType(r.t)))
                        "Some(" + ownedNullInterfaceAssignValue(r) + ")";
                    else
                        "Some(" + ownedNullAssignValue(r) + ")";
                } else if (isImplicitNullableLocal(l) && !isNullType(r.t) && !isTNull(r)) {
                    // A non-null Haxe local backed by Option<T> storage
                    // (e.g. initializer from .get()) assigns a concrete
                    // value; wrap in Some to keep the Option shape.
                    "Some(" + ownedNullAssignValue(r) + ")";
                } else if (isNoneInitializedLocal(l) && !isNullType(r.t) && !isTNull(r)) {
                    // A local declared T but initialized to null literal
                    // keeps Option<T> storage; a non-null RHS wraps once at
                    // the assignment boundary.
                    "Some(" + ownedNullAssignValue(r) + ")";
                } else if (isNullableCollapsedLocal(l)) {
                    // A charCodeAt-collapsed local binds a scalar (u32);
                    // its assignments stay in that domain and must not
                    // re-wrap in Some(...).
                    final collapsedTarget = stripAssignTargetLocal(l);
                    numericAssignmentValue(l.t, r, renderValueForType(l.t, r, expr(r)), i32BindingLocals.exists(collapsedTarget) ? "i32" : null,
                        collapsedTarget >= 0 && !i32Locals.exists(collapsedTarget));
                } else if (isStringType(l.t) && !isNullType(l.t)) {
                    switch (stripWrap(r).expr) {
                        case TConst(TString(_)): expr(r) + ".to_string()";
                        // A String parameter renders as &str in the callee;
                        // the element slot owns its text, so the assigned
                        // value converts on the way in.
                        case TLocal(v) if (isBorrowedLocal(v)): expr(r) + ".to_string()";
                        default: expr(r);
                    }
                } else if (isOwnedVecType(l.t) && !isNullType(l.t) && borrowedArrayRead(r)) {
                    // An owned array local assigned a borrowed array
                    // parameter clones the referent; the local owns its
                    // storage, the parameter is a &Vec view.
                    "(*" + expr(r) + ").clone()";
                } else {
                    // A u32 local assigned a signed rendering reinterprets
                    // the bits at the assignment boundary; a local that
                    // already carries the signed domain keeps its rendering.
                    final assignTarget = stripAssignTargetLocal(l);
                    numericAssignmentValue(l.t, r, renderValueForType(l.t, r, expr(r)), i32BindingLocals.exists(assignTarget) ? "i32" : null,
                        assignTarget >= 0 && !i32Locals.exists(assignTarget));
                };
#if boring_fold_debug
                if (expr(r).indexOf("cached") >= 0 || expr(r).indexOf("decision") >= 0)
                    emissionTrace("ASSIGN target=" + assignTarget(l) + " val=[" + expr(r).substr(0, expr(r).length > 50 ? 50 : expr(r).length) + "]", e.pos);
#end
                final assignTargetText = assignTarget(l);
                // E0502: an array assignment whose index reads the array
                // itself (`bottoms[bottoms.len() - 1] = ...`) borrows the
                // array immutably in the index while the assignment mutates
                // it. Hoist the index into a fresh local and index the
                // target with that local so the immutable read completes
                // before the mutable write.
                final hoisted = switch (stripWrap(l).expr) {
                    case TArray(arr, idx):
                        switch (stripWrap(arr).expr) {
                            case TLocal(v) if (mentionsLocalName(idx, v.name)):
                                final temp = freshRegionName("__idx");
                                final targetWithTemp = "(" + expr(arr) + ")" + "[" + temp + "]";
                                "{ let " + temp + " = " + castArg(idx, "usize") + "; " + targetWithTemp + " = " + rhs + " }";
                            case _: null;
                        };
                    case _: null;
                };
                if (hoisted != null)
                    return hoisted;
                return assignTargetText + " = " + rhs;
            case OpAssignOp(inner):
                // Int compound assignments must preserve Haxe's 32-bit wrapping.
                final intCompound = switch (inner) {
                    case OpMult | OpAdd | OpSub
                        if (isIntType(l.t) && isLocalOrFieldTarget(l) && !isGenericLocal(l) && !isClosureParam(l) && !RustType.isTypeParam(l.t)):
                        final domain = i32LocalDomain(l) ? "i32" : types.of(l.t);
                        assignTarget(l)
                        + " = "
                        + domain
                        + "::"
                        + wrappingMethod(inner)
                        + "("
                        + assignTarget(l)
                        + ", "
                        + expr(r)
                        + ")";
                    case _: null;
                };
                if (intCompound != null)
                    return intCompound;
                // String accumulation borrows the operand: String
                // implements AddAssign<&str>, and the += desugaring makes
                // the right side a coercion site, so &(expr) accepts both
                // String expressions and literals.
                switch (inner) {
                    case OpAdd if (isStringType(l.t) && !isNullType(l.t) && isStringType(r.t) && !isNullType(r.t)):
                        return assignTarget(l) + " += &(" + expr(r) + ")";
                    case _:
                }
                // Haxe widens an Int operand in a Float compound assignment;
                // Rust has no `f64 op= {integer}`, so the right side takes the
                // same explicit Float cast ordinary Float operands use.
                if (isFloatType(l.t) && isIntType(emittedType(r)))
                    return assignTarget(l) + " " + symbolOf(inner) + "= " + intToFloatText(expr(r));
                // A Null<Float> right operand lowers to Option<Float>; Haxe
                // compound arithmetic uses the absent value's numeric zero,
                // so extract it before the op-assign reaches the target. A
                // has-guarded get ternary local already materialized the
                // inner value at its declaration, so the forcing read must
                // not re-apply (E0599 unwrap_or on the plain f64).
                if (isFloatType(l.t) && isNullType(r.t) && isFloatType(getNullInnerType(r.t))
                    && narrowedSubject(r) == null && !isNullableCollapsedLocal(r)
                    && !(switch (stripWrap(r).expr) {
                        case TLocal(v): hasGuardedTernaryLocals.exists(v.id);
                        case _: false;
                    }))
                    return assignTarget(l) + " " + symbolOf(inner) + "= " + expr(r) + ".unwrap_or(0.0)";
                return assignTarget(l) + " " + symbolOf(inner) + "= " + expr(r);
            case OpAdd if (isStringType(l.t) || isStringType(r.t)):
                final parts:Array<TypedExpr> = [];
                collectStringConcatOperands(e, parts);
                final slots = [for (_ in parts) "{}"];
                return "format!(\"" + slots.join("") + "\",\n            " + [for (part in parts) stringConcatOperand(part)].join(",\n            ") + "\n        )";
            case OpDiv if (StringTools.endsWith(operand(l, op, false), ".len()")):
                // A length divided by a Haxe-Int divisor: the divisor widens to
                // usize (T3, never truncates), the quotient is the target u32,
                // narrowed by the T4 mask.
                final lenDiv = "((" + operand(l, op, false) + ") / " + usizeIndex(operand(r, op, true)) + ")";
                return RustConversions.truncate(lenDiv, "u32");
            case OpMult | OpAdd | OpSub
                if (isIntType(e.t)
                    && !inGenericFunction
                    && !isGenericLocal(l)
                    && !isClosureParam(l)
                    && !RustType.isTypeParam(currentReturnType)
                    && !RustType.isTypeParam(e.t)
                    && !RustType.isTypeParam(l.t)
                    && !RustType.isTypeParam(r.t)):
                final wrapDomain = (i32OperandDomain(l) || i32OperandDomain(r) || i32InitializerTarget || i32ComparisonTarget) ? "i32" : types.of(e.t);
                return wrapDomain + "::" + wrappingMethod(op) + "(" + wrappingOperand(l, op, wrapDomain, true) + ", "
                    + wrappingOperand(r, op, wrapDomain, false) + ")";
            case OpMult | OpAdd | OpSub | OpDiv if (isFloatType(e.t)):
                final real = FloatPrecision.isF32() ? "f32" : "f64";
                // An integer operand crosses through its exact decimal
                // (T7), which rounds identically to `as` without a cast.
                final lStr = if (isIntType(l.t)) RustConversions.intToFloat(operand(l, op, false), real) else operand(l, op, false);
                final rStr = if (isIntType(r.t)) RustConversions.intToFloat(operand(r, op, true), real) else operand(r, op, true);
                return lStr + " " + symbolOf(op) + " " + rStr;
            case OpAnd:
                final rightInner = stripWrap(r);
                final isMask255 = switch (rightInner.expr) {
                    case TConst(TInt(255)): true;
                    case _: false;
                };
                if (isMask255) {
                    final byteExt = tryMatchByteExtract(l);
                    if (byteExt != null) {
                        // Byte extraction is emitted as u8, while Haxe Int
                        // arithmetic remains in the module's u32 domain.
                        return types.of(e.t) == "u32" ? "u32::from(" + byteExt + ")" : byteExt;
                    }
                }
                return (isInt64Type(l.t)
                    || isInt64Type(r.t) ? "(" + expr(l) + ") & (" + expr(r) + ")" : operand(l, op, false) + " & " + operand(r, op, true));
            case OpOr | OpXor if (isInt64Type(l.t) || isInt64Type(r.t)):
                return expr(l) + " " + symbolOf(op) + " " + expr(r);
            case OpUShr:
                // The u32 domain makes Rust >> the logical shift; operand()
                // re-adds grouping parens by precedence, so a bare shift
                // initializer carries no outer parentheses.
                return operand(l, op, false) + " >> " + operand(r, op, true);
            case OpShl:
                // Rust parses an unparenthesized cast immediately followed by
                // `<` as generic arguments (`x as u32 << y`), the same trap the
                // comparison case below groups around.  operand() decides by
                // precedence alone, which lets a path-call shift RHS through
                // bare (`as u32 << u32::wrapping_add(...)`), so group both
                // operands unconditionally.
                return "(" + operand(l, op, false) + ") << (" + operand(r, op, true) + ")";
            case OpLt if (isZero(r) && !i32LocalDomain(l) && (isUnsignedOperand(l) || businessIntExpr(l))):
                // A signed rendering such as an indexOf match compares its
                // absent case (-1) in the business u32 domain, so the upper
                // bound test needs the same-width reinterpretation first.
                final zeroLeft = operand(l, op, false);
                final zeroLeftText = rendersI32ComparisonOperand(l, zeroLeft)
                    ? RustConversions.reinterpret(zeroLeft, "u32") : zeroLeft;
                return "(" + zeroLeftText + ") > 2147483647";
            case OpGte if (isZero(r) && businessIntExpr(l)):
                // Mirror of the `x < 0` mapping above: the signed predicate
                // `x >= 0` excludes the wrapped-negative upper half, which
                // the unsigned rendering spells as the i32-bound check. A
                // plain comparison against zero would be a useless type-limit
                // test on u32. (UnsignedZeroBoundTest)
                final zeroLeft = operand(l, op, false);
                final zeroLeftText = rendersI32ComparisonOperand(l, zeroLeft)
                    ? RustConversions.reinterpret(zeroLeft, "u32") : zeroLeft;
                return "(" + zeroLeftText + ") <= 2147483647";
            case OpSub:
                return operand(l, op, false) + " - " + operand(r, op, true);
            case OpLt | OpLte | OpGt | OpGte:
                // Haxe permits chained comparisons. Evaluate each operand once
                // before combining the adjacent predicates; this also avoids
                // Rust's chained-comparison parse error.
                final chain = switch (stripWrap(l).expr) {
                    case TBinop(inner, a, b) if (inner == OpLt || inner == OpLte || inner == OpGt || inner == OpGte): {a: a, b: b};
                    case _: null;
                };
                if (chain != null) {
                    final leftName = freshRegionName("__cmp_left");
                    final middleName = freshRegionName("__cmp_middle");
                    final rightName = freshRegionName("__cmp_right");
                    return "{ let " + leftName + " = " + expr(chain.a) + "; let " + middleName + " = " + expr(chain.b) + "; let " + rightName + " = "
                        + expr(r) + "; (" + leftName + " " + symbolOf(switch (stripWrap(l).expr) {
                            case TBinop(inner, _, _): inner;
                            case _: OpLt;
                        }) + " " + middleName + ") && (" + middleName + " " + symbolOf(op) + " " + rightName + ") }";
                }
                // Rust std implements PartialOrd only between equal string
                // types: String compares with &str through PartialEq but
                // not PartialOrd, so an ordered string comparison moves
                // every owned operand to its str view first.
                if (isStringType(l.t) && isStringType(r.t)) {
                    return "(" + stringOrderOperand(l) + ") " + symbolOf(op) + " (" + stringOrderOperand(r) + ")";
                }
                // Rust parses an unparenthesized cast immediately followed by
                // `<` as generic arguments (`x as u32 < y`).  Comparisons are
                // a precedence boundary, so group both operands unconditionally.
                // Signed-domain locals make arithmetic on the other side signed.
                final signedComparison = i32LocalDomain(l) || i32LocalDomain(r) || rendersSignedIntExpr(l) || rendersSignedIntExpr(r);
                if (signedComparison)
                    i32ComparisonTarget = true;
                var leftText = operand(l, op, false);
                var rightText = operand(r, op, true);
                // Rust does not implicitly widen integer literals or Haxe
                // Int expressions when the other comparison operand is Float.
                if (isIntType(emittedType(l)) && isFloatType(emittedType(r)))
                    leftText = intToFloatText(leftText);
                if (isIntType(emittedType(r)) && isFloatType(emittedType(l)))
                    rightText = intToFloatText(rightText);
                // An ordered comparison keeps both sides in one Rust integer
                // type. When one operand renders in the signed i32 domain and
                // the other in the business u32 domain, reinterpret the u32
                // side. An integer literal keeps its inferred type.
                if (!isFloatType(emittedType(l)) && !isFloatType(emittedType(r))) {
                    final leftI32 = rendersI32ComparisonOperand(l, leftText);
                    final rightI32 = rendersI32ComparisonOperand(r, rightText);
                    final leftUsize = rendersUsizeComparisonOperand(l, leftText);
                    final rightUsize = rendersUsizeComparisonOperand(r, rightText);
                    final leftLiteral = switch (stripWrap(l).expr) {
                        case TConst(TInt(_)): true;
                        case _: false;
                    };
                    final rightLiteral = switch (stripWrap(r).expr) {
                        case TConst(TInt(_)): true;
                        case _: false;
                    };
                    if (leftI32 && !rightI32 && !rightUsize && !rightLiteral)
                        rightText = RustConversions.reinterpret(rightText, "i32");
                    else if (rightI32 && !leftI32 && !leftUsize && !leftLiteral)
                        leftText = RustConversions.reinterpret(leftText, "i32");
                    else if (leftUsize && !rightUsize && !leftI32 && !rightI32)
                        leftText = RustConversions.truncate(leftText, "u32");
                    else if (rightUsize && !leftUsize && !leftI32 && !rightI32)
                        rightText = RustConversions.truncate(rightText, "u32");
                }
                if (signedComparison)
                    i32ComparisonTarget = false;
#if boring_fold_debug
                if (leftText.indexOf("from_ne_bytes") >= 0 || rightText.indexOf("from_ne_bytes") >= 0)
                    emissionTrace("CMP left=[" + leftText + "] right=[" + rightText + "]", e.pos);
#end
                return "(" + leftText + ") " + symbolOf(op) + " (" + rightText + ")";

            case _:
                // A comparison between two nullable values keeps both sides
                // as Option: unwrapping either would make the operands
                // disagree on nullability (E0308). Only a nullable value
                // compared with a non-nullable one unwraps the nullable side.
                final bothNullable = isNullType(l.t) && isNullType(r.t);
                var left = isInt64Type(l.t) ? "(" + expr(l) + ")" : (bothNullable ? expr(l) : operand(l, op, false));
                var right = isInt64Type(r.t) ? "(" + expr(r) + ")" : (bothNullable ? expr(r) : operand(r, op, true));
                // Haxe unifies Int and Float; widen Int comparison operands to
                // Float when the other side is Float.
                if (isIntType(emittedType(l)) && isFloatType(emittedType(r)))
                    left = intToFloatText(left);
                if (isIntType(emittedType(r)) && isFloatType(emittedType(l)))
                    right = intToFloatText(right);
                // An i32-domain operand compared with a business u32 operand
                // reinterprets its bits so both sides share the u32 domain.
                if (isIntType(emittedType(l)) && isIntType(emittedType(r)) && !isFloatType(e.t)) {
                    final leftSigned = i32LocalDomain(l) || rendersSignedIntExpr(l);
                    final rightSigned = i32LocalDomain(r) || rendersSignedIntExpr(r);
                    if (leftSigned && !rightSigned)
                        left = RustConversions.reinterpret(left, "u32");
                    else if (rightSigned && !leftSigned)
                        right = RustConversions.reinterpret(right, "u32");
                }
                return left + " " + symbolOf(op) + " " + right;
        }
    }

    /**
        One operand of an ordered string comparison. A literal and a
        borrowed &str parameter already render as a str view; every other
        String expression is owned and moves to its str view through
        as_str, so both sides compare as str.
    **/
    function stringOrderOperand(e:TypedExpr):String {
        return switch (stripWrap(e).expr) {
            case TConst(TString(_)): expr(e);
            case TLocal(v) if (isBorrowedLocal(v)): expr(e);
            case _: "(" + expr(e) + ").as_str()";
        };
    }

    function nullableEnumComparedWithEnum(nullable:Type, value:Type):Bool {
        if (!isNullType(nullable))
            return false;
        return switch (Context.follow(getNullInnerType(nullable))) {
            case TEnum(_, _): switch (Context.follow(value)) {
                    case TEnum(_, _): true;
                    case _: false;
                };
            case _: false;
        };
    }

    /** Whether the operand renders as a non-Option Rust value. A non-null
        Haxe type that does not lower to Option (including implicit-nullable
        locals that do lower to Option) determines whether a null comparison
        is a tautology.
        Covers the non-null-null-compare family. **/
    function nonNullableInRust(e:TypedExpr):Bool {
        // The emitted Rust type text decides the null comparison: a value
        // whose rendering is not Option/Result can never be None. Reading
        // the type text directly keeps; the wrapper probe does not preserve
        // Null<T> typedefs that emit Option<T> as real predicates.
        final rustType = types.of(e.t, false);
        if (StringTools.startsWith(rustType, "Option<") || StringTools.startsWith(rustType, "Result<"))
            return false;
        return switch (stripWrap(e).expr) {
            case TLocal(v): !implicitNullableLocals.exists(v.id);
            case _: true;
        };
    }

    function provenNonNullLocal(e:TypedExpr):Null<TVar> {
        final inner = stripWrap(e);
        return switch (inner.expr) {
            case TBinop(OpNotEq, left, right):
                switch [stripWrap(left).expr, stripWrap(right).expr] {
                    case [TLocal(v), _] if (isTNull(right)): v;
                    case [_, TLocal(v)] if (isTNull(left)): v;
                    case _: null;
                };
            case _: null;
        };
    }

    /** The rendered receiver+key text of a sorted-map has() guard, or null.
        An `if (map.has(key))` block proves `map.get(key)` is Some, so the
        get() inside unwraps into its value slot. **/
    function mapHasGuard(e:TypedExpr):Null<String> {
        final inner = stripWrap(e);
        return switch (inner.expr) {
            case TCall(fn, args) if (args.length == 1):
                switch (stripWrap(fn).expr) {
                    case TField(subj, fa) if (fieldName(fa) == "has" && (isSortedTable(subj) || isSortedBuilder(subj))):
                        mapGetKeyText(subj, args[0]);
                    case _: null;
                };
            case _: null;
        };
    }

    /** The rendered receiver+key text of a sorted-map get() call. **/
    function mapGetKeyText(subj:TypedExpr, key:TypedExpr):String {
        return expr(subj) + "|" + expr(key);
    }

    /** Whether a sorted-map get() call is proven present by an enclosing
        has() guard on the same receiver+key. **/
    function provenMapGet(e:TypedExpr):Bool {
        final inner = stripWrap(e);
        return switch (inner.expr) {
            case TCall(fn, args) if (args.length == 1):
                switch (stripWrap(fn).expr) {
                    case TField(subj, fa) if (fieldName(fa) == "get" && (isSortedTable(subj) || isSortedBuilder(subj))):
                        final key = mapGetKeyText(subj, args[0]);
                        provenMapGets.indexOf(key) >= 0;
                    case _: false;
                };
            case _: false;
        };
    }

    /** Whether the expression names a local proven non-null by a guard. */
    function provenNonNullLocalExpr(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TLocal(v): provenNonNullVarIds.exists(v.id);
            case _: false;
        };
    }

    /**
        The forcing read of a proven non-null local subject: the guard proved
        the local is Some, so the read opens the local directly through a
        borrow. A non-proven subject renders nothing.
    **/
    function provenNonNullLocalSubject(subj:TypedExpr):Null<String> {
        final local = switch (stripWrap(subj).expr) {
            case TLocal(v): v;
            case _: null;
        };
        if (local == null || !provenNonNullVarIds.exists(local.id) || !receiverCarriesFallibleWrapper(subj))
            return null;
        return "(" + expr(subj) + ").as_ref().unwrap()";
    }

    /** The owned inner value of a proven-non-null local. A non-null
        declaration copying a verified-present nullable source clones
        the inner value into the declaration's storage.
        Covers the proven-non-null owned read family. **/
    function provenNonNullOwnedText(subj:TypedExpr):Null<String> {
        final local = switch (stripWrap(subj).expr) {
            case TLocal(v): v;
            case _: null;
        };
        if (local == null || !provenNonNullVarIds.exists(local.id) || !receiverCarriesFallibleWrapper(subj))
            return null;
        final inner = getNullInnerType(subj.t);
        final ref = "(" + expr(subj) + ").as_ref().unwrap()";
        return isTypeCopy(inner) ? "*" + ref : ref + ".clone()";
    }

    /** Every local a `&&` chain of `!= null` checks proves non-null. */
    function provenNonNullLocals(e:TypedExpr):Array<TVar> {
        final inner = stripWrap(e);
        return switch (inner.expr) {
            case TBinop(OpBoolAnd, l, r):
                provenNonNullLocals(l).concat(provenNonNullLocals(r));
            case TBinop(OpNotEq, left, right):
                switch [stripWrap(left).expr, stripWrap(right).expr] {
                    case [TLocal(v), _] if (isTNull(right)): [v];
                    case [_, TLocal(v)] if (isTNull(left)): [v];
                    case _: [];
                };
            case _: [];
        };
    }

    /** Every local a `||` chain of `== null` checks proves non-null for the
        right operand: the chain is true when any checked local is null, so
        evaluating the right operand means every checked local holds Some.
        Covers the null-or-chain guard family. **/
    function provenNonNullOrChain(e:TypedExpr):Array<TVar> {
        final inner = stripWrap(e);
        return switch (inner.expr) {
            case TBinop(OpBoolOr, l, r):
                provenNonNullOrChain(l).concat(provenNonNullOrChain(r));
            case TBinop(OpEq, left, right):
                switch [stripWrap(left).expr, stripWrap(right).expr] {
                    case [TLocal(v), TConst(TNull)]: [v];
                    case [TConst(TNull), TLocal(v)]: [v];
                    case _: [];
                };
            case _: [];
        };
    }

    /**
        rendersSignedIntExpr: an expression that lowers in the i32 domain
        without a local binding, so a comparison against it keeps the signed
        literal and the wrapping arithmetic.
    **/
    function rendersSignedIntExpr(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TCall(fn, _) if (isStringIndexOf(fn)): true;
            case TCall(fn, _) if (isVecIndexOf(fn)): true;
            case TCall(fn, _) if (isFpHelperI32Call(fn)): true;
            case TCall(fn, _) if (isResidentI32Call(fn)): true;
            // Unary negation lowers in the signed i32 domain in a business
            // module, so the operator never applies `-` to a u32 operand.
            case TUnop(OpNeg, _, subj): isIntType(subj.t) && !RuntimeResidents.isResident(imports.selfModule);
            case _: false;
        };
    }

    /**
        rendersI32ComparisonOperand: an ordered comparison operand that already
        lowers in the signed i32 domain. The rendered text carries the wrapping
        and reinterpretation forms; a plain i32 local or an indexOf result is
        signed by construction.
    **/
    /**
        rendersSignedIntArg: an Int argument that lowers in the signed i32
        domain. A wrapping binop, reinterpretation, indexOf result, or an
        i32-domain local or its negation is signed; the caller reinterprets
        the rendered text when the target slot is the business u32 domain.
    **/
    function rendersSignedIntArg(arg:TypedExpr, text:String):Bool {
        if (StringTools.startsWith(text, "i32::") || StringTools.startsWith(text, "(i32::")
            || StringTools.startsWith(text, "match ") || StringTools.startsWith(text, "(match "))
            return true;
        if (rendersSignedIntExpr(arg))
            return true;
        return switch (stripWrap(arg).expr) {
            case TUnop(_, _, subj): i32LocalDomain(subj) || rendersSignedIntExpr(subj);
            case _: i32LocalDomain(arg);
        };
    }

    function rendersI32ComparisonOperand(e:TypedExpr, text:String):Bool {
        // A resident module renders every Int in the signed i32 domain.
        if (RuntimeResidents.isResident(imports.selfModule))
            return true;
        if (StringTools.startsWith(text, "i32::") || StringTools.startsWith(text, "(i32::")
            || StringTools.startsWith(text, "match ") || StringTools.startsWith(text, "(match "))
            return true;
        return i32LocalDomain(e) || rendersSignedIntExpr(e);
    }

    /**
        rendersUsizeComparisonOperand: an ordered comparison operand that
        lowers as a Rust usize. A length read and a nullable length read (the
        as_ref/map_or form) are the two shapes; the business Int side narrows
        the usize operand to the comparison's u32 domain.
    **/
    function rendersUsizeComparisonOperand(e:TypedExpr, text:String):Bool {
        if (StringTools.startsWith(text, "usize::") || StringTools.endsWith(text, ".len()"))
            return true;
        return text.indexOf(".as_ref().map_or(0, |v| v.len())") >= 0;
    }

    /**
        isVecIndexOf: an Array<T> indexOf call, whose lowering yields the same
        signed match as the String form.
    **/
    function isVecIndexOf(fn:TypedExpr):Bool {
        return switch (stripWrap(fn).expr) {
            case TField(subj, FInstance(_, _, cf)) if (cf.get().name == "indexOf" && isVecType(subj)): true;
            case _: false;
        };
    }

    function isZero(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TConst(TInt(0)): true;
            case _: false;
        };
    }

    /**
        Whether an Int declaration's initializer renders in the signed i32
        domain. A String.indexOf call lowers to a match that yields i32
        (narrowI32 on the found offset, -1 for the absent case); a wrapping
        binop under i32InitializerTarget renders i32. Every other Int
        initializer renders in the business u32 domain.
    **/
    function declarationRendersI32(init:TypedExpr):Bool {
        return switch (stripWrap(init).expr) {
            case TCall(fn, _) if (isStringIndexOf(fn)): true;
            case TBinop(OpAdd | OpSub | OpMult, _, _): true;
            case _: false;
        };
    }

    /** True when the local is a countdown loop variable with a `>= 0` guard. */
    function isSignedCountdownVar(v:TVar):Bool {
        return signedCountdownVars.exists(v.id);
    }

    function isUnderflowProneIntExpr(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TBinop(OpSub, value, amount):
                switch ([stripWrap(value).expr, stripWrap(amount).expr]) {
                    case [TField(_, FInstance(_, _, field)), TConst(TInt(k))] if (field.get().name == "length" && k > 0): true;
                    case _: false;
                }
            case _: false;
        };
    }

    /**
        Haxe Int reaches Rust as u32 for values and usize for byte positions, so
        a negative-domain check can only be expressed as an upper-bound check on
        those operands; signed operands keep the literal comparison.
    **/
    function isUnsignedOperand(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TLocal(v): unsignedLocals.exists(v.id) || (paramVarIds.exists(v.id)
                    && isUnsignedTypeName(argTypes.get(v.name))) || (isIntType(v.t) && !RuntimeResidents.isResident(imports.selfModule));
            case _: false;
        };
    }

    /**
        Whether a Haxe Int expression renders in the business u32 domain:
        a negative test against literal zero must then read as an
        upper-bound check on the unsigned rendering.
    **/
    function businessIntExpr(e:TypedExpr):Bool {
        if (!isIntType(e.t) || RuntimeResidents.isResident(imports.selfModule))
            return false;
        if (i32OperandDomain(e) || i32LocalDomain(e))
            return false;
        return true;
    }

    function isUnsignedTypeName(n:Null<String>):Bool {
        return n == "u16" || n == "u32" || n == "usize";
    }

    function operand(e:TypedExpr, parent:Binop, isRight:Bool):String {
        var rendered = expr(e);
        // Null<Int> is represented as Option<u32>. Haxe permits it to enter
        // numeric expressions; the target contract uses zero for the absent
        // value, consistently at every arithmetic operand boundary.
        if (isNullType(e.t) || isStringCharCodeAtCall(e)) {
            switch (stripWrap(e).expr) {
                case TCall(fn, _) if (isStringCharCodeAt(fn)):
                    rendered += ".unwrap_or(0)";
                case TLocal(v) if (provenNonNullVarIds.exists(v.id)
                    && isIntType(getNullInnerType(e.t))
                    && narrowedSubject(e) == null && !isNullableCollapsedLocal(e)
                    && !StringTools.startsWith(rendered, "&")):
                    // A proven-non-null nullable Int local (an early-exit or
                    // && guard proved the Option holds Some) unwraps to its
                    // inner scalar before arithmetic/comparison. A narrowed
                    // operand already renders its scalar match binding and a
                    // collapsed local already materialized the inner scalar,
                    // so neither must unwrap again.
                    if (RustShapeParse.shapeOf(rendered) != RustShape.ShapeBare)
                        rendered = "*(" + rendered + ").as_ref().unwrap()";
                case TLocal(v) if (isIntType(getNullInnerType(e.t))
                    && narrowedSubject(e) == null && !isNullableCollapsedLocal(e)
                    && !StringTools.startsWith(rendered, "&")):
                    // A nullable Int local that no guard proved present
                    // enters arithmetic/comparison through Haxe's null-to-zero
                    // bridge: the absent value is numeric zero.
                    rendered += ".unwrap_or(0)";
                case _:
            }
        }
        // A nullable local proven non-null by an early-exit guard holds the
        // inner value; arithmetic on it must unwrap the Option (the guard
        // proved Some). Covers the proven-non-null arithmetic operand family.
        // An Int local was already unwrapped by the Int branch above, so it
        // must not re-apply (E0599 as_ref on the scalar u32).
        if (isNullType(e.t) && switch (stripWrap(e).expr) {
            case TLocal(v): provenNonNullVarIds.exists(v.id) && !isIntType(getNullInnerType(e.t));
            case _: false;
        }) {
            final inner = getNullInnerType(e.t);
            if (RustShapeParse.shapeOf(rendered) != RustShape.ShapeBare)
                rendered = isTypeCopy(inner) ? "*((" + rendered + ").as_ref().unwrap())" : "(" + rendered + ").as_ref().unwrap()";
        } else if (isNullType(e.t) && isFloatType(getNullInnerType(e.t))
            && narrowedSubject(e) == null && !isNullableCollapsedLocal(e)
            && !isNonNullRenderedConditional(e)
            && !(switch (stripWrap(e).expr) {
                case TLocal(v): hasGuardedTernaryLocals.exists(v.id);
                case _: false;
            })
            // A rendered text that already evaluates bare (a guarded-ternary
            // whose arms unwrapped) must not unwrap again: the text pass is
            // the authority. (ShapeParse)
            && RustShapeParse.shapeOf(rendered) != RustShape.ShapeBare) {
#if boring_fold_debug
            Context.warning("ORPROBE shape=" + Std.string(RustShapeParse.shapeOf(rendered)) + " txt=[" + rendered.substr(0, rendered.length > 70 ? 70 : rendered.length) + "]", e.pos);
#end
            // Null<Float> lowers to Option<Float>. Haxe arithmetic uses the
            // absent value's numeric zero, so extract that value before the
            // operand reaches the operator. A narrowed operand already renders
            // its scalar match binding and a collapsed local already materialized
            // the inner scalar, so neither must unwrap again.
            rendered += ".unwrap_or(0.0)";
        }
        switch (e.expr) {
            case TBinop(op, _, _):
                final cp = precedenceOf(op);
                final pp = precedenceOf(parent);
                var parens = cp < pp || (cp == pp && (!associative(op) || isRight));
                return parens ? "(" + rendered + ")" : rendered;
            case _:
                return rendered;
        }
    }

    function unop(e:TypedExpr, op:Unop, post:Bool, subj:TypedExpr):String {
        final inner = expr(subj);
        switch (op) {
            case OpNot:
                return "!" + inner;
            case OpNegBits:
                return "!" + inner;
            case OpNeg:
                // Haxe Int values are unsigned in resident modules, while
                // unary negation requires the signed i32 domain. Preserve the
                // signed result at this operator boundary so Rust does not
                // apply unary `-` to u32 (E0600).
                if (isIntType(subj.t) && !RuntimeResidents.isResident(imports.selfModule))
                    return "-(" + inner + " as i32)";
                // Null<Float> lowers to Option<Float>. Haxe arithmetic uses
                // the absent value's numeric zero, so extract that value
                // before applying unary negation. This is the nullable-float
                // unary boundary rule and covers both precision targets.
                if (isNullType(subj.t) && isFloatType(getNullInnerType(subj.t)))
                    return "-(" + inner + ".unwrap_or(0.0))";
                return "-" + inner;
            case OpIncrement:
                return post ? "({ let t = " + inner + "; " + inner + " += 1; t })" : "({ " + inner + " += 1; " + inner + " })";
            case OpDecrement:
                return post ? "({ let t = " + inner + "; " + inner + " -= 1; t })" : "({ " + inner + " -= 1; " + inner + " })";
            case _:
                return fail(e, "unary operator has no lowering: " + Std.string(op));
        }
    }

    function int64Expression(e:TypedExpr):Null<String> {
        return switch (e.expr) {
            case TCall(fn, args): int64Call(fn, args);
            case _: null;
        };
    }

    function int64Call(fn:TypedExpr, args:Array<TypedExpr>):Null<String> {
        return int64CallText(fn, args);
    }

    /**
        Folds an integer-literal `as` cast into a typed literal, matching the
        bitwise result of `(x) as T` for the module's integer domain. Returns
        null when `e` is not an integer constant, so the caller falls back to a
        runtime cast. A Haxe Int literal is the signed i32 value; the business-
        module u32 rendering is its low 32 bits, so widening casts of such a
        literal are the unsigned decimal and a cast to i32 is the signed value.
        The same v + 4294967296 arithmetic the bare literal renderer uses (in
        `expr` for a negative business constant) yields that unsigned decimal.
        Resident modules keep the signed rendering.
    **/
    function constantCast(e:TypedExpr, ty:String):Null<String> {
        switch (stripWrap(e).expr) {
            case TConst(TInt(v)):
                if (ty == "u64") {
                    // A resident negative i32 constant casts with sign extension,
                    // which the emitter never requests (Int64 and sha literals are
                    // positive domain constants), so fall back to a runtime cast
                    // for that rare case.
                    if (RuntimeResidents.isResident(imports.selfModule) && v < 0)
                        return null;
                }
                final unsigned = v < 0 ? Std.string(v + 4294967296) : Std.string(v);
                // The folded literal is a typed integer literal, whose precedence
                // binds as tightly as any parenthesized atom, so it can stand
                // bare wherever `(x) as T` used to stand without altering
                // precedence or triggering unnecessary-parens warnings.
                switch (ty) {
                    case "u32": return unsigned + "u32";
                    case "i32": return v + "i32";
                    case "i64":
                        if (RuntimeResidents.isResident(imports.selfModule))
                            return v + "i64";
                        return unsigned + "i64";
                    case "u64": return unsigned + "u64";
                    case "usize": return unsigned + "usize";
                    case "u8": return (v & 0xFF) + "u8";
                    case "u16": return (v & 0xFFFF) + "u16";
                    case "f64": return unsigned + ".0";
                    case "f32": return unsigned + ".0f32";
                    default: return null;
                }
            default:
                return null;
        }
    }

    /**
        A Float-domain Math argument. The typer widens an Int operand to
        the Float parameter implicitly; rust needs the explicit crossing.
        A bare int literal stays as written because rust infers it into
        the parameter type, keeping existing trees unchanged.
    **/
    /** Types an integer literal used to initialize an Int local before method use. */
    function integerBindingLiteral(value:Int, localId:Int = -1):String {
        // An i32-domain local declares a negative value as the signed
        // literal so the binding carries the signed domain; a positive value
        // stays bare because its uses (wrapping arithmetic, comparisons)
        // infer i32. A local outside that domain keeps the wrapped u32
        // decimal the business domain expects.
        if (i32Locals.exists(localId)) {
            if (value < 0 && RuntimeResidents.isResident(imports.selfModule))
                return Std.string(value);
            if (value < 0)
                return Std.string(value) + "i32";
            return Std.string(value);
        }
        if (value < 0 && !RuntimeResidents.isResident(imports.selfModule))
            return Std.string(value + 4294967296) + "u32";
        return Std.string(value) + (RuntimeResidents.isResident(imports.selfModule) ? "i32" : "u32");
    }

    function mathFloatArg(a:TypedExpr):String {
        return switch (stripWrap(a).expr) {
            case TConst(TInt(v)):
                // Math arguments are Float even when the typed AST retains the
                // original Int constant. Suffixing this literal prevents Rust
                // method calls from leaving its numeric type ambiguous.
                Std.string(v) + ".0" + (FloatPrecision.isF32() ? "f32" : "f64");
            case _ if (isIntType(emittedType(a))): intToFloatText(expr(a));
            case _:
                // A nullable local proven non-null by a guard holds the inner
                // float; the Math call must unwrap the Option (the guard
                // proved Some). Covers the proven-non-null Math operand family.
                if (isNullType(a.t) && switch (stripWrap(a).expr) {
                    case TLocal(v): provenNonNullVarIds.exists(v.id);
                    case _: false;
                }) {
                    final inner = getNullInnerType(a.t);
                    final rendered = expr(a);
                    RustShapeParse.shapeOf(rendered) != RustShape.ShapeBare
                        ? isTypeCopy(inner) ? "*((" + rendered + ").as_ref().unwrap())" : "(" + rendered + ").as_ref().unwrap()"
                        : rendered;
                } else {
                    expr(a);
                }
        };
    }

    function mathFloatBindingArg(a:TypedExpr):String {
        final rendered = mathFloatArg(a);
        if (rendered.length >= 2 && rendered.charAt(0) == "(" && rendered.charAt(rendered.length - 1) == ")")
            return rendered.substr(1, rendered.length - 2);
        return rendered;
    }

    /** Folds an integer-constant cast to a typed literal, else renders the runtime cast. */
    function castArg(e:TypedExpr, ty:String):String {
        final folded = constantCast(e, ty);
        if (folded != null)
            return folded;
        if (ty == "usize") {
            // Index positions reach Rust as usize from a Haxe Int (u32)
            // source; the T3 form preserves every representable value and
            // never truncates, so it is allowed wherever the old `as usize`
            // index stood. usize::try_from(u32) always succeeds, making the
            // unwrap_or(0) arm unreachable.
            // A nullable Int proven non-null by a guard holds the inner u32;
            // unwrap it before the try_from so the index is not Option<u32>.
            if (isNullType(e.t) && provenNonNullLocalExpr(e)) {
                final inner = getNullInnerType(e.t);
                final rendered = expr(e);
                final unwrapped = RustShapeParse.shapeOf(rendered) != RustShape.ShapeBare
                    ? (isTypeCopy(inner) ? "*((" + rendered + ").as_ref().unwrap())" : "(" + rendered + ").as_ref().unwrap()")
                    : rendered;
                return usizeIndex(unwrapped);
            }
            // Nullable integer indices must be unwrapped before TryFrom;
            // Haxe's null-to-zero numeric boundary supplies the default. A
            // narrowed or collapsed operand already renders the inner scalar
            // match binding, so the unwrap_or would apply to the reference
            // binding and E0599s (GuardedChainNarrowing).
            if (isNullType(e.t) && isIntType(getNullInnerType(e.t))
                && narrowedSubject(e) == null && !isNullableCollapsedLocal(e)) {
                final rendered = expr(e);
                if (!StringTools.startsWith(rendered, "*"))
                    return usizeIndex(rendered + ".unwrap_or(0)");
                return usizeIndex(rendered);
            }
            return usizeIndex(expr(e));
        }
        if (ty == "u8") {
            // A u8 target (Bytes element stores) truncates the source the
            // way Rust `as u8` does: mask the low byte, then try_from. The
            // literal fold above has already run, so only real expressions
            // reach this branch.
            return RustConversions.truncate(expr(e), "u8");
        }
        return "(" + expr(e) + ") as " + ty;
    }

    /** T3 index form for an already-rendered source expression. */
    function usizeIndex(rendered:String):String {
        // The call parentheses already delimit the argument, so an outer
        // grouping of the rendered source (a block expression, a parenthesized
        // binop) is dropped to keep the generated code free of
        // unnecessary-parens warnings.
        var inner = rendered;
        if (StringTools.startsWith(inner, "(") && StringTools.endsWith(inner, ")") && matchingParens(inner)) {
            inner = inner.substr(1, inner.length - 2);
        }
        return "usize::try_from(" + inner + ").unwrap_or(0)";
    }

    /**
        Reinterpret a same-width u32-domain business value into the signed i32
        position a resident runtime parameter expects. Folds a literal to its
        signed value; otherwise goes through the native-endian byte round-trip
        (T5). This is the drop-in for the `(x) as i32` cast on such boundaries.
    **/
    function castSignedI32(e:TypedExpr):String {
        final folded = constantCast(e, "i32");
        if (folded != null)
            return folded;
        // In a resident module Haxe Int is already i32, so `(x) as i32` is a
        // no-op and the expression renders bare (this keeps integer locals
        // inferable). In a business module the value is u32 and the same-width
        // cast reinterprets bits (T5).
        if (RuntimeResidents.isResident(imports.selfModule))
            return expr(e);
        // A generic static call's return type is inferred from its context;
        // `.to_ne_bytes()` alone leaves it ambiguous (E0689), so an
        // annotated binding pins the u32 domain before the byte round-trip.
        if (genericStaticCallArg(e)) {
            return "{ let v: u32 = " + expr(e) + "; i32::from_ne_bytes(v.to_ne_bytes()) }";
        }
        final literal = switch (stripWrap(e).expr) {
            case TConst(TInt(v)): true;
            default: false;
        };
        if (literal)
            return RustConversions.reinterpret(types.of(e.t, false) == "u32" ? expr(e) : "0u32", "i32");
        return RustConversions.reinterpret(expr(e), "i32");
    }

    /** Casts an Int shift count to u32 (a no-op in business, reinterpret in resident). */
    function castShiftU32(e:TypedExpr):String {
        final folded = constantCast(e, "u32");
        if (folded != null)
            return folded;
        if (RuntimeResidents.isResident(imports.selfModule))
            return RustConversions.reinterpret(expr(e), "u32");
        // An i32-domain index reaching the u32 charCodeAt slot reinterprets
        // its bits; the slot is the business u32 domain.
        if (i32LocalDomain(e) && !isNullType(e.t))
            return RustConversions.reinterpret(expr(e), "u32");
        return expr(e);
    }

    function int64CallText(fn:TypedExpr, args:Array<TypedExpr>):Null<String> {
        function topClass(e:TypedExpr):Int {
            return switch (stripWrap(e).expr) {
                case TCall(callee, _): switch (stripWrap(callee).expr) {
                        case TField(_, FStatic(c, f)) if (c.get().module == "haxe.Int64" && c.get().name == "Int64_Impl_"):
                            switch (f.get().name) {
                                case "make" | "or": 1;
                                case "xor": 2;
                                case "and": 3;
                                case "ofInt" | "getLow" | "get_low" | "getHigh" | "get_high" | "ushr": 90;
                                case _: 100;
                            };
                        case _: 100;
                    };
                case TBinop(op, _, _): switch (op) {
                        case OpOr: 1;
                        case OpXor: 2;
                        case OpAnd: 3;
                        case _: 100;
                    };
                case _: 100;
            };
        }
        function infixOperand(e:TypedExpr, parentClass:Int):String {
            final text = expr(e);
            return topClass(e) < parentClass ? "(" + text + ")" : text;
        }
        function receiverOperand(e:TypedExpr):String {
            final text = expr(e);
            return topClass(e) == 100 ? text : "(" + text + ")";
        }
        function castOperand(e:TypedExpr, ty:String):String {
            final folded = constantCast(e, ty);
            if (folded != null)
                return folded;
            return "(" + expr(e) + ") as " + ty;
        }

        /** T2 widen of a u32-domain word into i64 (positive), folding literals. */
        function widenI64(e:TypedExpr):String {
            final folded = constantCast(e, "i64");
            if (folded != null)
                return folded;
            return "i64::from(" + expr(e) + ")";
        }

        /** Sign-extends a Haxe Int to i64 (Int64.ofInt). */
        function signExtendI64(e:TypedExpr):String {
            switch (stripWrap(e).expr) {
                case TConst(TInt(v)):
                    // `(x as i32) as i64` of a literal is its signed value.
                    return v + "i64";
                default:
            }
            if (RuntimeResidents.isResident(imports.selfModule)) {
                return "i64::from(" + expr(e) + ")";
            }
            return RustConversions.ofInt(expr(e));
        }

        return switch (PolicyQueries.int64OpOf(fn, args)) {
            case Make(high, low): widenI64(high) + " << 32 | " + widenI64(low);
            case OfInt(value): signExtendI64(value);
            case GetHigh(value): if (isFpHelperInt64Halves(value)) expr(value) + ".high" else RustConversions.truncate("(" + receiverOperand(value) +
                    " >> 32)", "u32");
            case GetLow(value): if (isFpHelperInt64Halves(value)) expr(value) + ".low" else RustConversions.truncate(expr(value), "u32");
            case Add(l, r): receiverOperand(l) + ".wrapping_add(" + expr(r) + ")";
            case Sub(l, r): receiverOperand(l) + ".wrapping_sub(" + expr(r) + ")";
            case Mul(l, r): "(" + expr(l) + ").wrapping_mul(" + expr(r) + ")";
            case MulInt(l, r): "(" + expr(l) + ").wrapping_mul(i64::from(" + expr(r) + "))";
            case And(l, r): infixOperand(l, 3) + " & " + infixOperand(r, 3);
            case Or(l, r): infixOperand(l, 1) + " | " + infixOperand(r, 1);
            case Xor(l, r): infixOperand(l, 2) + " ^ " + infixOperand(r, 2);
            case Complement(value): "!" + expr(value);
            case Shl(l, r): receiverOperand(l) + ".wrapping_shl(" + castShiftU32(r) + ")";
            case Shr(l, r): receiverOperand(l) + ".wrapping_shr(" + castShiftU32(r) + ")";
            case Ushr(l, r): RustConversions.shrLogicalI64(expr(l), castShiftU32(r));
            case Eq(l, r): expr(l) + " == " + expr(r);
            case Neq(l, r): expr(l) + " != " + expr(r);
            case Lt(l, r): expr(l) + " < " + expr(r);
            case Gt(l, r): expr(l) + " > " + expr(r);
            case Lte(l, r): expr(l) + " <= " + expr(r);
            case Gte(l, r): expr(l) + " >= " + expr(r);
            case null: null;
        };
    }

    function isFpHelperInt64Halves(e:TypedExpr):Bool {
        return PolicyQueries.isFpHelperInt64Halves(e, fpInt64Halves);
    }

    function isFpHelperInt64Call(fn:TypedExpr):Bool {
        return PolicyQueries.isFpHelperInt64Call(fn);
    }

    /** Whether the call is an FPHelper bit edge whose result is i32. */
    function isFpHelperI32Call(fn:TypedExpr):Bool {
        return switch (stripWrap(fn).expr) {
            case TField(_, FStatic(c, cf)) if (c.get().module == "haxe.io.FPHelper"):
                cf.get().name == "floatToI32" || cf.get().name == "f32ToI32";
            case _: false;
        };
    }

    /**
        Resident-module methods whose emitted signature returns i32: the
        sorted-table size query. A u32-domain operand compared against such
        a call reconciles into the signed domain.
        (ResidentI32Comparison)
    **/
    function isResidentI32Call(fn:TypedExpr):Bool {
        return switch (stripWrap(fn).expr) {
            case TField(_, FInstance(c, _, cf)) if (cf.get().name == "size"):
                RuntimeResidents.isResident(c.get().module);
            case _: false;
        }
    }

    function isRecursiveField(subj:TypedExpr, name:String):Bool {
        return switch (Context.follow(subj.t)) {
            case TInst(c, _):
                final owner = c.get();
                for (field in owner.fields.get())
                    if (field.name == name)
                        return types.recursiveClassField(field.type, owner) != types.of(field.type);
                false;
            case _: false;
        };
    }

    function field(subj:TypedExpr, fa:FieldAccess):String {
        switch (fa) {
            case FStatic(c, cf):
                final cls = c.get();
                final name = cf.get().name;
                final valueType = ValueTypeSupport.markedAbstractOfClass(cls);
                if (valueType != null) {
                    imports.requireType(valueType.module, valueType.name);
                    final field = cf.get();
                    final isConst = valueTypeStaticIsConst(field);
                    final item = valueType.name + "::" + (isConst ? RustImports.toScreamingSnakeCase(name) : RustImports.toSnakeCase(name));
                    return isConst ? item : item + "()";
                }
                if (RustDecl.usesLazyLockStatic(cls, cf.get(), state)) {
                    // LazyLock owns its value. Static reads cross Haxe value
                    // boundaries, so clone the referent before passing it
                    // to constructors.
                    return "(*" + staticItemPath(cls, name) + ").clone()";
                }
                if (isGuardStaticField(cls, name)) {
                    if (StaticFieldHelper.isConstruction(cf.get().expr()) && !StaticFieldHelper.isSelfConstruction(cf.get(), cls)) {
                        return "&*" + staticItemPath(cls, name);
                    }
                    final guard = staticGuard(cls, name);
                    return StaticFieldHelper.isArrayType(cf.get().type) ? guard : staticGuardClone(cls, name);
                }
                final rendered = staticRef(cls, name);
                if (StaticFieldHelper.isArrayType(cf.get().type))
                    return rendered + ".to_vec()";
                return StaticFieldHelper.isStringType(cf.get().type) ? rendered + ".to_string()" : rendered;
            case FEnum(e, ef):
                final en = e.get();
                imports.requireType(en.module, en.name);
                return en.name + "::" + RustImports.toUpperCamelCase(ef.name);
            case FInstance(_, _, cf) | FAnon(cf):
                final name = cf.get().name;
                final folded = foldedExceptionMessage(subj, name);
                if (folded != null) {
                    return folded;
                }
                {
                    final bound = catchPayloadAccess(subj, name);
                    if (bound != null) {
                        return bound;
                    }
                }
                if (name == "message" || name == "get_message") {
                    switch (stripWrap(subj).expr) {
                        case TLocal(v) if (catchVars.exists(v.id)):
                            // Display carries the message text of the variant
                            // (features/06: messages are display text).
                            return "format!(\"{}\", " + RustImports.toSnakeCase(localName(v)) + ")";
                        case _:
                    }
                }
                final staticGuard = staticGuardOf(subj);
                if (staticGuard != null) {
                    if (name == "length") {
                        return rustU32Length(staticGuard + ".len()");
                    }
                    return staticGuard + "." + RustImports.toSnakeCase(name);
                }
                if (name == "length") {
                    if (isNullType(subj.t) || isImplicitNullableLocal(subj) || isNoneInitializedLocal(subj)) {
                        // A null-coalescing initializer materialized the
                        // inner value into the local: the local is a plain
                        // collection, so its length is a direct len() read.
                        final collapsed = switch (stripWrap(subj).expr) {
                            case TLocal(v): nullableCollapsedLocals.exists(v.id)
                                || hasGuardedTernaryLocals.exists(v.id);
                            case _: false;
                        };
                        if (collapsed) {
                            return RustConversions.truncate(expr(subj) + ".len()", "u32");
                        }
                        // An enclosing null guard already collapsed the
                        // Option: the binding references the collection
                        // itself, so the length is a plain len() read.
                        final narrowed = narrowedSubject(subj);
                        if (narrowed != null) {
                            optionNarrowingHitCount++;
                            return RustConversions.truncate(narrowed + ".len()", "u32");
                        }
                        return "(" + expr(subj) + ").as_ref().map_or(0, |v| v.len())";
                    }
                    if (isStringBuf(subj)) {
                        return RustConversions.truncate(expr(subj) + ".len()", "u32");
                    }
                    // Resident modules keep the signed Int domain: their
                    // lengths join index arithmetic, so the read narrows
                    // here the way UStringPlatform end inlines.
                    if (RuntimeResidents.isResident(imports.selfModule)) {
                        return RustConversions.narrowI32("(" + expr(subj) + ").len()");
                    }
                    if (isString(subj)) {
                        state.shimsUsed.set("std.UStringRT", true);
                        imports.require("crate::runtime::u_string");
                        return "u_string::count(&(" + expr(subj) + "))";
                    }
                    if (i32ComparisonTarget)
                        return "(" + RustConversions.narrowI32("(" + expr(subj) + ").len()") + ")";
                    final receiver = expr(subj);
                    final receiverText = StringTools.startsWith(receiver, "&*") ? "(" + receiver + ")" : receiver;
                    return RustConversions.truncate(receiverText + ".len()", "u32");
                }
                final snake = RustImports.toSnakeCase(name);
                final subjText = expr(subj);
                // A null guard narrows the complete field path. For example,
                // `glyph.bounds != null` registers the whole `glyph.bounds`
                // path as the guarded subject. When that same field is read
                // inside the guard, the read resolves to the match binding
                // of the inner value directly.
                // Covers the full-path nullable field read family.
                final narrowedFull = narrowedText(subjText + "." + snake);
                if (narrowedFull != null) {
                    optionNarrowingHitCount++;
                    final inner = getNullInnerType(cf.get().type);
                    return isTypeCopy(inner) ? "*" + narrowedFull : "(*" + narrowedFull + ").clone()";
                }
                // A null guard narrows the complete field path. For example,
                // `glyph.bounds` is narrowed as one access path.
                // When the complete access is the narrowed value, this read
                // is the match binding. The binding is a reference, so clone
                // the non-Copy referent.
                final narrowed = narrowedSubject(subj);
                final narrowedReceiver = narrowed == null ? narrowedReceiverSubject(subj) : null;
                if (narrowed != null || narrowedReceiver != null)
                    optionNarrowingHitCount++;
                // A proven guard subject is Some at this read: the forcing
                // read opens the guarded local directly through the borrow,
                // with no match binding in the path.
                // Covers the proven-subject direct read family.
                final proven = narrowed == null ? provenNonNullLocalSubject(subj) : null;
                // A preceding fill guard guarantees the local holds Some: the
                // forcing read reuses the fill as the get_or_insert_with
                // closure body. The closure runs only when the guard did not
                // fill, which never happens after the guard.
                final filled = narrowed == null && proven == null && isNullType(subj.t) ? filledSubjectOf(subj) : null;
                final subjStr = if (narrowed != null) narrowed else if (narrowedReceiver != null) narrowedReceiver else if (proven != null) proven else if (filled != null) subjText
                    + ".get_or_insert_with(|| " + filled + ")" else if (fieldReceiverCarriesFallibleWrapper(subj)
                    // A bare-table reader holds the bare value: the
                    // fallible-wrapper forcing must not fire on it.
                    // (BuilderValueNullability)
                    && !(switch (stripWrap(subj).expr) {
                        case TLocal(v): nullableCollapsedLocals.exists(v.id);
                        case _: false;
                    })) subjText
                    + ".as_ref().unwrap()" else subjText;
#if boring_fold_debug
                if (subjStr.indexOf(".as_ref().unwrap()") >= 0 && subjStr.indexOf("inline_object") >= 0)
                    Context.warning("FLD2 forced-as_ref src=" + (narrowed != null ? "narrowed" : proven != null ? "proven" : filled != null ? "filled" : fieldReceiverCarriesFallibleWrapper(subj) ? "fallible" : "plain") + " [" + subjStr.substr(0, subjStr.length > 70 ? 70 : subjStr.length) + "]", Context.currentPos());
#end
                final access = subjStr + "." + snake;
                if (name != "length" && isRecursiveField(subj, name)) {
                    // A cursor-local receiver re-binds the recursive field
                    // value: the as_ref borrow maps to an owned clone so the
                    // assignment target keeps its Option<EdgeState> shape.
                    // (CursorPattern)
                    final cursorReceiver = switch (stripWrap(subj).expr) {
                        case TLocal(v): cursorLocals.exists(v.id);
                        case _: false;
                    };
                    if (cursorReceiver)
                        return "(" + access + ").as_ref().map(|b| (**b).clone())";
                    return "(" + access + ").as_ref()";
                }
                if (name != "length" && isConstructedStaticRead(subj) && StaticFieldHelper.isStringType(cf.get().type))
                    return "(" + access + ").to_string()";
                if (name != "length" && isConstructedStaticRead(subj) && !isTypeCopy(cf.get().type))
                    return "(" + access + ").clone()";
                if (name != "length" && isNullType(cf.get().type)) {
                    // `Std.string` and string comparisons observe nullable values;
                    // preserve Option. Do not treat it as Display. A non-Copy
                    // inner value behind self or a borrowed subject still
                    // clones so the read produces an owned Option; the non-cloned form does not
                    // perform a move out of a reference. A method receiver keeps its
                    // borrow so mutations reach the original storage.
                    if (!isTypeCopy(getNullInnerType(cf.get().type)) && !renderingMethodReceiver && switch (subj.expr) {
                        case TConst(TThis): true;
                        case _: isBorrowedExpression(subj) || StringTools.contains(subjStr, ".as_ref().unwrap()");
                    }) {
                        return "(" + access + ").clone()";
                    }
                    return access;
                }
                if (name != "length" && (isStringType(cf.get().type) || isRecordValueType(cf.get().type))) {
                    return isStringType(cf.get().type) ? "(" + access + ").to_string()" : "(" + access + ").clone()";
                }
                if (name != "length" && !renderingMethodReceiver && !isTypeCopy(cf.get().type)
                    && switch (subj.expr) {
                        case TConst(TThis): true;
                        case _: false;
                    }) {
                    return "(" + access + ").clone()";
                }
                // A field read through a borrowed subject (parameter, loop
                // variable, or chained reference) yields a reference to the
                // field. Non-Copy fields must clone at the read site so the
                // value slots that consume them receive an owned copy.
                // Covers the borrowed-field-read family (E0507).
                if (name != "length" && !renderingMethodReceiver && !isTypeCopy(cf.get().type)
                    && (isBorrowedExpression(subj) || StringTools.contains(subjStr, ".as_ref().unwrap()"))) {
                    return "(" + access + ").clone()";
                }
                return access;
            case FDynamic(name):
                if ((name == "length" || name == "get_length") && isStringBuf(subj)) {
                    return RustConversions.truncate(expr(subj) + ".len()", "u32");
                }
                return fail(subj, "dynamic field access has no lowering");
            case FClosure(_):
                return fail(subj, "closure has no lowering");
        }
    }

    function receiverText(subj:TypedExpr, cf:Null<Ref<ClassField>>):String {
        final previous = renderingMethodReceiver;
        renderingMethodReceiver = cf != null && RustDecl.methodWritesReceiver(cf.get());
        final text = expr(subj);
        renderingMethodReceiver = previous;
        return text;
    }

    function staticFieldOf(cls:ClassType, name:String):Null<ClassField> {
        for (field in cls.statics.get()) {
            if (field.name == name) {
                return field;
            }
        }
        return null;
    }

    function isLazyStaticField(cls:ClassType, name:String):Bool {
        final field = staticFieldOf(cls, name);
        return field != null && RustDecl.usesLazyLockStatic(cls, field, state);
    }

    /**
        The deref-and-clone read of a LazyLock static, or null when the
        field is not emitted as a LazyLock. Mirrors the field() static-read
        branch so coalescing defaults (unwrap_or_else closures) reference
        the referent, never the LazyLock itself.
    **/
    function lazyStaticRead(cls:ClassType, name:String):Null<String> {
        final field = staticFieldOf(cls, name);
        if (field == null)
            return null;
        if (!RustDecl.usesLazyLockStatic(cls, field, state))
            return null;
        return "(*" + staticItemPath(cls, name) + ").clone()";
    }

    function isLazyArrayStaticField(field:ClassField):Bool {
        final init = StaticFieldHelper.initializer(field);
        return field.isFinal && StaticFieldHelper.isNonEmptyArrayLiteral(init) && !StaticFieldHelper.isIntLiteralArray(init);
    }

    function isDirectArrayStaticField(field:ClassField):Bool {
        final init = StaticFieldHelper.initializer(field);
        return field.isFinal && StaticFieldHelper.isNonEmptyArrayLiteral(init) && StaticFieldHelper.isIntLiteralArray(init);
    }

    function isLazyArrayReceiver(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TField(_, FStatic(c, cf)): isLazyArrayStaticField(cf.get());
            case _: false;
        };
    }

    function isDirectArrayStaticRead(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TField(_, FStatic(_, cf)): isDirectArrayStaticField(cf.get());
            case _: false;
        };
    }

    function isGuardStaticField(cls:ClassType, name:String):Bool {
        final field = staticFieldOf(cls, name);
        return field != null
            && !field.kind.match(FMethod(_))
            && ValueTypeSupport.markedAbstractOfClass(cls) == null
            && StaticFieldHelper.initializer(field) != null
            && !StaticFieldHelper.isConstValue(field)
            && !DataTableHelper.isDataTableField(field)
            && !isDirectArrayStaticField(field)
            && !isLazyArrayStaticField(field)
            && !RustDecl.usesLazyLockStatic(cls, field, state)
            && (!StaticFieldHelper.isConstruction(field.expr()) || StaticFieldHelper.isSelfConstruction(field, cls));
    }

    function staticItemPath(cls:ClassType, name:String):String {
        final itemName = RustImports.toScreamingSnakeCase(cls.name + "_" + name);
        return cls.module == imports.selfModule ? itemName : "crate::" + RustImports.moduleToRustPath(cls.module) + "::" + itemName;
    }

    function staticGuard(cls:ClassType, name:String):String {
        final path = staticItemPath(cls, name);
        // A non-Send static (trait object, Rc-backed function value) is
        // emitted as a thread-local RefCell, which borrows the inner value
        // without acquiring a lock. Covers the RefCell static guard family.
        final field = staticFieldOf(cls, name);
        if (field != null && RustDecl.isNonSendStaticType(types.of(field.type)))
            return path + ".with(|c| c.borrow())";
        return path + ".lock().unwrap_or_else(|e| e.into_inner())";
    }

    /** The guard read cloned to an owned value. The RefCell family clones
        inside the with-closure: a clone applied outside would clone the
        returned Ref guard and tie it to the thread-local's lifetime.
        (RefCellStaticGuardScope) */
    function staticGuardClone(cls:ClassType, name:String):String {
        final path = staticItemPath(cls, name);
        final field = staticFieldOf(cls, name);
        if (field != null && RustDecl.isNonSendStaticType(types.of(field.type)))
            return path + ".with(|c| c.borrow().clone())";
        return staticGuard(cls, name) + ".clone()";
    }

    /** The item path of a guard static whose guard is a RefCell borrow, or
        null when the expression is not one. The assignment through such a
        guard must happen inside the with-closure.
        (RefCellStaticGuardScope) */
    function refCellGuardStaticPath(e:TypedExpr):Null<String> {
        return switch (stripWrap(e).expr) {
            case TField(_, FStatic(c, cf)):
                final field = staticFieldOf(c.get(), cf.get().name);
                field != null && isGuardStaticField(c.get(), cf.get().name)
                    && RustDecl.isNonSendStaticType(types.of(field.type))
                    ? staticItemPath(c.get(), cf.get().name) : null;
            case _: null;
        };
    }

    function staticGuardOf(e:TypedExpr):Null<String> {
        return switch (stripWrap(e).expr) {
            case TField(_, FStatic(c, cf)) if (isGuardStaticField(c.get(), cf.get().name)):
                staticGuard(c.get(), cf.get().name);
            case _: null;
        };
    }

    function staticIndex(e:TypedExpr):String {
        return switch (stripWrap(e).expr) {
            case TConst(TInt(value)): Std.string(value) + "usize";
            case _:
                "match usize::try_from(" + expr(e) + ") { Ok(value) => value, Err(_) => 0usize }";
        };
    }

    function rustU32Length(length:String):String {
        return "match u32::try_from(" + length + ") { Ok(value) => value, Err(_) => u32::MAX }";
    }

    function staticAssignmentTarget(e:TypedExpr):Null<String> {
        return switch (stripWrap(e).expr) {
            case TField(_, FStatic(c, cf)) if (isGuardStaticField(c.get(), cf.get().name)):
                "*" + staticGuardMutable(c.get(), cf.get().name);
            case _: null;
        };
    }

    /** The mutable guard access for a static: borrow_mut for a RefCell
        (non-Send) static, lock for a Mutex static. */
    function staticGuardMutable(cls:ClassType, name:String):String {
        final path = staticItemPath(cls, name);
        final field = staticFieldOf(cls, name);
        if (field != null && RustDecl.isNonSendStaticType(types.of(field.type)))
            return path + ".with(|c| c.borrow_mut())";
        return path + ".lock().unwrap_or_else(|e| e.into_inner())";
    }

    /** True when the expression reads any guard-static field anywhere. */
    function rhsMentionsGuardStatic(e:TypedExpr):Bool {
        var found = false;
        function walk(node:TypedExpr) {
            if (found)
                return;
            switch (node.expr) {
                case TField(_, FStatic(c, cf)) if (isGuardStaticField(c.get(), cf.get().name)):
                    found = true;
                    return;
                case _:
            }
            haxe.macro.TypedExprTools.iter(node, walk);
        }
        walk(e);
        return found;
    }

    function isConstructedStaticRead(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TField(_,
                FStatic(c, cf)) if (StaticFieldHelper.isConstruction(cf.get().expr())
                    && !StaticFieldHelper.isSelfConstruction(cf.get(), c.get())): true;
            case _: false;
        };
    }

    function staticOwnedValue(e:TypedExpr):String {
        final rendered = expr(e);
        if (StaticFieldHelper.isConstruction(e))
            return rendered;
        if (StaticFieldHelper.isStringType(e.t)) {
            if (rendered.indexOf("&*") >= 0)
                return rendered + ".to_string()";
            return StringTools.endsWith(rendered, ".to_string()")
                || StringTools.endsWith(rendered, ".clone()") ? rendered : rendered + ".to_string()";
        }
        if (!isTypeCopy(e.t) && !StringTools.endsWith(rendered, ".clone()") && !StringTools.endsWith(rendered, ".to_vec()")) {
            return rendered + ".clone()";
        }
        return rendered;
    }

    function staticContainerArg(e:TypedExpr):String {
        final rendered = expr(e);
        if (StaticFieldHelper.isConstruction(e))
            return rendered;
        if (StaticFieldHelper.isArrayType(e.t))
            return rendered + ".to_vec()";
        if (StaticFieldHelper.isStringType(e.t) && !StringTools.endsWith(rendered, ".clone()")) {
            return rendered + ".to_string()";
        }
        // A nullable value pushed into a non-null static container unwraps
        // the Option; the null literal stays bare.
        if (isNullType(e.t) && !isTNull(e)) {
            final narrowed = narrowedSubject(e);
            if (narrowed != null)
                return isTypeCopy(getNullInnerType(e.t)) ? "*" + narrowed : "(" + narrowed + ").clone()";
            // A pushed local that is read later keeps its value after the
            // push in Haxe semantics: clone before the unwrapping move.
            // (PushedThenRead)
            final readAfterPush = switch (stripWrap(e).expr) {
                case TLocal(v): !isTypeCopy(getNullInnerType(e.t)) && pushedThenRead.exists(v.id);
                case _: false;
            };
            return readAfterPush ? rendered + ".clone().unwrap()" : rendered + ".unwrap()";
        }
        return rendered;
    }

    static function isNodeFileSystemOperation(name:String):Bool {
        return name == "mkdirSync" || name == "writeFileSync";
    }

    function isFunctionType(t:Null<Type>):Bool {
        return PolicyQueries.isFunctionType(t);
    }

    function staticFunctionName(cls:ClassType, name:String):String {
        return RustImports.toScreamingSnakeCase(cls.name + "_" + name);
    }

    function staticMethodName(cls:ClassType, name:String):String {
        final runtimeClassName = cls.name == "UStringRT" ? "UString" : cls.name;
        final qualifiedRuntimeClass = runtimeClassName == "TestCore" || runtimeClassName == "SortedTable" || runtimeClassName == "Graphemes"
            || runtimeClassName == "StringTools" || runtimeClassName == "UString";
        return qualifiedRuntimeClass ? RustImports.toSnakeCase(runtimeClassName + "_" + name) : RustImports.toSnakeCase(name);
    }

    /**
        Whether a marked static field emits as a free function and so
        carries its plain snake name.
    **/
    function markedFieldUsesFreeName(cls:ClassType, field:ClassField):Bool {
        switch (field.type) {
            case TFun(args, _) if (args.length > 0):
                return RustDecl.usesFreeFunctionForm(cls.module, field, args[0].t);
            case _:
        }
        return StaticFunctionMarkers.isTopLevel(field);
    }

    /** Constructed value-type statics are emitted as associated accessors. */
    function valueTypeStaticIsConst(field:ClassField):Bool {
        return StaticFieldHelper.isConstValue(field) && !StaticFieldHelper.isConstruction(field.expr());
    }

    function staticRef(cls:ClassType, name:String):String {
        final staticField = findStaticField(cls, name);
        final staticName = RustDecl.usesUnqualifiedCodecStaticName(cls) ? RustImports.toSnakeCase(name) : staticField != null
            && staticField.isFinal ? RustImports.toScreamingSnakeCase(RustImports.emittedTypeName(cls.name) + "_" + name) : RustImports.toSnakeCase(RustImports.emittedTypeName(cls.name) + "_" + name);
        final valueType = ValueTypeSupport.markedAbstractOfClass(cls);
        if (valueType != null) {
            imports.requireType(valueType.module, valueType.name);
            final field = findStaticField(cls, name);
            final isConst = field != null && valueTypeStaticIsConst(field);
            final item = valueType.name + "::" + (isConst ? RustImports.toScreamingSnakeCase(name) : RustImports.toSnakeCase(name));
            return isConst ? item : item + "()";
        }
        final markedField = findStaticField(cls, name);
        if (markedField != null && StaticFunctionMarkers.isMarked(markedField)) {
            final nativeName = markedFieldUsesFreeName(cls, markedField) ? RustImports.toSnakeCase(name) : RustImports.toSnakeCase(cls.name + "_" + name);
            if (markedField.isPublic) {
                imports.requireType(cls.module, nativeName);
            }
            return nativeName;
        }
        // Lazy static value reference policy: static fields emitted as
        // LazyLock must expose their owned referent at every value-expression
        // boundary, including paths that bypass field() (for example static
        // arguments and return values). The helper names this policy and
        // excludes self-construction reads, which must retain the initializer
        // cycle-safe path.
        final lazyRead = lazyStaticRead(cls, name);
        if (lazyRead != null)
            return lazyRead;
        // Key the shim/standard routing on the module; the name-derived
        // path is not used: an @:native extern (std.Functional -> "__functional_shim")
        // overrides cls.name while cls.module keeps the declared module, so
        // a name-derived path would miss the std.Functional arm and fall to
        // the generic shim import under the native name.
        switch (cls.module) {
            case "String":
                return "String::" + RustImports.toSnakeCase(name);
            case "Math":
                // The f32 configuration renders the whole Math family from f32, the
                // binary32 equivalent of every static (feature spec 23).
                final real = FloatPrecision.isF32() ? "f32" : "f64";
                if (name == "NaN")
                    return real + "::NAN";
                if (name == "POSITIVE_INFINITY")
                    return real + "::INFINITY";
                if (name == "NEGATIVE_INFINITY")
                    return real + "::NEG_INFINITY";
                return real + "::" + RustImports.toSnakeCase(name);
            case _ if (RustTestBinding.isTestExtern(cls)):
                state.shimsUsed.set(RuntimeResidents.externsOf("runtime.TestCore")[0], true);
                if (name == "run") {
                    imports.require("crate::runtime::test as testlib");
                    return "testlib::run";
                }
                imports.require("crate::runtime::test_core");
                return "test_core::TestCore::" + staticMethodName(cls, name);
            case "std.Functional":
                imports.requireType("std.Functional", "Functional");
                return "Functional::" + staticMethodName(cls, name);
            case "std.UStringRT":
                return uStringRef(cls, name);
            case "std.Graphemes":
                // The extern fronts the resident runtime module
                // runtime.Graphemes, compiled into graphemes.rs; the
                // reference names the struct and calls its methods.
                state.shimsUsed.set("std.Graphemes", true);
                if (name == "boundaries" && !RuntimeResidents.isResident(imports.selfModule)) {
                    // The boundary vector crosses whole between the two
                    // Int domains; the adapter in graphemes.rs casts each
                    // element once, because Array results have no
                    // call-site cast machinery (RuntimeResidents).
                    imports.require("crate::runtime::graphemes");
                    return "graphemes::boundaries";
                }
                imports.requireType("runtime.Graphemes", "Graphemes");
                return "Graphemes::" + staticMethodName(cls, name);
            case "StringTools":
                // StringTools statics without a native Rust/String inline
                // lowering (lpad, rpad, ltrim, rtrim, replace, ...) route
                // into the runtime module, mirroring the Kotlin target.
                // The inline-lowered ones (hex, trim, startsWith,
                // endsWith) are handled before staticRef. A resident
                // caller addresses the compiled class directly; a business
                // caller goes through the adapter module (RuntimeResidents).
                state.shimsUsed.set("StringTools", true);
                if (RuntimeResidents.isResident(imports.selfModule)) {
                    imports.requireType("runtime.StringTools", "StringTools");
                    return "StringTools::" + staticMethodName(cls, name);
                }
                imports.require("crate::runtime::string_tools");
                return "string_tools::StringTools::" + RustImports.toSnakeCase(cls.name + "_" + name);
            case _:
                if (RustTestBinding.isTestExtern(cls)) {
                    state.shimsUsed.set(RuntimeResidents.externsOf("runtime.TestCore")[0], true);
                    if (name == "run") {
                        imports.require("crate::runtime::test as testlib");
                        return "testlib::run";
                    }
                    imports.require("crate::runtime::test_core");
                    return "test_core::TestCore::" + staticMethodName(cls, name);
                }
                if (cls.module == "std.UStringRT") {
                    return uStringRef(cls, name);
                }
                if (RustImports.isShimModule(cls.module)) {
                    final structName = RustImports.emittedTypeName(cls.name);
                    imports.requireType(cls.module, structName);
                    return structName + "::" + RustImports.toSnakeCase(name);
                }
                if (cls.module == "std.Graphemes") {
                    state.shimsUsed.set("std.Graphemes", true);
                    if (name == "boundaries" && !RuntimeResidents.isResident(imports.selfModule)) {
                        // Same routing as the path arm above: the boundary
                        // vector crosses whole, so the business caller
                        // reaches the element-casting adapter.
                        imports.require("crate::runtime::graphemes");
                        return "graphemes::boundaries";
                    }
                    imports.requireType("runtime.Graphemes", "Graphemes");
                    return "Graphemes::" + staticMethodName(cls, name);
                }
                for (field in cls.statics.get()) {
                    if (field.name == name && field.kind.match(FVar(_, _)) && isFunctionType(field.type)) {
                        final targetName = staticFunctionName(cls, name);
                        if (cls.module != imports.selfModule) {
                            imports.requireType(cls.module, targetName);
                        }
                        return targetName;
                    }
                }
                for (field in cls.statics.get()) {
                    if (field.name == name && DataTableHelper.isDataTableField(field)) {
                        if (cls.module == imports.selfModule) {
                            return RustImports.toScreamingSnakeCase(name);
                        }
                    }
                }
                if (markedField != null && isDirectArrayStaticField(markedField)) {
                    return staticItemPath(cls, name);
                }
                // The typer renders an @:native extern class under its
                // native name (console, process) even when its
                // declaration name differs; the emitted shim keeps the
                // declaration's module name (Console, Process). A
                // Pascal-case name is already the declaration name and
                // stays untouched.
                final first = cls.name.length > 0 ? cls.name.charAt(0) : "?";
                final nativeLower = first >= "a" && first <= "z";
                final structName = nativeLower ? cls.module.substr(cls.module.lastIndexOf(".") + 1) : RustImports.emittedTypeName(cls.name);
                if (cls.module != "" && StringTools.endsWith(cls.name, "_Impl_")) {
                    // A sub-type abstract's non-inline static (for example
                    // `FontId::of`) lowers to the synthetic implementation's
                    // `_Impl_`. The call site names that symbol, so
                    // compileClassImpl must not drop the referenced `_Impl_`
                    // even though ordinary synthetic impls never emit.
                    state.referencedImpls.set(cls.module, true);
                }
                imports.requireType(cls.module, structName);
                return structName + "::" + staticName;
        }
    }

    function findStaticField(cls:ClassType, name:String):Null<ClassField> {
        return PolicyQueries.findStaticField(cls, name);
    }

    /**
        Reference to the UString runtime through the std.UStringRT extern.
        A resident caller addresses the compiled class directly and shares
        its i32 convention; a business caller goes through the u32 adapter
        free functions emitted beside the class, because Null and Array
        results have no call-site cast machinery (RuntimeResidents).
     */
    function uStringRef(cls:ClassType, name:String):String {
        state.shimsUsed.set("std.UStringRT", true);
        if (RuntimeResidents.isResident(imports.selfModule)) {
            imports.requireType("runtime.UString", "UString");
            return "UString::" + RustImports.toSnakeCase("UString_" + name);
        }
        imports.require("crate::runtime::u_string");
        return "u_string::" + RustImports.toSnakeCase(name);
    }

    function typeExpr(t:ModuleType):String {
        switch (t) {
            case TClassDecl(c):
                final cls = c.get();
                if (cls.pack.length == 0 && (cls.name == "String" || cls.name == "Math")) {
                    return cls.name;
                }
                if (RustTestBinding.isTestExtern(cls)) {
                    state.shimsUsed.set(RuntimeResidents.externsOf("runtime.TestCore")[0], true);
                    imports.require("crate::runtime::test as testlib");
                    return "testlib";
                }
                imports.requireType(cls.module, RustImports.emittedTypeName(cls.name));
                return RustImports.emittedTypeName(cls.name);
            case TEnumDecl(e):
                final en = e.get();
                final owner = state.payloadEnumOwners.get(en.module);
                final name = owner != null ? owner : en.name;
                imports.requireType(en.module, name);
                return name;
            case _:
                Context.error("type expression has no value lowering", Context.currentPos());
                return null;
        }
    }

    function stdString(arg:TypedExpr, inConcat:Bool):String {
        final fromSource = PolicyQueries.inSourceScope(arg.pos);
        final nullable = PolicyQueries.isNullableType(arg.t);
        if (fromSource && nullable) {
            Context.error("Std.string does not accept Null<T> operands; compare against null first", arg.pos);
        }
        // A synthesized nullable operand narrows structurally inside
        // stdStringType (the Null match form); an assertion here would
        // strip the Option before that match and break its typing.
        return stdStringType(arg.t, expr(arg), inConcat, arg);
    }

    function stdIsOfType(args:Array<TypedExpr>):String {
        final target = TypeCheckHelper.classOfTypeExpr(args[1]);
        if (target == null) {
            Context.error("Std.isOfType requires a class type expression", args[1].pos);
            return "false";
        }
        final known = TypeCheckHelper.knownIsOfType(args[0], target);
        if (known != null) {
            return known ? "true" : "false";
        }
        return expr(args[0]) + ".__haxe_type_name() == \"" + target.module + "." + target.name + "\"";
    }

    function stdStringType(t:Type, value:String, inConcat:Bool, origin:TypedExpr, depth:Int = 0):String {
        // Context.follow may expose the wrapped value type of Null<T> before
        // the category classifier runs. Preserve the Option match whenever
        // the wrapped type is a marked value wrapper.
        switch (t) {
            case TAbstract(a, [inner]) if (a.get().name == "Null" && ValueTypeSupport.markedAbstractOfType(inner) != null):
                return "match "
                    + value
                    + " { Some(ref v) => "
                    + stdStringType(inner, "v", false, origin, depth + 1)
                    + ", None => \"null\".to_string() }";
            case _:
        }
        // Context.follow unwraps Null<T> into T, so the switch below never
        // sees the wrapper; a nullable operand takes the match form here,
        // before the follow.
        switch (t) {
            case TAbstract(a, [inner]) if (a.get().name == "Null"):
                // A narrowed subject or a null-coalescing-collapsed local is
                // already the scalar binding; render the inner string
                // directly, skipping the Option match form. A null-guarded
                // ternary whose arms are both non-null also renders a plain
                // String (guardedMatchExpression renders it as a plain value), so the
                // Option match must not re-apply.
                if (narrowedSubject(origin) != null || isNullableCollapsedLocal(origin)
                    || isNonNullRenderedConditional(origin) || isNullGuardedTernary(origin))
                    return stdStringType(inner, value, inConcat, origin, depth + 1);
                // A Copy inner binds by value so float/int formatting
                // receives the owned scalar; owned inners bind by
                // reference.
                final binding = isTypeCopy(inner) ? "v" : "ref v";
                return "match "
                    + value
                    + " { Some("
                    + binding
                    + ") => "
                    + stdStringType(inner, "v", false, origin, depth + 1)
                    + ", None => \"null\".to_string() }";
            case _:
        }
        return switch (PolicyQueries.stdStringCategory(t)) {
            case IsString:
                inConcat ? value : value + ".to_string()";
            case IsArray(element):
                imports.require("std::fmt::Write");
                final index = depth == 0 ? "i" : "i" + depth;
                final item = stdStringType(element, value + "[" + index + "]", true, origin, depth + 1);
                '{\n        let mut out = String::new();\n        out.push(\'[\');\n        let n = ${value}.len();\n        let mut ${index} = 0usize;\n        while ${index} < n {\n            if ${index} > 0 { out.push_str(", "); }\n            let _ = write!(out, "{}", ${item});\n            ${index} += 1;\n        }\n        out.push(\']\');\n        out\n    }';
            case IsSortedSet(element):
                imports.require("std::fmt::Write");
                final index = depth == 0 ? "i" : "i" + depth;
                final item = stdStringType(element, value + ".at(" + index + ")", true, origin, depth + 1);
                '{\n        let mut out = String::new();\n        out.push(\'[\');\n        let n = ${value}.size();\n        let mut ${index} = 0;\n        while ${index} < n {\n            if ${index} > 0 { out.push_str(", "); }\n            let _ = write!(out, "{}", ${item});\n            ${index} += 1;\n        }\n        out.push(\']\');\n        out\n    }';
            case IsSortedMap(key, val):
                imports.require("std::fmt::Write");
                final index = depth == 0 ? "i" : "i" + depth;
                final itemKey = stdStringType(key, value + ".key_at(" + index + ")", true, origin, depth + 1);
                final itemVal = stdStringType(val, value + ".value_at(" + index + ")", true, origin, depth + 1);
                '{\n        let mut out = String::new();\n        out.push(\'{\');\n        let n = ${value}.size();\n        let mut ${index} = 0;\n        while ${index} < n {\n            if ${index} > 0 { out.push_str(", "); }\n            let _ = write!(out, "{}={}", ${itemKey}, ${itemVal});\n            ${index} += 1;\n        }\n        out.push(\'}\');\n        out\n    }';
            case IsTypeParameter:
                state.memberPrintsTypeParam = true;
                "format!(\"{:?}\", " + value + ")";
            case IsRecordLike: value + ".to_string()";
            case IsInstanceToString: value + ".to_string()";
            case IsMarkedAbstract(abs):
                value + ".0.to_string()";
            case IsNull:
                "match " + value + " { Some(v) => v.to_string(), None => \"null\".to_string() }";
            case IsFloat:
                inConcat ? value : "crate::runtime::fp_helper::FPHelper::format_float" + (FloatPrecision.isF32() ? "_f32" : "") + "(" + value + ")";
            case IsInt | IsBool: inConcat ? value : "(" + value + ").to_string()";
            case IsReadOnlyArray(underlying):
                stdStringType(underlying, value, inConcat, origin, depth);
            case IsParameterlessEnum(en):
                EnumQueryExpander.requireNameRead(en);
                // A narrowed enum read renders as a deref of the match
                // binding (*__option); appending .name() binds the method
                // to the reference and the deref applies to the returned
                // &str. Parenthesize the deref so .name() reaches the
                // enum value (E0308 expected String, found str).
                (StringTools.startsWith(value, "*") ? "(" + value + ")" : value) + ".name()" + (inConcat ? "" : ".to_string()");
            case IsCyclicEnum(en): cyclicEnumString(en, value, inConcat, origin);
            case IsPayloadEnum(_): value + ".to_string()";
            case IsUnsupported:
                Context.error("Std.string accepts scalars, enum values, records, and arrays of them only", origin.pos);
                null;
        };
    }

    function hasInstanceToString(cls:ClassType):Bool {
        return PolicyQueries.hasInstanceToString(cls);
    }

    function cyclicEnumString(en:EnumType, value:String, inConcat:Bool, origin:TypedExpr):String {
        final existing = enumStringNaming.existing(en);
        if (existing != null)
            return existing + "(&" + value + ")";
        final name = enumStringNaming.open(en, RustImports.toSnakeCase("stdString" + en.name));
        final body = payloadEnumString(en, "v", false, origin);
        enumStringNaming.close(en);
        return "{ fn " + name + "(v: &" + en.name + ") -> String { " + body + " } " + name + "(&" + value + ") }";
    }

    function payloadEnumString(en:EnumType, value:String, inConcat:Bool, origin:TypedExpr):String {
        final fields = [for (ef in en.constructs) ef];
        fields.sort((a, b) -> Reflect.compare(a.index, b.index));
        imports.require("std::fmt::Write");
        final arms:Array<String> = [];
        for (ef in fields) {
            final args = switch (ef.type) {
                case TFun(a, _): a;
                case _: [];
            };
            final pattern = en.name + "::" + RustImports.toUpperCamelCase(ef.name);
            if (args.length == 0)
                arms.push(pattern + " => out.push_str(\"" + ef.name + "\")");
            else {
                var formatText = ef.name + "(";
                for (i in 0...args.length)
                    formatText += (i == 0 ? "" : ", ") + args[i].name + "={}";
                formatText += ")";
                arms.push(pattern
                    + " { "
                    + [for (a in args) a.name].join(", ")
                        + " } => { let _ = write!(out, \""
                        + formatText
                        + "\", "
                        + [for (a in args) stdStringType(a.t, a.name, true, origin)].join(", ") + "); }");
            }
        }
        return "{ let mut out = String::new(); match " + value + " { " + arms.join(", ") + " }; out }";
    }

    function isParameterlessEnum(en:EnumType):Bool {
        return PolicyQueries.isParameterlessEnum(en);
    }

    function stdStringArg(e:TypedExpr):Null<TypedExpr> {
        return PolicyQueries.stdStringArg(e);
    }

    function stringToolsHex(args:Array<TypedExpr>):String {
        final validated = PolicyQueries.stringToolsHexArgs(args);
        final value = validated.value;
        final digits = validated.digits;
        final valueText = expr(value);
        if (digits == null) {
            return "format!(\"{:X}\", " + valueText + ")";
        }
        return "format!(\"{:0w$X}\", " + valueText + ", w = usize::try_from(" + expr(digits) + ").unwrap_or_default())";
    }

    function isNegativeIntLiteral(e:TypedExpr):Bool {
        return ExpressionPredicates.isNegativeIntLiteral(e);
    }

    /** Routes calls on a marked abstract implementation to Rust members. */
    function valueTypeCall(fn:TypedExpr, args:Array<TypedExpr>):Null<String> {
        switch (stripWrap(fn).expr) {
            case TField(_, FStatic(c, cf)):
                final abs = ValueTypeSupport.markedAbstractOfClass(c.get());
                if (abs == null)
                    return null;
                final field = cf.get();
                if (field.name == "_new") {
                    imports.requireType(abs.module, abs.name);
                    final rendered = ctorCallArgs(c.get(), args);
                    if (ValueTypeSupport.constructorThrows(abs)) {
                        final call = abs.name + "::new(" + rendered + ")";
                        return call + (isFallible ? "?" : ".unwrap()");
                    }
                    return abs.name + "(" + rendered + ")";
                }
                if (field.name == "toString" && args.length > 0) {
                    // A null guard narrows the complete field path (for
                    // example `self.first_line_indent`), so the toString
                    // receiver reads the match binding, never the Option.
                    // The general member-call path applies this narrowing;
                    // the value-type toString intercepts before it, so the
                    // same substitution is required here.
                    final receiver = args[0];
                    final narrowed = narrowedSubject(receiver);
                    if (narrowed != null)
                        optionNarrowingHitCount++;
                    final receiverText = narrowed != null ? narrowed : expr(receiver);
                    return receiverText + ".to_string()";
                }
                final op = ValueTypeSupport.operatorOf(abs, field);
                if (op != null) {
                    return switch (op) {
                        case Binary(_): args.length >= 2 ? expr(args[0]) + " " + opStrForValue(op) + " " + expr(args[1]) : abs.name;
                        case Unary(_): args.length > 0 ? "-" + expr(args[0]) : abs.name;
                    };
                }
                if (ValueTypeSupport.hasReceiver(field) && args.length > 0) {
                    return expr(args[0])
                        + "."
                        + RustImports.toSnakeCase(field.name)
                        + "("
                        + [for (i in 1...args.length) expr(args[i])].join(", ") + ")";
                }
                return abs.name + "::" + RustImports.toSnakeCase(field.name) + "(" + [for (a in args) expr(a)].join(", ") + ")";
            case TField(subj, FInstance(_, _, cf)) | TField(subj, FAnon(cf)):
                final abs = ValueTypeSupport.markedAbstractOfType(subj.t);
                if (abs == null)
                    return null;
                final name = cf.get().name;
                // A null guard narrows the complete field path (for example
                // `self.first_line_indent`), so a value-type member call on
                // that path must read the match binding, never the Option.
                // The general member-call path already applies this
                // narrowing; valueTypeCall intercepts toString before it, so
                // the same substitution is required here.
                final narrowed = narrowedSubject(subj);
                if (narrowed != null)
                    optionNarrowingHitCount++;
                final receiver = narrowed != null ? narrowed : expr(subj);
                return name == "toString" ? receiver + ".to_string()" : receiver
                    + "."
                    + RustImports.toSnakeCase(name)
                    + "("
                    + [for (a in args) expr(a)].join(", ") + ")";
            case _:
        }
        return null;
    }

    function opStrForValue(op:ValueTypeOperator):String {
        return switch (op) {
            case Binary(binary): opStr(binary);
            case Unary(_): "-";
        };
    }

    function call(fn:TypedExpr, args:Array<TypedExpr>):String {
        final int64CallText = int64Call(fn, args);
        if (int64CallText != null)
            return int64CallText;
        final wrapperCall = valueTypeCall(fn, args);
        if (wrapperCall != null)
            return wrapperCall;
        switch (fn.expr) {
            case TField(_, FStatic(c, cf)) if (c.get().module == "Std" && cf.get().name == "string" && args.length == 1):
                return stdString(args[0], false);
            case TField(_, FStatic(c, cf)) if (c.get().module == "Std" && cf.get().name == "isOfType" && args.length == 2):
                return stdIsOfType(args);
            case TField(subj, FInstance(_, _, cf)) if (cf.get().name == "get_message" && args.length == 0):
                final folded = foldedExceptionMessage(stripCast(subj), "get_message");
                if (folded != null) {
                    return folded;
                }
            case TField(subj, FStatic(c, cf)):
                final cls = c.get();
                final name = cf.get().name;
                final path = cls.pack.join(".") + "." + cls.name;
                final markedField = findStaticField(cls, name);
                if (markedField != null && StaticFunctionMarkers.isMarked(markedField)) {
                    final isOwnedExtension = StaticFunctionMarkers.isExtension(markedField)
                        && RustDecl.isCrateOwnedReceiver(cls.module, args[0].t);
                    final isStaticFallible = isFallibleCallee(c, cf, true);
                    final q = isFallible ? (isStaticFallible ? "?" : "") : (isStaticFallible ? ".unwrap()" : "");
                    if (isOwnedExtension) {
                        final receiver = expr(args[0]);
                        final receiverText = StringTools.startsWith(receiver, "*") ? "(" + receiver + ")" : receiver;
                        return receiverText
                            + "."
                            + RustImports.toSnakeCase(name)
                            + "("
                            + renderCallArgs(cf.get().type, args.slice(1), null, 1, mutableParamPositions(cf.get()), args[0].t)
                            + ")"
                            + q;
                    }
                    return staticRef(cls, name) + "(" + renderCallArgs(cf.get().type, args, null, 0, mutableParamPositions(cf.get())) + ")" + q;
                }
                if ((cls.name == "Functional" || cls.name == "__functional_shim" || path == "std.Functional" || cls.module == "std.Functional")
                    && name == "sortedBy") {
                    final receiver = args[0];
                    final lambda = args[1];
                    final func = unwrapLambda(lambda);
                    if (func != null && func.args.length == 1) {
                        final paramName = RustImports.toSnakeCase(func.args[0].v.name);
                        final keyExpr = expr(lambdaBody(func.expr));
                        return "{\n    let mut _sorted = " + expr(receiver) + ".to_vec();\n    _sorted.sort_by_key(|" + paramName + "| " + keyExpr
                            + ");\n    _sorted\n}";
                    }
                }
                // The Functional shims (sum_of_float, for_each, ...) are
                // generic over their callback; the Arc::new(move |o| ...)
                // closure cannot infer the parameter type through the generic
                // bound, so the lambda parameter is annotated from the
                // receiver's element type.
                if ((cls.name == "Functional" || cls.name == "__functional_shim" || path == "std.Functional" || cls.module == "std.Functional")
                    && args.length == 2) {
                    final receiver = args[0];
                    final lambda = args[1];
                    final func = unwrapLambda(lambda);
                    if (func != null && func.args.length == 1) {
                        final elemType = switch (Context.follow(receiver.t)) {
                            case TInst(c, [element]) if (c.get().name == "Array"): types.of(element, false);
                            case _: null;
                        };
                        if (elemType != null) {
                            final paramName = RustImports.toSnakeCase(func.args[0].v.name);
                            final bodyText = functionLiteral(func, lambda.t);
                            final typed = StringTools.replace(bodyText, "|" + paramName + "|", "|" + paramName + ": &" + elemType + "|");
                            return staticRef(cls, name) + "(&" + expr(receiver) + ", " + typed + ")";
                        }
                    }
                }
            case _:
        }
        final inlineMapCall = mapHasOwnPropertyCall(fn, args);
        if (inlineMapCall != null) {
            return inlineMapCall;
        }
        final renderedArgs = [for (a in args) expr(a)].join(", ");
        switch (fn.expr) {
            case TField(_, FStatic(c, cf)) if (c.get().module == "haxe.io.Bytes" && cf.get().name == "alloc" && args.length == 1):
                return "vec![0u8; " + castArg(args[0], "usize") + "]";
            case TField(_, FStatic(c, cf)) if (c.get().module == "haxe.io.Bytes" && cf.get().name == "ofString" && args.length == 1):
                return expr(args[0]) + ".as_bytes().to_vec()";
            case TField(_, FStatic(c, cf)) if (c.get().module == "haxe.io.Bytes" && cf.get().name == "concat" && args.length == 2):
                return "{ let mut v = " + expr(args[0]) + ".to_vec(); v.extend_from_slice(&" + expr(args[1]) + "); v }";
            case TField(_, FStatic(c, cf))
                if ((c.get().name == "NodeFileSystem" && isNodeFileSystemOperation(cf.get().name))
                    || (c.get().meta.has(":jsRequire") && isNodeFileSystemOperation(cf.get().name))):
                // The trace writer's file extern binds node:fs, which has
                // no rust face; both members lower to the resident file
                // edge, which carries the same create-parents and
                // utf-8 write behavior with the host failure mapping. The
                // resident edge reads &str, so each String argument borrows.
                state.shimsUsed.set("std.Fs", true);
                imports.requireType("std.Fs", "Fs");
                final fsName = cf.get().name;
                if (fsName == "mkdirSync" && args.length >= 1) {
                    return "Fs::make_dirs(" + stringViewArg(args[0]) + ")";
                }
                if (fsName == "writeFileSync" && args.length >= 2) {
                    return "Fs::write_text(" + stringViewArg(args[0]) + ", " + stringViewArg(args[1]) + ")";
                }
                Context.error("file extern has no lowering for member " + fsName, fn.pos);
                return "null";
            case TCast(inner, _):
                return call(inner, args);
            case TField(subj, FDynamic(name)) if ((name == "length" || name == "get_length") && isStringBuf(subj)):
                return RustConversions.truncate(expr(subj) + ".len()", "u32");
            case TField(subj, FInstance(c, _, cf)):
                final name = cf.get().name;
                final staticGuard = staticGuardOf(subj);
                if (staticGuard != null) {
                    if (name == "push" && args.length == 1) {
                        return staticGuard + ".push(" + staticContainerArg(args[0]) + ")";
                    }
                    if (name == "length" || name == "get_length") {
                        return rustU32Length(staticGuard + ".len()");
                    }
                }
                if (isString(subj)) {
                    if (name == "toLowerCase")
                        return expr(subj) + ".to_lowercase()";
                    if (name == "toUpperCase")
                        return expr(subj) + ".to_uppercase()";
                }
                final snake = RustImports.toSnakeCase(name);
                if (name == "valueAt" && args.length == 1 && (isSortedTable(subj) || isSortedBuilder(subj))) {
                    // The resident value_at takes an i32 index. An integer
                    // literal infers against the parameter directly; a
                    // u32-domain argument reinterprets its bits.
                    // (ResidentI32Comparison)
                    final argText = switch (stripWrap(args[0]).expr) {
                        case TConst(TInt(_)): expr(args[0]) + "i32";
                        case _: RustConversions.reinterpret(expr(args[0]), "i32");
                    };
                    return receiverText(subj, cf) + ".value_at(" + argText + ")";
                }
                if (isMapType(subj.t)) {
                    if (name == "exists" && args.length == 1)
                        return expr(subj) + ".contains_key(&" + rustMapKey(args[0]) + ")";
                    if (name == "get" && args.length == 1)
                        return expr(subj) + ".get(&" + rustMapKey(args[0]) + ").cloned()";
                    if (name == "set" && args.length == 2)
                        return expr(subj) + ".insert(" + rustMapKey(args[0]) + ", " + rustMapValue(args[1]) + ")";
                }
                if (isStringBuf(subj)) {
                    // stdlib/08: add and addChar lower only as statements,
                    // because the pairing check leaves through `return Err`.
                    if (name == "add") {
                        return fail(subj, "string buffer add has no expression lowering: keep the mutation a statement inside a fallible function (stdlib/08)");
                    }
                    if (name == "addChar") {
                        return fail(subj,
                            "string buffer addChar has no expression lowering: keep the mutation a statement inside a fallible function (stdlib/08)");
                    }
                    if (name == "toString") {
                        final fault = stringBufFaultEnum();
                        if (fault == null) {
                            return fail(subj, "string buffer checks require std.UStringException in the module set (stdlib/08)");
                        }
                        // The unit vector keeps the buffer well-formed up to
                        // a trailing lead, so from_utf16 fails exactly on
                        // that lead and the map_err names it. The `?` or
                        // `.unwrap()` rides the ordinary fallibility rules.
                        final q = isFallible ? "?" : ".unwrap()";
                        return "String::from_utf16(" + expr(subj) + ".as_slice()).map_err(|_| " + wrappedBufferFault(fault, fault + "::UnpairedSurrogate { unit: u32::from("
                            + expr(subj) + "[" + expr(subj) + ".len() - 1]) }") + ")" + q;
                    }
                    if (name == "get_length" || name == "length") {
                        return RustConversions.truncate(expr(subj) + ".len()", "u32");
                    }
                }
                if (name == "get" && isBytes(stripCast(subj))) {
                    // A Bytes element is u8; widening to the module's Haxe
                    // Int domain (u32 in business, i32 in resident) goes
                    // through From so the read carries no `as`.
                    final intDomain = RuntimeResidents.isResident(imports.selfModule) ? "i32" : "u32";
                    return intDomain + "::from(" + expr(subj) + "[" + castArg(args[0], "usize") + "])";
                }
                if (name == "set" && args.length == 2 && isBytes(stripCast(subj))) {
                    return expr(subj) + "[" + castArg(args[0], "usize") + "] = " + castArg(args[1], "u8");
                }
                if (name == "blit" && args.length == 4 && isBytes(stripCast(subj))) {
                    return expr(subj)
                        + "["
                        + castArg(args[0], "usize")
                        + ".."
                        + usizeIndex("(" + expr(args[0]) + " + " + expr(args[3]) + ")")
                        + "].copy_from_slice(&"
                        + expr(args[1])
                        + "["
                        + castArg(args[2], "usize")
                        + ".."
                        + usizeIndex("(" + expr(args[2]) + " + " + expr(args[3]) + ")")
                        + "])";
                }
                if (name == "fill" && args.length == 3 && isBytes(stripCast(subj))) {
                    return expr(subj)
                        + "["
                        + castArg(args[0], "usize")
                        + ".."
                        + usizeIndex("(" + expr(args[0]) + " + " + expr(args[1]) + ")")
                        + "].fill("
                        + castArg(args[2], "u8")
                        + ")";
                }
                if (name == "sub" && args.length == 2 && isBytes(stripCast(subj))) {
                    return expr(subj)
                        + "["
                        + castArg(args[0], "usize")
                        + ".."
                        + usizeIndex("(" + expr(args[0]) + " + " + expr(args[1]) + ")")
                        + "].to_vec()";
                }
                if (name == "getString" && args.length == 2 && isBytes(stripCast(subj))) {
                    return "String::from_utf8_lossy(&"
                        + expr(subj)
                        + "["
                        + castArg(args[0], "usize")
                        + ".."
                        + usizeIndex("(" + expr(args[0]) + " + " + expr(args[1]) + ")")
                        + "]).into_owned()";
                }
                if (name == "charAt" && isString(stripCast(subj))) {
                    state.shimsUsed.set("std.UStringRT", true);
                    imports.require("crate::runtime::u_string");
                    // The exclusive end is the index plus one in the same
                    // integer domain as the start. A bare `(index) + 1`
                    // rendered source is an untyped {integer} literal when
                    // index is one (E0689), so the end arrives as a typed
                    // wrapping add on the start's cast form instead.
                    return "u_string::substring(&" + expr(subj) + ", " + castSignedI32(args[0]) + ", i32::wrapping_add(" + castSignedI32(args[0]) + ", 1)"
                        + ")";
                }
                if ((name == "indexOf" || name == "index_of") && isString(stripCast(subj)) && args.length >= 1) {
                    // The find() needle must implement Pattern: a literal or
                    // a borrowed &str parameter already renders as a str view,
                    // while an owned String local borrows through as_str.
                    final needle = if (isStringType(args[0].t)) {
                        switch (stripWrap(args[0]).expr) {
                            case TConst(TString(_)): expr(args[0]);
                            case TLocal(v) if (isBorrowedParamLocal(v)): expr(args[0]);
                            case _: "(" + expr(args[0]) + ").as_str()";
                        };
                    } else {
                        expr(args[0]);
                    };
                    return "match ("
                        + expr(subj)
                        + ").find(&"
                        + needle
                        + ") { Some(v) => "
                        + RustConversions.narrowI32("v")
                        + ", None => -1 }";
                }
                if ((name == "charCodeAt" || name == "char_code_at") && isString(stripCast(subj))) {
                    state.shimsUsed.set("std.UStringRT", true);
                    imports.require("crate::runtime::u_string");
                    // The call site's own expression decides: a Null<Int>
                    // context keeps the Option and an Int context unwraps it.
                    var callRet:Null<Type> = null;
                    switch (Context.follow(fn.t)) {
                        case TFun(_, r): callRet = r;
                        case _:
                    }
                    final nullableResult = callRet != null && isNullType(callRet);
                    // A proven-non-null nullable String receiver holds the
                    // inner value; unwrap it before the at() borrow.
                    final receiver = if (isNullType(subj.t) && switch (stripWrap(subj).expr) {
                        case TLocal(v): provenNonNullVarIds.exists(v.id);
                        case _: false;
                    }) "(" + expr(subj) + ").as_ref().unwrap()" else expr(subj);
                    return nullableResult ? "u_string::at(&" + receiver + ", " + castShiftU32(args[0]) + ")" : "u_string::at(&"
                        + receiver
                        + ", "
                        + castShiftU32(args[0])
                        + ").unwrap_or(0)";
                }
                if (name == "split" && isString(stripCast(subj)) && args.length == 1) {
                    state.shimsUsed.set("std.UStringRT", true);
                    imports.require("crate::runtime::u_string");
                    return "u_string::split(&" + expr(subj) + ", &" + expr(args[0]) + ")";
                }
                if ((name == "lastIndexOf" || name == "last_index_of") && isString(stripCast(subj)) && args.length >= 1) {
                    // String method arguments render as owned String values;
                    // borrow the pattern for Rust's str Pattern implementation.
                    return "match (" + expr(subj) + ").rfind(&" + expr(args[0]) + ") { Some(v) => " + RustConversions.narrowI32("v") + ", None => -1 }";
                }
                if ((name == "startsWith" || name == "starts_with") && isString(stripCast(subj)) && args.length >= 1) {
                    // String method arguments render as owned String values;
                    // borrow the pattern for Rust's str Pattern implementation.
                    return "(" + expr(subj) + ").starts_with(&" + expr(args[0]) + ")";
                }
                if ((name == "substring" || name == "sub_string") && isString(stripCast(subj))) {
                    // Member-call lowering into the u_string runtime: the
                    // bounds are UTF-16 units on every target, so the call
                    // converts them to byte boundaries. The runtime keeps
                    // i32 bounds for the same clamping reason as
                    // u_string.slice (SIGNED_SHIM_PARAMS), and the subject
                    // borrows like every u_string call. An omitted
                    // ?endIndex reaches this arm as a null argument and
                    // routes to the one-sided form.
                    state.shimsUsed.set("std.UStringRT", true);
                    imports.require("crate::runtime::u_string");
                    final endOmitted = args.length < 2 || switch (stripWrap(args[1]).expr) {
                        case TConst(TNull): true;
                        case _: false;
                    };
                    if (!endOmitted) {
                        return "u_string::substring(&" + expr(subj) + ", " + castSignedI32(args[0]) + ", " + castSignedI32(args[1]) + ")";
                    }
                    return "u_string::substring_from(&" + expr(subj) + ", " + castSignedI32(args[0]) + ")";
                }
                if (name == "substr" && isString(stripCast(subj))) {
                    // Member-call lowering into the u_string runtime:
                    // UTF-16 units bound the cut on every target, a
                    // negative pos counts from the end of the unit
                    // sequence, and an omitted ?len reaches this arm as
                    // a null argument and routes to None.
                    state.shimsUsed.set("std.UStringRT", true);
                    imports.require("crate::runtime::u_string");
                    final lenOmitted = args.length < 2 || switch (stripWrap(args[1]).expr) {
                        case TConst(TNull): true;
                        case _: false;
                    };
                    if (!lenOmitted) {
                        return "u_string::substr(&" + expr(subj) + ", " + castSignedI32(args[0]) + ", Some(" + castSignedI32(args[1]) + "))";
                    }
                    return "u_string::substr(&" + expr(subj) + ", " + castSignedI32(args[0]) + ", None)";
                }
                if (name == "put" && isSortedBuilder(subj)) {
                    // Builder puts borrow every argument; the resident
                    // clones into storage, so the call-site expressions
                    // stay alive. A nullable receiver unwraps its inner
                    // builder mutably before the put. The value slot is
                    // the applied V of the receiver: a nullable local
                    // feeding a non-null V unwraps to the borrowed inner,
                    // and a plain value feeding a nullable V wraps in
                    // Some. (SortedPutValueAdaptation)
                    final appliedSlot = {
                        final applied = appliedReceiverParamTypes(cf.get().type, subj.t);
                        var v:Null<Type> = applied != null && applied.length > 1 ? applied[1] : null;
                        // A bare-value builder's applied V is the inner
                        // type: every stored value is has-guard-proven
                        // non-null. (BuilderValueNullability)
                        final subjBuilder = switch (stripWrap(subj).expr) {
                            case TLocal(b): b;
                            case _: null;
                        };
                        if (v != null && subjBuilder != null && bareValueBuilders.exists(subjBuilder.id) && isNullType(v))
                            v = getNullInnerType(v);
                        v;
                    };
                    final putArgs = [for (i in 0...args.length) {
                        var r = sortedRefArg(args[i]);
                        // A string literal key owns its storage: the borrow
                        // of a bare literal is a &str while the table key is
                        // a String. (SortedPutValueAdaptation)
                        if (i == 0 && switch (stripWrap(args[i]).expr) {
                            case TConst(TString(_)): true;
                            case _: false;
                        })
                            r = r + ".to_string()";
                        // A borrowed match binding as the value (index 1) of
                        // a nullable-V map wraps its cloned inner value in
                        // Some. The binding forms are matched exactly, so a
                        // nested render that contains the name anywhere must
                        // pass through untouched.
                        final binding = (~/^&\((__option\d+)\)$/);
                        final clonedBinding = (~/^&\(\*(__option\d+)\)\.clone\(\)$/);
                        final parenClonedBinding = (~/^&\(\(\*(__option\d+)\)\.clone\(\)\)$/);
                        if (i == 1 && appliedSlot != null && isNullType(appliedSlot)) {
                            if (binding.match(r))
                                r = "&(Some((*" + binding.matched(1) + ").clone()))";
                            else if (clonedBinding.match(r))
                                r = "&(Some((*" + clonedBinding.matched(1) + ").clone()))";
                            else if (parenClonedBinding.match(r))
                                r = "&(Some((*" + parenClonedBinding.matched(1) + ").clone()))";
                            else if (!isNullType(args[i].t)
                                && !isNumericScalarType(getNullInnerType(appliedSlot))
                                // A has-guard-proven value local holds the
                                // bare inner value and stores as-is.
                                // (BuilderValueNullability)
                                && !(switch (stripWrap(args[i]).expr) {
                                    case TLocal(v2): nullableCollapsedLocals.exists(v2.id);
                                    case _: false;
                                })) {
                                // A plain value enters a nullable slot: the
                                // boundary wraps it in Some. A match binding
                                // is a reference to the inner value, so it
                                // dereferences and clones. (SortedPutValueAdaptation)
                                final inner = StringTools.startsWith(r, "&")
                                    ? stripRenderedParens(r.substr(1))
                                    : stripRenderedParens(r);
                                final bareBinding = (~/^(__option\d+)$/);
                                if (!StringTools.startsWith(inner, "Some(")) {
                                    r = bareBinding.match(inner)
                                        ? "&(Some((*" + bareBinding.matched(1) + ").clone()))"
                                        : "&(Some(" + inner + "))";
                                }
                            }
                        // A null-guarded get local lowers to the bare
                        // inner value (its declaration unwrapped); a
                        // nullable-V slot still needs the Option shape.
                        // (SortedPutValueAdaptation)
                        else if (i == 1 && appliedSlot != null && isNullType(appliedSlot) && isNullType(args[i].t)
                            && switch (stripWrap(args[i]).expr) {
                                case TLocal(v): nullableCollapsedLocals.exists(v.id)
                                    || hasGuardedTernaryLocals.exists(v.id);
                                case _: false;
                            })
                            r = "&(Some(" + stripRenderedParens(expr(stripWrap(args[i]))) + "))";
                        } else if (i == 1 && appliedSlot != null && !isNullType(appliedSlot) && isNullType(args[i].t)
                            && switch (stripWrap(args[i]).expr) {
                                case TLocal(v): optionRenderedLocals.exists(v.id);
                                case _: false;
                            })
                            r = "(" + stripRenderedParens(expr(stripWrap(args[i]))) + ").as_ref().unwrap()";
                        r;
                    }];
                    return nullableMethodReceiver(subj, true) + ".put(" + putArgs.join(", ") + ")";
                }
                if (name == "build" && isSortedBuilder(subj)) {
                    // build() consumes the builder; a nullable receiver
                    // must yield the owned inner value so the consuming
                    // call can move it. Covers the builder-build family (E0507).
                    final receiver = nullableMethodReceiver(subj, false);
                    // nullableMethodReceiver for a non-mutable nullable receiver
                    // produces .as_ref().unwrap(). Strip .as_ref() so the
                    // owned builder reaches the consuming build().
                    final ownedReceiver = StringTools.replace(receiver, ".as_ref().unwrap()", ".unwrap()");
                    // A build consumes the builder in Rust, but Haxe
                    // builders are reference objects: the same builder can
                    // build again, and callers keep using it after a
                    // build. Both builders derive Clone, so every build
                    // clones its receiver and consumes the clone. Shared
                    // (Mutex-guarded) receivers clone through the guard the
                    // same way. (SharedClosureArrays, BuilderSnapshot)
                    return ownedReceiver + ".clone().build()";
                }
                if ((name == "get" || name == "has") && (isSortedTable(subj) || isSortedBuilder(subj))) {
                    final receiver = nullableMethodReceiver(subj, false);
                    final call = receiver + "." + name + "(" + sortedRefArg(args[0]) + ")";
                    // SortedMap<K, Null<V>>.get returns Option<Option<V>> in
                    // Rust (the resident get wraps the stored Option<V>),
                    // but Haxe normalizes Null<Null<V>> to Null<V>, so the
                    // double Option must flatten to one. Only a nullable
                    // value type triggers the extra layer.
                    if (name == "get" && sortedMapValueTypeIsNullable(subj))
                        return call + ".flatten()";
                    return call;
                }
                if (name == "size" && isSortedTable(subj)) {
                    // The resident counts in its signed Int domain; the business
                    // domain is unsigned, so the read reinterprets the raw i32.
                    // Under a signed comparison target the other operand narrows
                    // to i32, so this read narrows the same way and both sides
                    // share one type. (ResidentI32Comparison)
                    final sizeRead = nullableMethodReceiver(subj, false) + ".size()";
                    // Both forms are bit reinterprets of the same i32 read;
                    // the direction follows the comparison's target domain.
                    // The narrow form's u32 mask literal overflows i32, so
                    // the signed target uses the plain reinterpret.
                    return i32ComparisonTarget
                        ? RustConversions.reinterpret(sizeRead, "i32")
                        : RustConversions.reinterpret(sizeRead, "u32");
                }
                if ((name == "keyAt" || name == "valueAt" || name == "at") && isSortedTable(subj)) {
                    return nullableMethodReceiver(subj, false) + "." + RustImports.toSnakeCase(name) + "(" + castSignedI32(args[0]) + ")";
                }
                if (name == "put" && isSortedBuilder(subj)) {
                    final kExpr = switch (args[0].expr) {
                        case TConst(TString(_)): expr(args[0]);
                        case TLocal(_) | TField(_):
                            if (!isTypeCopy(args[0].t)) {
                                expr(args[0]) + ".clone()";
                            } else {
                                expr(args[0]);
                            }
                        case _: expr(args[0]);
                    };
                    if (args.length > 1) {
                        final vExpr = if (isStringType(args[1].t)) {
                            switch (args[1].expr) {
                                case TConst(TString(_)): expr(args[1]) + ".to_string()";
                                case _: expr(args[1]) + ".clone()";
                            }
                        } else {
                            // The value renders through the full call-argument
                            // chain (paramOffset 1 reads the declared V slot)
                            // so the borrowed-binding and proven adaptations
                            // apply. (SortedPutValueAdaptation)
                            renderCallArgs(cf.get().type, [args[1]], null, 1, null, subj.t);
                        };
                        return nullableMethodReceiver(subj, true) + ".put(" + kExpr + ", " + vExpr + ")";
                    } else {
                        return nullableMethodReceiver(subj, true) + ".put(" + kExpr + ")";
                    }
                }
                if ((name == "get" || name == "has") && (isSortedTable(subj) || isSortedBuilder(subj))) {
                    final kExpr = if (isStringType(args[0].t)) {
                        switch (args[0].expr) {
                            case TConst(TString(_)): expr(args[0]);
                            case TLocal(v):
                                final pt = types.of(v.t, true);
                                if (pt == "&str") expr(args[0]); else "&" + expr(args[0]);
                            case _: expr(args[0]);
                        }
                    } else if (!isTypeCopy(args[0].t)) {
                        "&" + expr(args[0]);
                    } else {
                        expr(args[0]);
                    };
                    return nullableMethodReceiver(subj, false) + "." + name + "(" + kExpr + ")";
                }
                if (name == "push") {
                    return nullableMethodReceiver(subj, true) + ".push(" + renderPushArg(args[0], arrayElementType(subj.t)) + ")";
                }
                if (name == "join") {
                    if (isVecType(subj)) {
                        // The iterator spec records no callback-driven call
                        // sites or closures in a loop body, so the Vec join
                        // renders as the ruled single-pass builder.
                        imports.require("std::fmt::Write");
                        final joined = freshRegionName("joined");
                        final index = freshRegionName("index");
                        final receiver = nullableMethodReceiver(subj, false);
                        // A nullable receiver rendered as (X.clone()).as_ref().unwrap()
                        // creates a clone temporary whose lifetime ends at the
                        // semicolon; split into separate bindings so the clone
                        // outlives the join body (E0716).
                        final needsSplit = StringTools.contains(receiver, ".clone()).as_ref().unwrap()");
                        if (needsSplit) {
                            final tmp = freshRegionName("_jtmp");
                            final cloneExpr = StringTools.replace(receiver, ".as_ref().unwrap()", "");
                            return "{ let " + tmp + " = " + cloneExpr + "; let " + joined + " = " + tmp + ".as_ref().unwrap(); let mut out = String::new(); let n = "
                                + joined + ".len(); let mut " + index + " = 0usize; while " + index + " < n { if " + index
                                + " > 0 { out.push_str(&(" + renderedArgs + ")); } let _ = write!(out, \"{}\", " + joined + "[" + index + "]); "
                                + index + " += 1; } out }";
                        }
                        return "{ let " + joined + " = " + receiver + "; let mut out = String::new(); let n = "
                            + joined + ".len(); let mut " + index + " = 0usize; while " + index + " < n { if " + index
                            + " > 0 { out.push_str(&(" + renderedArgs + ")); } let _ = write!(out, \"{}\", " + joined + "[" + index + "]); "
                            + index + " += 1; } out }";
                    }
                    return nullableMethodReceiver(subj, false) + ".join(" + renderedArgs + ")";
                }
                // Haxe Array methods that Rust's Vec names differently or
                // implements under another operation.
                if (name == "copy" && isVecType(subj)) {
                    return expr(subj) + ".clone()";
                }
                if ((name == "concat" || name == "concat_array") && isVecType(subj) && args.length == 1) {
                    return "{ let mut result = " + expr(subj) + ".clone(); result.extend(" + expr(args[0]) + ".iter().cloned()); result }";
                }
                if (name == "shift" && isVecType(subj)) {
                    return "{ if " + expr(subj) + ".is_empty() { None } else { Some(" + expr(subj) + ".remove(0)) } }";
                }
                if (name == "unshift" && isVecType(subj) && args.length == 1) {
                    return expr(subj) + ".insert(0, " + renderPushArg(args[0], arrayElementType(subj.t)) + ")";
                }
                if (name == "insert" && isVecType(subj) && args.length == 2) {
                    return expr(subj) + ".insert(" + castArg(args[0], "usize") + ", " + renderPushArg(args[1], arrayElementType(subj.t)) + ")";
                }
                // vecSpliceDrain: Haxe Array.splice(pos, len) removes len
                // elements at pos and returns the removed sub-array. Rust's
                // Vec::splice has different semantics (range + replacement
                // iterator), so the lowering uses Vec::drain on a usize range
                // built from the cast index and count. The drain moves the
                // elements out of the Vec and the block collects them into a
                // new Vec matching the Haxe return type.
                if (name == "splice" && isVecType(subj) && args.length == 2) {
                    final idxVar = freshRegionName("splice_index");
                    final countVar = freshRegionName("splice_count");
                    final removedVar = freshRegionName("splice_removed");
                    return "{ let " + idxVar + " = " + castArg(args[0], "usize") + "; let " + countVar + " = " + castArg(args[1], "usize") + "; let " + removedVar + ": Vec<_> = "
                        + expr(subj) + ".drain(" + idxVar + ".." + idxVar + " + " + countVar + ").collect(); " + removedVar + " }";
                }
                if (name == "indexOf" && isVecType(subj) && args.length >= 1) {
                    var needle = expr(args[0]);
                    // A narrowed binding deref carries the signed i32 inner
                    // domain; the business Int element compares in u32, so
                    // the needle reinterprets before the comparison.
                    if (isIntType(arrayElementType(subj.t)) && narrowedSubject(args[0]) != null
                        && isIntType(getNullInnerType(args[0].t)))
                        needle = RustConversions.reinterpret(needle, "u32");
                    // A nullable needle searches as its inner value: Haxe's
                    // indexOf(null) never matches an Int element, so the
                    // absent value falls to the -1 sentinel, which the u32
                    // reinterpret maps past every real element.
                    // (NullableNeedleDomain)
                    else if (isIntType(arrayElementType(subj.t)) && isNullType(args[0].t)
                        && !isTNull(args[0]) && narrowedSubject(args[0]) == null)
                        needle = RustConversions.reinterpret(needle + ".unwrap_or(-1)", "u32");
                    // The iterator yields &T; compare by reference so the
                    // element is not moved out of the Vec (E0507/E0277 on a
                    // non-Copy element like String). A nullable receiver
                    // unwraps to its inner Vec first.
                    return "match "
                        + nullableMethodReceiver(subj, false)
                        + ".iter().position(|e| e == &"
                        + needle
                        + ") { Some(v) => i32::from_ne_bytes(u32::try_from(v).unwrap_or(0).to_ne_bytes()), None => -1 }";
                }
                if (name == "addByte") {
                    return receiverText(subj, cf) + ".add_byte(" + RustConversions.truncate(expr(args[0]), "u8") + ")";
                }
                if (name == "add") {
                    return receiverText(subj, cf) + ".add(&" + expr(args[0]) + ")";
                }
                if (name == "readU16") {
                    // The wire read answers u16 while the Int domain is
                    // u32; the widening is total, so from covers every
                    // value the field can hold. The read is fallible, so
                    // the call propagates before the widening.
                    return "u32::from(" + receiverText(subj, cf) + ".read_u16()?)";
                }
                if (name == "writeU16") {
                    // The Int domain is u32 while the wire field is u16;
                    // the Haxe writer masks to the low half, and the Rust
                    // cast truncates identically, so the narrowing matches
                    // source semantics for every value.
                    return receiverText(subj, cf) + ".write_u16(" + RustConversions.truncate(expr(args[0]), "u16") + ")";
                }
                if (name == "writeU32") {
                    final innerArg = stripWrap(args[0]);
                    final isLen = switch (innerArg.expr) {
                        case TField(_, fa) if (fieldName(fa) == "length"): true;
                        case _: false;
                    };
                    if (isLen) {
                        if (errorTypeName == null || countOverflowVariant == null) {
                            Context.error("cannot lower length conversion: missing error enum or overflow variant", args[0].pos);
                            return "";
                        }
                        final errVariant = errorTypeName + "::" + countOverflowVariant;
                        return receiverText(subj, cf) + ".write_u32(u32::try_from(" + expr(args[0]) + ").map_err(|_| " + errVariant + ")?)";
                    }
                    return receiverText(subj, cf) + ".write_u32(" + expr(args[0]) + ")";
                }
                if (name == "writeAscii") {
                    // A heap String argument borrows as &str; string
                    // literals and parameters of the enclosing function
                    // already render as &str.
                    final argStr = if (isStringType(args[0].t)) {
                        switch (stripWrap(args[0]).expr) {
                            case TConst(TString(_)): expr(args[0]);
                            case TLocal(v) if (isBorrowedParamLocal(v)): expr(args[0]);
                            case _: expr(args[0]) + ".as_str()";
                        }
                    } else {
                        expr(args[0]);
                    };
                    return receiverText(subj, cf) + ".write_ascii(" + argStr + ")";
                }
                if (cf != null && cf.get().kind.match(FVar(_, _)) && Context.follow(cf.get().type).match(TFun(_, _))) {
                    // A function-typed field calls through a parenthesized
                    // receiver: the field itself names the callee, so the
                    // read renders as an explicit field access in the
                    // parenthesized position. Method fields (FMethod) take
                    // the ordinary method-call path above this branch.
                    // Parameter-typed arguments borrow unless the local
                    // already holds a reference (a borrowed parameter of
                    // the enclosing function).
                    return "(" + expr(subj) + "." + snake + ")(" + renderCallArgs(cf.get().type, args, null, 0, null, subj.t) + ")";
                }
                final isMethodFallible = isFallibleCallee(c, cf, false);
                final q = isFallible ? (isMethodFallible ? errorPropagationSuffix(c, cf, false) : "") : (isMethodFallible ? ".unwrap()" : "");
                final previousReceiverContext = renderingMethodReceiver;
                renderingMethodReceiver = RustDecl.methodWritesReceiver(cf.get());
                final subjText = expr(subj);
                renderingMethodReceiver = previousReceiverContext;
                final narrowed = narrowedSubject(subj);
                if (narrowed != null)
                    optionNarrowingHitCount++;
                // A mutating method borrows the unwrapped receiver mutably:
                // the trait-mutation table drives the interface-method calls,
                // the receiver-writer list the concrete ones (MutatingForcing).
                final mutCall = RustDecl.mutatingTraitMethods.exists(cf.get().name)
                    || RustDecl.methodWritesReceiver(cf.get());
                final forcingRead = mutCall ? ".as_mut().unwrap()" : ".as_ref().unwrap()";
                final subjStr = narrowed != null ? narrowed
                    : (receiverCarriesFallibleWrapper(subj) ? subjText + forcingRead : subjText);
                // A by-value method on a shared (Mutex-guarded) receiver
                // cannot move out of the guard: clone the referent through
                // the guard and consume the clone. (SharedClosureArrays)
                final receiverSharedLocal = switch (stripWrap(subj).expr) {
                    case TLocal(v): sharedClosureArrays.exists(v.id) || sharedClosureScalars.exists(v.id);
                    case _: false;
                };
                final throughGuardClone = receiverSharedLocal && RustDecl.methodConsumesSelf(cf.get());
                final callReceiver = throughGuardClone ? subjText + ".clone()" : subjStr;
                return callReceiver + "." + snake + "(" + renderCallArgs(cf.get().type, args, null, 0, mutableParamPositions(cf.get()), subj.t) + ")" + q;
            case TField(_, FStatic(c, cf)):
                final cls = c.get();
                final name = cf.get().name;
                final path = cls.pack.length == 0 ? cls.name : cls.pack.join(".") + "." + cls.name;
                if (cls.pack.length == 0 && cls.name == "StringTools" && name == "hex") {
                    return stringToolsHex(args);
                }
                if (cls.pack.length == 0 && cls.name == "StringTools" && name == "trim" && args.length == 1) {
                    return expr(args[0]) + ".trim()";
                }
                if (cls.pack.length == 0
                    && cls.name == "StringTools"
                    && (name == "startsWith" || name == "endsWith")
                    && args.length == 2) {
                    // A Null<String> first argument lowers to Option<String>;
                    // Haxe calls the method on the inner value (null throws),
                    // so unwrap the wrapper before the member call. A
                    // narrowed subject already binds the inner value and must
                    // not re-apply the forcing read (E0599 on &String).
                    final narrowed = narrowedSubject(args[0]);
                    if (narrowed != null)
                        optionNarrowingHitCount++;
                    final sText = expr(args[0]);
                    final sStr = narrowed != null ? narrowed
                        : (receiverCarriesFallibleWrapper(args[0]) ? "(" + sText + ").as_ref().unwrap()" : sText);
                    return "(" + sStr + ")." + RustImports.toSnakeCase(name) + "(&" + expr(args[1]) + ")";
                }
                if (cls.pack.length == 0 && cls.name == "Lambda" && name == "has" && args.length == 2) {
                    return "(" + expr(args[0]) + ").contains(&" + expr(args[1]) + ")";
                }
                if (cls.pack.length == 0 && cls.name == "Std" && name == "int") {
                    // An Int-typed argument converts nothing, except a
                    // bare length read, whose rendering is usize.
                    if (isIntType(args[0].t) && !isUsizeExpr(args[0])) {
                        return expr(args[0]);
                    }
                    // Haxe types Int/Int division as Float but truncates it
                    // back through Std.int; the truncation is Rust integer
                    // division, so the Float round-trip drops away.
                    final truncDiv = intDivisionOf(args[0]);
                    if (truncDiv != null) {
                        return truncDiv;
                    }
                    // A length-division lowering is already a truncating
                    // integer quotient in the module domain; Std.int over it
                    // converts nothing.
                    if (isLengthDivision(args[0])) {
                        return expr(args[0]);
                    }
                    // A genuine Float argument truncates with Rust `as`
                    // saturation, reproduced bit-exactly without a cast.
                    if (RuntimeResidents.isResident(imports.selfModule)) {
                        return RustConversions.floatToI32(expr(args[0]));
                    }
                    return RustConversions.floatToU32(expr(args[0]));
                }
                if (cls.pack.length == 0 && cls.name == "String" && name == "fromCharCode") {
                    final value = expr(args[0]);
                    // A collapsed local already rendered as a plain integer;
                    // unwrap applies only to an argument that still carries Option.
                    final collapsedArg = switch (stripWrap(args[0]).expr) {
                        case TLocal(v): nullableCollapsedLocals.exists(v.id);
                        case _: false;
                    };
                    final argument = (isNullType(args[0].t) && !collapsedArg) ? "(" + value + ".unwrap_or_default())" : (StringTools.startsWith(value,
                        "(") ? value : "("
                        + value + ")");
                    final unwrapped = argument;
                    return "String::from_utf16(&[u16::try_from" + unwrapped + ".unwrap_or_default()]).unwrap_or_default()";
                }
                if (path == "std.UStringPlatform") {
                    // Cursor primitives of the resident UString walk, inlined
                    // per call: a cursor is a byte offset here, so end is the
                    // byte length, codeAt decodes the char at the offset, and
                    // advance adds that char's UTF-8 width. Business code
                    // never reaches them; it calls std.UString.
                    if (!RuntimeResidents.isResident(imports.selfModule)) {
                        Context.error("std.UStringPlatform is a resident runtime primitive; business code calls std.UString", fn.pos);
                    }
                    switch (name) {
                        case "end":
                            return RustConversions.narrowI32("(" + expr(args[0]) + ").len()");
                        case "codeAt":
                            // A char lowers to its Unicode scalar through
                            // From<char> for u32, then narrows into the
                            // resident i32 domain (values fit: scalars cap at
                            // 0x10FFFF).
                            return "i32::try_from(u32::from(" + "(" + expr(args[0]) + ")[" + castArg(args[1], "usize")
                                + "..].chars().next().unwrap_or('\\0')" + ")).unwrap_or(0)";
                        case "advance":
                            return RustConversions.narrowI32("(" + castArg(args[1], "usize") + " + (" + expr(args[0]) + ")[" + castArg(args[1], "usize")
                                + "..].chars().next().unwrap_or('\\0').len_utf8())");
                        case "substringBetween":
                            return "(" + expr(args[0]) + ")[" + castArg(args[1], "usize") + ".." + castArg(args[2], "usize") + "].to_string()";
                        case "fromCodePoint":
                            return "char::from_u32(" + RustConversions.reinterpret(expr(args[0]), "u32") + ").unwrap_or('\\0').to_string()";
                        case _:
                    }
                }
                if (RustTestBinding.isTestPlatformExtern(path)) {
                    // Host edges of the resident runtime.TestCore, inlined
                    // per call: raising is a panic, the running test id
                    // lives in the test host module of the runtime emit, and
                    // plain numbers render through to_string. Marking the
                    // test extern shim used keeps that host module emitted
                    // beside this resident. Business code never reaches
                    // these; it calls test extern.
                    if (!RuntimeResidents.isResident(imports.selfModule)) {
                        Context.error("test platform extern is a resident runtime primitive; business code calls test extern", fn.pos);
                    }
                    state.shimsUsed.set(RuntimeResidents.externsOf("runtime.TestCore")[0], true);
                    switch (name) {
                        case "raise":
                            return "panic!(\"{}\", " + expr(args[0]) + ")";
                        case "currentTestId":
                            return "crate::runtime::test::current_test_id()";
                        case "intToString":
                            return "(" + expr(args[0]) + ").to_string()";
                        case "floatToString":
                            return "(" + expr(args[0]) + ").to_string()";
                        case _:
                    }
                }
                if (path == "haxe.io.FPHelper") {
                    imports.requireType(cls.module, "FPHelper");
                    // The f32 configuration converts the two 64-bit value edges to their
                    // binary32 runtime variants; the 8-byte wire bit layout
                    // is untouched (feature spec 23, ruling 7).
                    final targetName = if (FloatPrecision.isF32()) {
                        if (name == "i64ToDouble")
                            "i64ToF32"
                        else if (name == "doubleToI64")
                            "f32ToI64"
                        else if (name == "i32ToFloat")
                            "i32ToF32"
                        else if (name == "floatToI32")
                            "f32ToI32"
                        else
                            name;
                    } else {
                        name;
                    }
                    // The signed bit edge takes the i32 domain while the Haxe
                    // parameter is the business u32 Int, so the argument
                    // reinterprets unless it already lowers signed.
                    final fpArgs = if (name == "i32ToFloat" && args.length == 1 && isIntType(args[0].t)) {
                        final argStr = expr(args[0]);
                        rendersSignedIntArg(args[0], argStr) ? argStr : RustConversions.reinterpret(argStr, "i32");
                    } else {
                        renderCallArgs(cf.get().type, args, null, 0, mutableParamPositions(cf.get()));
                    };
                    return "FPHelper::" + RustImports.toSnakeCase(targetName) + "(" + fpArgs + ")";
                }
                if (cls.module == "Math" && name == "isNaN")
                    return "(" + mathFloatBindingArg(args[0]) + ").is_nan()";
                if (cls.module == "Math" && name == "isFinite")
                    return "(" + mathFloatBindingArg(args[0]) + ").is_finite()";
                if (cls.module == "Math" && name == "abs")
                    return "(" + mathFloatBindingArg(args[0]) + ").abs()";
                if (cls.module == "Math" && (name == "min" || name == "max") && args.length == 2) {
                    // Rust's intrinsic min/max return the non-NaN operand,
                    // unlike the Haxe/JavaScript oracle. Bind first so the
                    // explicit semantic check preserves left-to-right,
                    // single evaluation of both arguments. The bind names
                    // are fresh so an argument that references a local
                    // named `a`/`b` is not shadowed by the block bindings.
                    final real = FloatPrecision.isF32() ? "f32" : "f64";
                    final aName = freshRegionName("__min_a");
                    final bName = freshRegionName("__min_b");
                    final a = mathFloatBindingArg(args[0]);
                    final b = mathFloatBindingArg(args[1]);
                    final zeroResult = name == "min" ? "if " + aName + ".is_sign_negative() { " + aName + " } else { " + bName + " }" : "if " + aName + ".is_sign_negative() { " + bName + " } else { " + aName + " }";
                    final ordered = name == "min" ? "if " + aName + " < " + bName + " { " + aName + " } else if " + bName + " < " + aName + " { " + bName + " } else if " + aName + " == 0.0 && " + bName + " == 0.0 { "
                        + zeroResult
                        + " } else { " + aName + " }" : "if " + aName + " > " + bName + " { " + aName + " } else if " + bName + " > " + aName + " { " + bName + " } else if " + aName + " == 0.0 && " + bName + " == 0.0 { "
                        + zeroResult
                        + " } else { " + aName + " }";
                    return "({ let " + aName + " = (" + a + ") as " + real + "; let " + bName + " = (" + b + ") as " + real + "; if " + aName + ".is_nan() || " + bName + ".is_nan() { " + real + "::NAN } else { " + ordered + " } })";
                }
                if (cls.module == "Math" && name == "pow" && args.length == 2) {
                    // Rust names the power function powf; the f32
                    // configuration reads it from f32 (feature spec 23).
                    final real = FloatPrecision.isF32() ? "f32" : "f64";
                    return real + "::powf(" + mathFloatBindingArg(args[0]) + ", " + mathFloatBindingArg(args[1]) + ")";
                }
                if (cls.module == "Math" && name == "sqrt")
                    return "(" + mathFloatBindingArg(args[0]) + ").sqrt()";
                if (cls.module == "Math" && (name == "floor" || name == "ceil" || name == "round")) {
                    // Haxe types floor, ceil, and round as Int; the Rust
                    // methods return the real type, so the call site
                    // truncates through the same conversion Std.int uses.
                    final real = FloatPrecision.isF32() ? "f32" : "f64";
                    final rounded = real + "::" + name + "(" + mathFloatBindingArg(args[0]) + ")";
                    return RuntimeResidents.isResident(imports.selfModule) ? rounded + " as i32" : RustConversions.floatToU32(rounded);
                }
                if (cls.module == "Std" && name == "parseFloat") {
                    final real = FloatPrecision.isF32() ? "f32" : "f64";
                    imports.require("crate::runtime::u_string");
                    return "u_string::parse_" + real + "(&(" + expr(args[0]) + "))";
                }
                if (cls.module == "Std" && name == "parseInt") {
                    imports.require("crate::runtime::u_string");
                    return "u_string::parse_i32(&(" + expr(args[0]) + "))";
                }
                if ((cls.module == "std.Process" || (cls.pack.join(".") == "std" && cls.name == "Process")) && name == "exit") {
                    imports.require("std::process::exit");
                    return "exit(" + renderedArgs + ")";
                }
                if ((path == "std.Process" || cls.module == "std.Process") && name == "args") {
                    // std.Process.args() reads the arguments of the test
                    // binary after its name (stdlib/17).
                    return "std::env::args().skip(1).collect::<Vec<String>>()";
                }
                if ((path == "std.SortedMap" || cls.module == "std.SortedMap") && name == "builder") {
                    final kType = sortedKeyType(fn);
                    final vType = sortedValueType(fn);
                    state.shimsUsed.set("std.SortedMap", true);
                    imports.requireType("runtime.SortedTable", "SortedTable");
                    return "SortedTable::sorted_table_map_builder::<" + types.of(kType) + ", "
                            + (bareValueBuilderPos.exists(Std.string(fn.pos)) ? stripLastValueOption(types.of(vType)) : types.of(vType))
                            + ">(" + sortedComparator(kType, fn.pos) + ")";
                }
                if ((path == "std.SortedSet" || cls.module == "std.SortedSet") && name == "builder") {
                    final kType = sortedKeyType(fn);
                    state.shimsUsed.set("std.SortedSet", true);
                    imports.requireType("runtime.SortedTable", "SortedTable");
                    return "SortedTable::sorted_table_set_builder::<" + types.of(kType) + ">(" + sortedComparator(kType, fn.pos) + ")";
                }
                if ((path == "runtime.SortedTable" || cls.module == "runtime.SortedTable") && (name == "mapBuilder" || name == "setBuilder")) {
                    // The resident builder binds its key (and value) type at
                    // the comparator, so a call through the runtime class
                    // carries the same explicit parameters and comparator
                    // closure the std builder front carries (stdlib/07).
                    final kType = sortedKeyType(fn);
                    final vType = sortedValueType(fn);
                    imports.requireType("runtime.SortedTable", "SortedTable");
                    if (name == "mapBuilder")
                        return "SortedTable::sorted_table_map_builder::<" + types.of(kType) + ", "
                            + (bareValueBuilderPos.exists(Std.string(fn.pos)) ? stripLastValueOption(types.of(vType)) : types.of(vType))
                            + ">(" + sortedComparator(kType, fn.pos) + ")";
                    return "SortedTable::sorted_table_set_builder::<" + types.of(kType) + ">(" + sortedComparator(kType, fn.pos) + ")";
                }

                if (RustTestBinding.isTestExtern(cls)) {
                    // The assertion checks and message formatting live in the
                    // resident runtime.TestCore; this host module keeps run and
                    // its result recording. Messages are plain &str: an absent
                    // message renders as the empty string, which the canonical
                    // builder omits.
                    state.shimsUsed.set(RuntimeResidents.externsOf("runtime.TestCore")[0], true);
                    imports.require("crate::runtime::test_core");
                    final messageArg = function(idx:Int):String {
                        return (args.length > idx && !isTNull(args[idx])) ? "&(" + expr(args[idx]) + ")" : "\"\"";
                    };
                    if (name == "ok") {
                        final cond = expr(args[0]);
                        return "test_core::TestCore::test_core_ok(" + cond + ", " + messageArg(1) + ")";
                    }
                    if (name == "fail") {
                        return "test_core::TestCore::test_core_fail(&(" + expr(args[0]) + "))";
                    }
                    if (name == "run") {
                        // Only run lowers to testlib text in this branch;
                        // assertions stay on test_core, so a class without
                        // a run call must not import testlib.
                        imports.require("crate::runtime::test as testlib");
                        return "testlib::run(" + renderedArgs + ")";
                    }
                    if (name == "equals") {
                        final expectedArg = args[0];
                        final actualArg = args[1];
                        final msg = messageArg(2);
                        if (isNullType(expectedArg.t) || isNullType(actualArg.t)) {
                            final nullInner = getNullInnerType(expectedArg.t != null
                                && isNullType(expectedArg.t) ? expectedArg.t : actualArg.t);
                            final innerKind = scalarTypeKind(nullInner);
                            imports.require("crate::tests::test_helper::*");
                            switch (innerKind) {
                                case "String":
                                    final expStr = renderOptArg(expectedArg, "String");
                                    final actStr = renderOptArg(actualArg, "String");
                                    return "assert_equals_opt_string(&" + expStr + ", &" + actStr + ", " + msg + ")";
                                case "Int":
                                    final expStr = renderOptArg(expectedArg, "Int");
                                    final actStr = renderOptArg(actualArg, "Int");
                                    return "assert_equals_opt(&" + expStr + ", &" + actStr + ", " + msg + ")";
                                case _:
                            }
                        }
                        if (isScalarType(expectedArg.t)) {
                            final scalarKind = scalarTypeKind(expectedArg.t);
                            switch (scalarKind) {
                                case "Bool":
                                    return "test_core::TestCore::test_core_equals_bool(" + expr(expectedArg) + ", " + expr(actualArg) + ", " + msg + ")";
                                case "Int":
                                    // Business Int renders u32, usize in loop heads;
                                    // the resident takes i32, so both sides
                                    // reinterpret once (T5). Literals fold to
                                    // their signed value first.
                                    return "test_core::TestCore::test_core_equals_int(" + castSignedI32(expectedArg) + ", " + castSignedI32(actualArg)
                                        + ", " + msg + ")";
                                case "Float":
                                    return "test_core::TestCore::test_core_equals_float(" + expr(expectedArg) + ", " + expr(actualArg) + ", " + msg + ")";
                                case "String":
                                    return "test_core::TestCore::test_core_equals_string(&(" + expr(expectedArg) + "), &(" + expr(actualArg) + "), " + msg
                                        + ")";
                                case _:
                            }
                        }
                        // Aggregate equality
                        recordAggregateType(expectedArg.t);
                        final fnName = aggregateAssertFuncName(expectedArg.t);
                        imports.require("crate::tests::test_helper::*");
                        return fnName + "(&" + expr(expectedArg) + ", &" + expr(actualArg) + ", " + msg + ")";
                    }
                }
                final isStaticFallible = isFallibleCallee(c, cf, true);
                final q = isFallible ? (isStaticFallible ? errorPropagationSuffix(c, cf, true) : "") : (isStaticFallible ? ".unwrap()" : "");
                final shimKey = if (cls.module == "std.UStringRT") {
                    "u_string." + name;
                } else {
                    null;
                };
                var signedPositions = shimKey != null ? SIGNED_SHIM_PARAMS.get(shimKey) : null;
                final callerResident = RuntimeResidents.isResidentAbi(imports.selfModule);
                // std.UStringRT resolves by caller: residents reach the
                // i32 class, business reaches the u32 adapters, so the
                // callee convention always matches the resolved path.
                final calleeResident = cls.module == "std.UStringRT" ? callerResident : RuntimeResidents.isResidentAbi(cls.module);
                if (calleeResident) {
                    // Resident runtime modules render haxe Int as i32
                    // (their clamping contracts carry negative values),
                    // while business expressions render u32; every Int
                    // parameter casts once at the call boundary.
                    signedPositions = intParamPositions(cf.get().type);
                }
                final callStr = staticRef(cls, name)
                    + "("
                    + renderCallArgs(cf.get().type, args, signedPositions, 0, mutableParamPositions(cf.get()))
                    + ")"
                    + q;
                if (calleeResident != callerResident && returnsInt(cf.get().type)) {
                    // An Int result crosses between the two conventions;
                    // containers never cross whole, only their elements
                    // through Int-typed expressions, which the argument
                    // casts above already cover. The crossing reinterprets
                    // the same-width bits (T5).
                    return RustConversions.reinterpret(callStr, callerResident ? "i32" : "u32");
                }
                return callStr;
            case TField(subj, FEnum(e, ef)):
                final en = e.get();
                imports.requireType(en.module, en.name);
                final efArgs = switch (ef.type) {
                    case TFun(fargs, _): fargs;
                    case _: [];
                };
                final parts = [];
                for (i in 0...args.length) {
                    final argName = i < efArgs.length ? RustImports.toSnakeCase(efArgs[i].name) : "arg" + i;
                    final argType = i < efArgs.length ? efArgs[i].t : null;
                    parts.push(argName + ": " + ownedConstructorArg(argType, args[i], en));
                }
                if (parts.length == 0) {
                    return en.name + "::" + RustImports.toUpperCamelCase(ef.name);
                }
                return en.name + "::" + RustImports.toUpperCamelCase(ef.name) + " { " + parts.join(", ") + " }";
            case TConst(TSuper):
                return "super(" + renderedArgs + ")";
            case TLocal(v):
                // A fallible local function returns Result; propagate the
                // throw to the enclosing error domain at the call.
                final localQ = fallibleLocalFunctionErrors.exists(v.id) ? (isFallible ? "?" : ".unwrap()") : "";
                return expr(fn) + "(" + renderCallArgs(fn.t, args) + ")" + localQ;
            case _:
                return expr(fn) + "(" + renderedArgs + ")";
        }
    }

    function mutableParamPositions(cf:ClassField):Array<Int> {
        final out:Array<Int> = [];
        switch (Context.follow(cf.type)) {
            case TFun(ps, _):
                final body = cf.expr();
                if (body != null)
                    for (i in 0...ps.length)
                        if (RustDecl.argIsMutated(body, ps[i].name))
                            out.push(i);
            case _:
        }
        return out;
    }

    function functionLiteral(f:TFunc, functionType:Null<Type>):String {
        final params = [for (a in f.args)
            (unusedLocalIds.exists(a.v.id) ? "_" : "") + RustImports.toSnakeCase(a.v.name)].join(", ");
        final previousReturnUnsigned = returnUnsigned;
        final previousReturnTypeName = returnTypeName;
        final previousReturnType = currentReturnType;
        final functionReturn = switch (functionType) {
            case null: null;
            case _: switch (Context.follow(functionType)) {
                    case TFun(_, ret): ret;
                    case _: null;
                }
        };
        returnUnsigned = functionReturn == null ? false : switch (Context.follow(functionReturn)) {
            case TAbstract(a, _) if (a.get().name == "Int"): !RuntimeResidents.isResident(imports.selfModule);
            case _: false;
        };
        returnTypeName = functionReturn == null ? null : types.of(functionReturn, false);
        currentReturnType = functionReturn;
        final previousGeneric = inGenericFunction;
        final previousFallible = isFallible;
        final previousErrorTypeName = errorTypeName;
        // A local function has its own return boundary. A body that throws
        // keeps the enclosing error type so each call propagates the throw;
        // an infallible local does not inherit the enclosing Result wrapper.
        final closureError = localFunctionErrorName;
        localFunctionErrorName = null;
        isFallible = closureError != null;
        errorTypeName = closureError;
        inGenericFunction = true;
        genericParamIds.clear();
        final previousClosureParams = closureParamIds.copy();
        closureParamIds.clear();
        for (a in f.args) {
            closureParamIds.set(a.v.id, true);
            if (RustType.isTypeParam(a.v.t))
                genericParamIds.set(a.v.id, true);
        }
        // A capture the body mutates through a method call shadows its
        // capture copy with a mut body-local: an Fn closure cannot mutate
        // a captured binding, but it may mutate its own per-call copy of
        // the value. Only this closure's own captures are shadowed, so a
        // nested body never sees the enclosing closure's marks.
        // (ClosureCaptureMutation)
        final mutShadows = [for (v in closureOwnedCaptures(f))
            if (currentCaptureMut.exists(v.id) && !sharedClosureArrays.exists(v.id) && !sharedClosureScalars.exists(v.id))
                indent(2) + "let mut " + RustImports.toSnakeCase(localName(v)) + " = ("
                    + RustImports.toSnakeCase(localName(v)) + ").clone();"
        ];
        final body = mutShadows.concat(coalescingNormalizationLines(f.expr, 2, [for (a in f.args) a.v.name]).concat(blockLines(statementsOf(f.expr), 2, true)));
        returnUnsigned = previousReturnUnsigned;
        returnTypeName = previousReturnTypeName;
        currentReturnType = previousReturnType;
        isFallible = previousFallible;
        errorTypeName = previousErrorTypeName;
        localFunctionErrorName = closureError;
        inGenericFunction = previousGeneric;
        closureParamIds.clear();
        for (id in previousClosureParams.keys())
            closureParamIds.set(id, true);
        final closureText = 'move |$params| {\n' + body.join("\n") + '\n}';
        // A nested closure that captures a shared closure array or scalar
        // clones the Arc and leaves the enclosing Fn binding in place
        // closure, whose captured bindings are immutable
        // (SharedClosureArrays, SharedClosureScalars).
        final sharedCaptures = [for (v in closureOwnedCaptures(f))
            if (sharedClosureArrays.exists(v.id) || sharedClosureScalars.exists(v.id))
                "let " + RustImports.toSnakeCase(localName(v)) + " = Arc::clone(&" + RustImports.toSnakeCase(localName(v)) + ");"
        ];
        if (sharedCaptures.length > 0) {
            imports.require("std::sync::Arc");
            return "{ " + sharedCaptures.join(" ") + " " + closureText + " }";
        }
        return closureText;
    }

    function functionValueLiteral(f:TFunc, functionType:Null<Type>):String {
        imports.require("std::sync::Arc");
        final captures = closureOwnedCaptures(f);
        final previousClones = currentCaptureClones;
        final previousMut = currentCaptureMut;
        final previousOwnedStrings = captureOwnedStringCopies;
        currentCaptureClones = [for (v in captures) if (!sharedClosureArrays.exists(v.id) && !sharedClosureScalars.exists(v.id)) v.id => true];
        currentCaptureMut = captureMutatedCopies(f, captures);
        captureOwnedStringCopies = [for (v in captures) if (captureCopySuffix(v) == ".to_string()") v.id => true];
        final copies = [for (v in captures) sharedClosureArrays.exists(v.id)
            ? "let " + RustImports.toSnakeCase(localName(v)) + " = Arc::clone(&" + RustImports.toSnakeCase(localName(v)) + ");"
            : "let " + (currentCaptureMut.exists(v.id) ? "mut " : "") + RustImports.toSnakeCase(localName(v)) + " = ("
                + RustImports.toSnakeCase(localName(v)) + ")" + captureCopySuffix(v) + ";"];
        final text = "{ " + copies.join(" ") + " Arc::new(" + functionLiteral(f, functionType) + ") }";
        currentCaptureClones = previousClones;
        currentCaptureMut = previousMut;
        captureOwnedStringCopies = previousOwnedStrings;
        return text;
    }

    /**
        Captures whose closure body calls a mutating method through a field
        chain rooted at the capture. The prologue clone is the closure's own
        copy, so mutating it needs a mut binding; the captured outer binding
        itself stays untouched, which keeps the closure Fn.
        (ClosureCaptureMutation)
    **/
    function captureMutatedCopies(f:TFunc, captures:Array<TVar>):Map<Int, Bool> {
        final out:Map<Int, Bool> = [];
        if (captures.length == 0)
            return out;
        final captureIds:Map<Int, Bool> = [];
        for (v in captures)
            captureIds.set(v.id, true);
        final bound:Map<Int, Bool> = [];
        for (arg in f.args)
            bound.set(arg.v.id, true);
        function walk(e:TypedExpr):Void {
            switch (e.expr) {
                case TVar(v, init):
                    if (init != null)
                        walk(init);
                    bound.set(v.id, true);
                    return;
                case TCall(fn, _):
                    switch (stripWrap(fn).expr) {
                        case TField(subj, FInstance(_, _, cf)):
                            final mutating = switch (Context.follow(subj.t)) {
                                case TInst(ic, _) if (ic.get().isInterface): interfaceMethodWritesReceiver(ic, cf.get());
                                case _: RustDecl.methodWritesReceiver(cf.get());
                            };
                            if (mutating) {
                                var inner = subj;
                                while (true) {
                                    switch (stripWrap(inner).expr) {
                                        case TLocal(l):
                                            if (captureIds.exists(l.id) && !bound.exists(l.id))
                                                out.set(l.id, true);
                                            break;
                                        case TField(next, _): inner = next;
                                        case _: break;
                                    }
                                }
                            }
                        case _:
                    }
                    haxe.macro.TypedExprTools.iter(e, walk);
                case _:
                    haxe.macro.TypedExprTools.iter(e, walk);
            }
        }
        walk(f.expr);
        return out;
    }

    /** The capture-copy conversion suffix: a borrowed view (&str, &Vec)
        must convert to its owned form or the move closure keeps borrowing
        the enclosing frame, which the 'static function-value bound rejects.
        (ClosureCaptureOwnedCopy) */
    function captureCopySuffix(v:TVar):String {
        if (!isBorrowedLocal(v))
            return ".clone()";
        return StringTools.startsWith(types.of(v.t, true), "&Vec") ? ".to_vec()" : ".to_string()";
    }

    /** Clone reusable non-Copy locals at a closure boundary before move capture. */
    function closureOwnedCaptures(f:TFunc):Array<TVar> {
        final bound:Map<Int, Bool> = [];
        final captures:Array<TVar> = [];
        for (arg in f.args)
            bound.set(arg.v.id, true);
        function walk(e:TypedExpr):Void {
            switch (e.expr) {
                case TVar(v, init):
                    if (init != null)
                        walk(init);
                    bound.set(v.id, true);
                    return;
                case TLocal(v):
                    // A shared closure array or scalar renders as
                    // Arc<Mutex<_>>, which never copies, even when the
                    // Haxe macro type (Null<Float>, Null<Int>) reads as a
                    // Copy scalar. The capture line must clone the Arc or
                    // the move closure takes the outer binding.
                    // (SharedClosureArrays, SharedClosureScalars)
                    if (!bound.exists(v.id)
                        && (!isTypeCopy(v.t) || sharedClosureArrays.exists(v.id) || sharedClosureScalars.exists(v.id))
                        && !Lambda.exists(captures, c -> c.id == v.id))
                        captures.push(v);
                case TFunction(nf):
                    // Descend into a nested function literal: a local used
                    // only by the nested body is still moved out of this
                    // scope by the enclosing move closure and needs its
                    // capture clone line here too. The nested parameters
                    // shadow their names for the nested body.
                    // (SharedClosureArrays, SharedClosureScalars)
                    for (a in nf.args)
                        bound.set(a.v.id, true);
                    haxe.macro.TypedExprTools.iter(e, walk);
                    return;
                case _:
            }
            haxe.macro.TypedExprTools.iter(e, walk);
        }
        walk(f.expr);
        return captures;
    }

    /**
        Records every Array local that two or more nested functions capture
        while the mutation scan proved a write on it. The declaration then
        lowers as Arc<Mutex<Vec>> and each capturing closure clones the Arc,
        so one closure's writes are visible to the others' reads. A single
        capturing closure, or a read-only capture set, keeps the snapshot
        clone because its observable behavior already matches.
        (SharedClosureArrays)
    **/
    function scanSharedClosureArrays(root:TypedExpr):Void {
        final fns:Array<TFunc> = [];
        function collect(e:TypedExpr):Void {
            switch (e.expr) {
                case TFunction(f): fns.push(f);
                case _:
            }
            haxe.macro.TypedExprTools.iter(e, collect);
        }
        collect(root);
        if (fns.length < 2)
            return;
        final counts:Map<Int, Int> = [];
        final vars:Map<Int, TVar> = [];
        for (f in fns) {
            final bound:Map<Int, Bool> = [];
            final ids:Map<Int, TVar> = [];
            for (arg in f.args)
                bound.set(arg.v.id, true);
            function walk(e:TypedExpr):Void {
                switch (e.expr) {
                    case TVar(v, init):
                        if (init != null)
                            walk(init);
                        bound.set(v.id, true);
                        return;
                    case TLocal(v):
                        if (!bound.exists(v.id))
                            ids.set(v.id, v);
                    case _:
                }
                haxe.macro.TypedExprTools.iter(e, walk);
            }
            walk(f.expr);
            for (id in ids.keys()) {
                counts.set(id, (counts.exists(id) ? counts.get(id) : 0) + 1);
                vars.set(id, ids.get(id));
            }
        }
        for (id in counts.keys()) {
            // One capturing closure with a proved write already breaks the
            // snapshot-clone contract when the outer scope reads the
            // binding after the closure runs; the shared form is required
            // at any capture count. (SharedClosureArrays)
            if (counts.get(id) < 1 || !mutated.exists(id))
                continue;
            final v = vars.get(id);
            final isArray = switch (Context.follow(v.t)) {
                case TInst(c, _) if (c.get().name == "Array"): true;
                case _: false;
            };
            if (isArray)
                sharedClosureArrays.set(id, true);
        }
    }

    function emissionTrace(tag:String, pos:Dynamic):Void {
        Sys.stderr().writeString("EMITSTACK " + tag + "\n" + haxe.CallStack.toString(haxe.CallStack.callStack()) + "\n");
    }

    function scanSortedGetInfo(call:TypedExpr, wantMethod:String):Null<{subj:String, key:String}> {
        return switch (stripWrap(call).expr) {
            case TCall(fn, args) if (args.length == 1):
                switch (stripWrap(fn).expr) {
                    case TField(subj, FInstance(_, _, cf)) if (cf.get().name == wantMethod):
                        final t = methodSubjectType(subj);
                        switch (Context.follow(t)) {
                            case TInst(c, _):
                                final n = c.get().name;
                                if (n == "SortedMap" || n == "SortedMapTable" || n == "SortedSet" || n == "SortedSetTable" || n == "SortedMapBuilder" || n == "SortedSetTableBuilder")
                                    {subj: subjectTextOf(subj), key: subjectTextOf(args[0])};
                                else
                                    null;
                            case _: null;
                        };
                    case _: null;
                };
            case _: null;
        };
    }

    function isSortedBuilderFactory(fn:TypedExpr):Bool {
        return switch (stripWrap(fn).expr) {
            case TField(_, FStatic(_, cf)): cf.get().name == "mapBuilder" || cf.get().name == "builder";
            case _: false;
        };
    }

    function builderValueIsNullableV(init:TypedExpr):Bool {
        return switch (stripWrap(init).expr) {
            case TCall(fn, _):
                switch (Context.follow(fn.t)) {
                    case TFun(_, ret):
                        switch (Context.follow(ret)) {
                            case TInst(_, params) if (params.length >= 2): isNullType(params[1]);
                            case _: false;
                        };
                    case _: false;
                };
            case _: false;
        };
    }

    function stripLastValueOption(text:String):String {
        final re = ~/^(.*), Option<(.*)>$/;
        return re.match(text) ? re.matched(1) + ", " + re.matched(2) : text;
    }

    function scanBuilderValueNullability(root:TypedExpr):Void {
        final proven:Map<Int, Bool> = [];
        final builderPosByKey:Map<String, Bool> = [];
        function walk1(e:TypedExpr, guards:Map<String, Bool>):Void {
            switch (e.expr) {
                case TIf(cond, then, els):
                    // The local null-guards: `if (d != null)` proves the
                    // local non-null inside the branch, so puts of that
                    // local store non-null values. This arm must run before
                    // the field-guard arm: the field pattern accepts any
                    // subject, and a local subject is proven per id, not
                    // per text. (BuilderValueNullability)
                    final localGuard = switch (stripWrap(cond).expr) {
                        case TBinop(OpNotEq, {expr: TLocal(lv)}, {expr: TConst(TNull)}): lv.id;
                        case _: -1;
                    };
                    if (localGuard >= 0) {
                        proven.set(localGuard, true);
                        walk1(cond, guards);
                        walk1(then, guards);
                        if (els != null)
                            walk1(els, guards);
                        return;
                    }
                    // The field null-guards: `x.f != null` proves the field
                    // non-null inside the branch. (BuilderValueNullability)
                    final fieldGuard = switch (stripWrap(cond).expr) {
                        case TBinop(OpNotEq, fe, {expr: TConst(TNull)}): subjectTextOf(fe);
                        case _: null;
                    };
                    if (fieldGuard != null) {
                        fieldNullGuards.set(fieldGuard, true);
                        final next = [for (k => v in guards) k => v];
                        next.set(fieldGuard, true);
                        walk1(cond, next);
                        walk1(then, next);
                        if (els != null)
                            walk1(els, guards);
                        return;
                    }
                    final info = scanSortedGetInfo(cond, "has");
                    if (info != null) {
                        final key = info.subj + "\u0000" + info.key;
                        final next = [for (k => v in guards) k => v];
                        next.set(key, true);
                        walk1(cond, guards);
                        walk1(then, next);
                        if (els != null)
                            walk1(els, guards);
                        return;
                    }
                    walk1(cond, guards);
                case TVar(v, init):
                    if (init != null) {
                        walk1(init, guards);
                        final info = scanSortedGetInfo(init, "get");
                        if (info != null && guards.exists(info.subj + "\u0000" + info.key))
                            proven.set(v.id, true);
                    }
                    return;
                case TCall(fn, cargs):
                    if (isSortedBuilderFactory(fn)) {
                        final posKey = Std.string(fn.pos);
                        builderPosByKey.set(posKey, true);
                    }
                    walk1(fn, guards);
                    for (a in cargs)
                        walk1(a, guards);
                    return;
                case _:
            }
            haxe.macro.TypedExprTools.iter(e, walk1.bind(_, guards));
        }
        walk1(root, []);
        final builderIds:Map<Int, String> = [];
        final putValues:Map<Int, Array<TypedExpr>> = [];
        function walk2(e:TypedExpr):Void {
            switch (e.expr) {
                case TVar(v, init):
                    if (init != null) {
                        switch (stripWrap(init).expr) {
                            case TCall(fn, _):
                                final posKey = Std.string(fn.pos);
                                if (builderPosByKey.exists(posKey) && builderValueIsNullableV(init))
                                    builderIds.set(v.id, posKey);
                            case _:
                        }
                    }
                case TCall(fn, cargs):
                    if (cargs.length >= 2) {
                        switch (stripWrap(fn).expr) {
                            case TField(s, FInstance(_, _, cf)) if (cf.get().name == "put"):
                                switch (stripWrap(s).expr) {
                                    case TLocal(bid) if (builderIds.exists(bid.id)):
                                        final arr = putValues.exists(bid.id) ? putValues.get(bid.id) : [];
                                        arr.push(cargs[1]);
                                        putValues.set(bid.id, arr);
                                    case _:
                                }
                            case _:
                        }
                    }
                case _:
            }
            haxe.macro.TypedExprTools.iter(e, walk2);
        }
        walk2(root);
        for (id in builderIds.keys()) {
            final values = putValues.exists(id) ? putValues.get(id) : [];
            if (values.length == 0)
                continue;
            var allProven = true;
            for (v in values) {
                var ok = false;
                switch (stripWrap(v).expr) {
                    case TLocal(lid): ok = proven.exists(lid.id);
                    // A field read proven non-null by an enclosing
                    // `x.f != null` guard stores a non-null entry.
                    // (BuilderValueNullability)
                    case TField(_, _): ok = fieldNullGuards.exists(subjectTextOf(stripWrap(v)));
                    case TConst(TInt(_)) | TConst(TFloat(_)) | TConst(TString(_)): ok = true;
                    case _:
                }
                if (!ok) {
                    allProven = false;
                    break;
                }
            }
            if (allProven) {
                bareValueBuilders.set(id, true);
                bareValueBuilderPos.set(builderIds.get(id), true);
            }
        }
        function walk3(e:TypedExpr):Void {
            switch (e.expr) {
                case TVar(v, init):
                    if (init != null) {
                        final call = stripWrap(init);
                        switch (call.expr) {
                            case TCall(fn, cargs):
                                final callee = switch (stripWrap(fn).expr) {
                                    case TField(s, FInstance(_, _, cf)): {subject: s, name: cf.get().name};
                                    case _: null;
                                };
                                if (callee != null) {
                                    var recvExpr = callee.subject;
                                    switch (stripWrap(recvExpr).expr) {
                                        case TCall(cf2, cargs2) if (cargs2.length == 0):
                                            switch (stripWrap(cf2).expr) {
                                                case TField(s2, FInstance(_, _, cf3)) if (cf3.get().name == "clone"):
                                                    recvExpr = s2;
                                                case _:
                                            }
                                        case _:
                                    }
                                    final recvLocal = switch (stripWrap(recvExpr).expr) {
                                        case TLocal(t): t;
                                        case _: null;
                                    };
                                    if (recvLocal != null) {
                                        if (cargs.length == 0 && callee.name == "build" && bareValueBuilders.exists(recvLocal.id))
                                            builtBareTables.set(v.id, true);
                                        if ((callee.name == "value_at" || callee.name == "valueAt" || callee.name == "get" || callee.name == "keyAt") && builtBareTables.exists(recvLocal.id))
                                            nullableCollapsedLocals.set(v.id, true);
                                    }
                                }
                                walk3(fn);
                                for (a in cargs)
                                    walk3(a);
                            case _:
                                walk3(init);
                        }
                    }
                case _:
                    haxe.macro.TypedExprTools.iter(e, walk3);
            }
        }
        walk3(root);
    }

    /** Locals whose id the body never mentions in a TLocal read: the
        declaration only stores a value no one observes.
        (UnusedLocalNaming) */
    function scanUnusedLocals(root:TypedExpr):Void {
        final counts:Map<Int, Int> = [];
        function walk(node:TypedExpr):Void {
            switch (node.expr) {
                case TVar(v, _):
                    if (!counts.exists(v.id))
                        counts.set(v.id, 0);
                case TFunction(nf):
                    // Closure parameters have no TVar declaration node:
                    // register them so a zero-read parameter still marks.
                    for (a in nf.args)
                        if (!counts.exists(a.v.id))
                            counts.set(a.v.id, 0);
                case TBinop(OpAssign, target, value):
                    walk(value);
                    switch (stripWrap(target).expr) {
                        case TLocal(v):
                            // A reassignment only writes; the read state stays
                            // whatever the declaration recorded.
                            if (!counts.exists(v.id))
                                counts.set(v.id, 0);
                        case _:
                            walk(target);
                    }
                case TBinop(op = OpAssignOp(_), target, value):
                    walk(value);
                    switch (stripWrap(target).expr) {
                        case TLocal(v):
                            // A compound assignment still reads the target.
                            counts.set(v.id, (counts.exists(v.id) ? counts.get(v.id) : 0) + 1);
                        case _:
                            walk(target);
                    }
                case TLocal(v):
                    counts.set(v.id, (counts.exists(v.id) ? counts.get(v.id) : 0) + 1);
                case _:
            }
            haxe.macro.TypedExprTools.iter(node, walk);
        }
        walk(root);
        for (id in counts.keys())
            if (counts.get(id) == 0)
                unusedLocalIds.set(id, true);
        scanIntervalCounters(root);
        // A declaration the typer shares with a `for` binding rebinds the
        // same var: every read sits inside the loop subtree, the loop
        // re-initializes the binding, and the emitted `for` declares its
        // own Rust binding that shadows the declaration. The declaration
        // line drops. (ForSharedBindingDeclaration)
        final forBoundIds:Map<Int, Int> = [];
        final readsInFor:Map<Int, Int> = [];
        function scanFor(node:TypedExpr, inFor:Bool):Void {
            switch (node.expr) {
                case TFor(v, it, body):
                    forBoundIds.set(v.id, (forBoundIds.exists(v.id) ? forBoundIds.get(v.id) : 0) + 1);
                    scanFor(it, inFor);
                    scanFor(body, true);
                case TLocal(v) if (inFor):
                    readsInFor.set(v.id, (readsInFor.exists(v.id) ? readsInFor.get(v.id) : 0) + 1);
                case _:
                    haxe.macro.TypedExprTools.iter(node, child -> scanFor(child, inFor));
            }
        }
        scanFor(root, false);
        for (id in forBoundIds.keys()) {
            final total = counts.exists(id) ? counts.get(id) : 0;
            final inside = readsInFor.exists(id) ? readsInFor.get(id) : 0;
            if (total > 0 && total == inside)
                forSharedLocals.set(id, true);
        }
#if boring_fold_debug
        if (unusedLocalIds.keys().hasNext())
            Sys.stderr().writeString("RSCANDUMP n=" + Lambda.count(unusedLocalIds) + "\n");
#end
    }

    /**
        Counted loops arrive as hidden counter declarations plus a while;
        when the typer adopts the user's own declaration as that counter,
        the emitted `for index in ..` rebinds the name and the body's
        increment disappears into the stride, so the declaration must not
        carry `mut`. Records every interval counter id.
        (IntervalCounterMut)
    **/
    function scanIntervalCounters(root:TypedExpr):Void {
        final totalWrites:Map<Int, Int> = [];
        final claimedWrites:Map<Int, Int> = [];
        final claimed:Map<Int, Bool> = [];
        function countWrites(node:TypedExpr, id:Null<Int>, into:Map<Int, Int>):Void {
            switch (node.expr) {
                case TBinop(op = OpAssign | OpAssignOp(_), t, _):
                    switch (stripWrap(t).expr) {
                        case TLocal(v) if (id == null || v.id == id):
                            into.set(v.id, (into.exists(v.id) ? into.get(v.id) : 0) + 1);
                        case _:
                    }
                case TUnop(OpIncrement | OpDecrement, _, t):
                    switch (stripWrap(t).expr) {
                        case TLocal(v) if (id == null || v.id == id):
                            into.set(v.id, (into.exists(v.id) ? into.get(v.id) : 0) + 1);
                        case _:
                    }
                case _:
            }
            haxe.macro.TypedExprTools.iter(node, child -> countWrites(child, id, into));
        }
        function walk(node:TypedExpr):Void {
            final loop = matchInterval(node);
            if (loop != null) {
                claimed.set(loop.counter.id, true);
                claimed.set(loop.index.id, true);
                countWrites(node, loop.counter.id, claimedWrites);
                for (b in loop.body)
                    walk(b);
                return;
            }
            switch (node.expr) {
                case TBlock(stmts):
                    for (s in regroupLoops(stmts))
                        walk(s);
                case TIf(_, t, f):
                    if (t != null)
                        walk(t);
                    if (f != null)
                        walk(f);
                case TWhile(_, b, _):
                    walk(b);
                case TFor(_, _, b):
                    walk(b);
                case _:
                    haxe.macro.TypedExprTools.iter(node, walk);
            }
        }
        switch (root.expr) {
            case TBlock(stmts):
                for (s in regroupLoops(stmts))
                    walk(s);
            case _: walk(root);
        }
        // Mut is dropped only when EVERY write of the local is a claimed
        // loop's own counter increment: those disappear into the emitted
        // `for` stride. A write anywhere else needs the mutable binding.
        countWrites(root, null, totalWrites);
        for (id in claimed.keys()) {
            final total = totalWrites.exists(id) ? totalWrites.get(id) : 0;
            final inClaim = claimedWrites.exists(id) ? claimedWrites.get(id) : 0;
            if (total > 0 && total == inClaim)
                intervalCounterLocals.set(id, true);
        }
    }

    /**
        A conditional arm that names a local as a bare value of owned
        non-Copy type moves the local's storage; a later mention of the
        local then trips E0382. Statement order follows preorder: a node's
        subtree occupies a contiguous index range, so a mention whose index
        exceeds the conditional's range is a later read. The conditional's
        own condition sits inside the range (it evaluates before the arms).
        (BranchArmMoveClone)
    **/
    function scanBranchArmMoves(root:TypedExpr):Void {
        final starts = new haxe.ds.ObjectMap<TypedExpr, Int>();
        final ends = new haxe.ds.ObjectMap<TypedExpr, Int>();
        var counter = 0;
        function number(node:TypedExpr):Int {
            final start = counter++;
            starts.set(node, start);
            var end = start;
            haxe.macro.TypedExprTools.iter(node, function(child:TypedExpr):Void {
                final childEnd = number(child);
                if (childEnd > end)
                    end = childEnd;
            });
            ends.set(node, end);
            return end;
        }
        number(root);
        final sites:Array<{node:TypedExpr, id:Int}> = [];
        function collect(node:TypedExpr):Void {
            switch (node.expr) {
                case TIf(_, t, f) if (f != null):
                    for (arm in [t, f]) {
                        switch (stripWrap(arm).expr) {
                            case TLocal(l) if (!isTypeCopy(l.t)):
                                sites.push({node: node, id: l.id});
                            case _:
                        }
                    }
                case _:
            }
            haxe.macro.TypedExprTools.iter(node, collect);
        }
        collect(root);
        for (s in sites) {
            final siteEnd = ends.get(s.node);
            var found = false;
            function walk(node:TypedExpr):Void {
                if (found)
                    return;
                switch (node.expr) {
                    case TLocal(v): if (v.id == s.id && starts.get(node) > siteEnd) found = true;
                    case _:
                }
                if (!found)
                    haxe.macro.TypedExprTools.iter(node, walk);
            }
            walk(root);
            if (found)
                branchArmMoveReadsAfter.set(s.id, true);
        }
    }

    /** A local whose occurrences exceed its push occurrences is read
        somewhere outside its own push argument: that push must clone so
        the binding stays usable. (PushedThenRead) */
    function scanPushedThenRead(root:TypedExpr):Void {
        final occurrences:Map<Int, Int> = [];
        final pushOccurrences:Map<Int, Int> = [];
        function walk(e:TypedExpr):Void {
            switch (e.expr) {
                case TLocal(v):
                    occurrences.set(v.id, (occurrences.exists(v.id) ? occurrences.get(v.id) : 0) + 1);
                case TCall(fn, args):
                    final isPush = switch (stripWrap(fn).expr) {
                        case TField(_, FInstance(_, _, cf)): cf.get().name == "push";
                        case _: false;
                    };
                    if (isPush && args.length == 1) {
                        switch (stripWrap(args[0]).expr) {
                            case TLocal(v):
                                occurrences.set(v.id, (occurrences.exists(v.id) ? occurrences.get(v.id) : 0) + 1);
                                pushOccurrences.set(v.id, (pushOccurrences.exists(v.id) ? pushOccurrences.get(v.id) : 0) + 1);
                            case _:
                        }
                    }
                    haxe.macro.TypedExprTools.iter(fn, walk);
                    for (i in 0...args.length) {
                        if (isPush && i == 0)
                            continue;
                        walk(args[i]);
                    }
                    return;
                case _:
            }
            haxe.macro.TypedExprTools.iter(e, walk);
        }
        walk(root);
        for (id in occurrences.keys()) {
            final pushCount = pushOccurrences.exists(id) ? pushOccurrences.get(id) : 0;
            if (pushCount > 0 && occurrences.get(id) > pushCount)
                pushedThenRead.set(id, true);
        }
    }

    /**
        Scalar locals assigned inside a named local function lower as
        Arc<dyn Fn>, and the Fn contract forbids assigning a captured
        binding. Each such scalar shares through Arc<Mutex> so the writes
        stay visible through the shared referent.
        (SharedClosureScalars)
    **/
    function scanSharedClosureScalars(root:TypedExpr):Void {
        function scan(e:TypedExpr):Void {
            switch (e.expr) {
                case TFunction(f):
                    final bound:Map<Int, Bool> = [];
                    for (arg in f.args)
                        bound.set(arg.v.id, true);
                    function walk(x:TypedExpr):Void {
                        switch (x.expr) {
                            case TVar(v, init):
                                if (init != null)
                                    walk(init);
                                bound.set(v.id, true);
                                return;
                            case TLocal(v):
                                // Any captured-and-reassigned binding needs
                                // the shared referent: the Fn contract
                                // forbids assigning a captured binding of
                                // every type; the earlier rule covered scalars only.
                                // (SharedClosureScalars)
                                if (!bound.exists(v.id) && mutated.exists(v.id))
                                    sharedClosureScalars.set(v.id, true);
                            case _:
                        }
                        haxe.macro.TypedExprTools.iter(x, walk);
                    }
                    walk(f.expr);
                case _:
            }
            haxe.macro.TypedExprTools.iter(e, scan);
        }
        scan(root);
    }

    /**
        An `if (X == null) { continue; }` statement inside a loop proves X
        holds Some for the rest of that iteration. A following
        `let v = X;` copy stores the Option value, and a call slot that
        expects the inner value unwraps the copy through the proven
        mechanism. (ContinueNullGuards)
    **/
    /** Whether the tree assigns the local (a re-binding null guard body). */
    function containsAssignTo(e:TypedExpr, id:Int):Bool {
        var hit = false;
        function walk(x:TypedExpr):Void {
            if (hit)
                return;
            switch (stripWrap(x).expr) {
                case TBinop(OpAssign, target, _) if (switch (stripWrap(target).expr) {
                        case TLocal(v): v.id == id;
                        case _: false;
                    }):
                    hit = true;
                    return;
                case _:
            }
            haxe.macro.TypedExprTools.iter(x, walk);
        }
        walk(e);
        return hit;
    }

    /**
        A cursor local starts from a nullable proven source and is later
        re-assigned an Option-typed expression, so it must keep the Option
        shape: the branches that lower the value to its scalar skip it. (CursorPattern)
    **/
    function scanCursorLocals(root:TypedExpr):Void {
        function scan(e:TypedExpr):Void {
            switch (stripWrap(e).expr) {
                case TBinop(OpAssign, target, rhs):
                    if (isNullType(rhs.t))
                        switch (stripWrap(target).expr) {
                            case TLocal(v): cursorLocals.set(v.id, true);
                            case _:
                        }
                case _:
            }
            haxe.macro.TypedExprTools.iter(e, scan);
        }
        scan(root);
    }

    /** The local/field name chain of an access path, outermost first. */
    function accessChainOf(x:TypedExpr):Null<Array<String>> {
        final names:Array<String> = [];
        var cur = x;
        while (true) {
            switch (stripWrap(cur).expr) {
                case TField(sub, fa):
                    names.unshift(fieldName(fa));
                    cur = sub;
                case TLocal(v):
                    names.unshift(v.name);
                    return names;
                case TConst(TThis):
                    return names;
                case _:
                    return null;
            }
        }
        return null;
    }

    /** Whether the tree references an access path ending in the chain. */
    function containsAccess(e:TypedExpr, chain:Array<String>):Bool {
        var hit = false;
        function walk(x:TypedExpr):Void {
            if (hit)
                return;
            var cursor = x;
            var depth = 0;
            while (depth < chain.length) {
                switch (stripWrap(cursor).expr) {
                    case TField(sub, fa) if (fieldName(fa) == chain[chain.length - 1 - depth]):
                        cursor = sub;
                        depth++;
                    case TLocal(v) if (v.name == chain[chain.length - 1 - depth] && depth == chain.length - 1):
                        hit = true;
                        return;
                    case _:
                        return;
                }
            }
            if (depth == chain.length)
                hit = true;
            haxe.macro.TypedExprTools.iter(x, walk);
        }
        walk(e);
        return hit;
    }

    function scanContinueNullGuards(root:TypedExpr):Void {
        function containsEarlyExit(e:TypedExpr):Bool {
            if (e.expr.match(TContinue) || e.expr.match(TReturn(_)) || e.expr.match(TBreak))
                return true;
            var found = false;
            haxe.macro.TypedExprTools.iter(e, function(x) {
                if (!found)
                    found = containsEarlyExit(x);
            });
            return found;
        }
        function scan(e:TypedExpr):Void {
            switch (stripWrap(e).expr) {
                case TIf(cond, then, null):
                    // The guard may be a disjunction whose first term is the
                    // null check (`X == null || ...`): the chain short-circuits
                    // to the early exit when X is null, so the later terms see
                    // the inner value. (ContinueNullGuards)
                    var first = stripWrap(cond);
                    while (true) {
                        switch (stripWrap(first).expr) {
                            case TBinop(OpBoolOr, ll, _): first = ll;
                            case _: break;
                        }
                    }
                    switch (stripWrap(first).expr) {
                        case TBinop(OpEq, l, r):
                            final subject = isTNull(l) ? r : (isTNull(r) ? l : null);
                            if (subject != null && containsEarlyExit(then))
                                provenContinueSubjects.set(subjectTextOf(subject), true);
                        case TBinop(OpNotEq, l, r):
                            final subject = isTNull(l) ? r : (isTNull(r) ? l : null);
                            if (subject != null && containsEarlyExit(then))
                                provenContinueSubjects.set(subjectTextOf(subject), true);
                        case TBinop(OpNotEq, l, r):
                            // `if (X != null) { ...X... }` proves X for the
                            // guarded block: register the subject so the
                            // guarded references render the inner value. The
                            // containment test walks the AST field chain, so
                            // rendering the block here would advance the
                            // naming counters as a side effect.
                            final subject = isTNull(l) ? r : (isTNull(r) ? l : null);
                            if (subject != null) {
                                final chain = accessChainOf(subject);
                                if (chain != null && containsAccess(then, chain))
                                    provenContinueSubjects.set(subjectTextOf(subject), true);
                            }
                        case _:
                    }
                case _:
            }
            haxe.macro.TypedExprTools.iter(e, scan);
        }
        scan(root);
    }

    function functionLiteralNamed(name:String, f:TFunc, functionType:Null<Type>):String {
        final previous = currentLocalName;
        currentLocalName = name;
        final result = functionLiteral(f, functionType);
        currentLocalName = previous;
        return result;
    }

    function functionValueLiteralNamed(name:String, f:TFunc, functionType:Null<Type>):String {
        final previous = currentLocalName;
        currentLocalName = name;
        final result = functionValueLiteral(f, functionType);
        currentLocalName = previous;
        return result;
    }

    function isFallibleCallee(c:Ref<ClassType>, cf:Ref<ClassField>, isStatic:Bool):Bool {
        final name = cf.get().name;
        if (RustEmissionState.runtimeShimIsFallible(name))
            return true;
        if (name == "require" && c.get().module == "registry.Semver")
            return true;
        // An interface method is fallible when any implementation throws; the
        // trait signature carries the Result, so the call site propagates.
        if (!isStatic && c.get().isInterface) {
            final shape = state.interfaceMethodShapes.get(RustEmissionState.interfaceMethodKey(c.get().module, c.get().name, name));
            if (shape != null && shape.isFallible)
                return true;
        }
        return state.funcErrorEnums.exists(RustEmissionState.funcKey(c.get().module, name, isStatic));
    }

    function isDiscardedUnitResultCall(e:TypedExpr, fn:TypedExpr):Bool {
        if (!isVoidType(e.t))
            return false;
        return switch (stripWrap(fn).expr) {
            case TField(_, FInstance(c, _, cf)):
                isFallibleCallee(c, cf, false);
            case TField(_, FStatic(c, cf)):
                isFallibleCallee(c, cf, true);
            case _: false;
        };
    }

    function isFallibleConstructor(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TNew(c, _, _):
                state.funcErrorEnums.exists(RustEmissionState.funcKey(c.get().module, "new", false));
            case _: false;
        };
    }

    /** A `new ConcreteClass(...)` expression whose class is not itself an interface. */
    function isConcreteConstructor(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TNew(c, _, _): !c.get().isInterface;
            case _: false;
        };
    }

    function normalizeConstructorResult(e:TypedExpr, rendered:String):String {
        if (!isFallibleConstructor(e) || StringTools.endsWith(rendered, "?") || StringTools.endsWith(rendered, ".unwrap()"))
            return rendered;
        return isFallible ? rendered + "?" : "(" + rendered + ").unwrap()";
    }

    /**
        normalizeFallibleCallArgument: a factory call can be typed by Haxe as
        its successful payload while Rust still sees the emitted Result. The
        argument boundary must resolve that Result before a constructor or
        other value slot receives it. This keeps the decision tied to the
        callee's fallibility registry and its typed call shape.
    **/
    function normalizeFallibleCallArgument(e:TypedExpr, rendered:String):String {
        final suffix = switch (stripWrap(e).expr) {
            case TCall(fn, _):
                switch (stripWrap(fn).expr) {
                    case TField(_, FInstance(c, _, cf)):
                        isFallibleCallee(c, cf, false) ? errorPropagationSuffix(c, cf, false) : "";
                    case TField(_, FStatic(c, cf)):
                        isFallibleCallee(c, cf, true) ? errorPropagationSuffix(c, cf, true) : "";
                    case TLocal(v):
                        fallibleLocalFunctionErrors.exists(v.id) ? (isFallible ? "?" : ".unwrap()") : "";
                    case _: "";
                }
            case _: "";
        };
        if (suffix == "" || rendered.indexOf("?") >= 0 || StringTools.endsWith(rendered, suffix)
            || StringTools.endsWith(rendered, ".unwrap()"))
            return rendered;
        return rendered + suffix;
    }

    function newExpr(c:Ref<ClassType>, params:Array<Type>, args:Array<TypedExpr>):String {
        final cls = c.get();
        final valueType = ValueTypeSupport.markedAbstractOfClass(cls);
        if (valueType != null) {
            imports.requireType(valueType.module, valueType.name);
            final rendered = ctorCallArgs(cls, args);
            if (ValueTypeSupport.constructorThrows(valueType)) {
                return valueType.name + "::new(" + rendered + ")" + (isFallible ? "?" : ".unwrap()");
            }
            return valueType.name + "(" + rendered + ")";
        }
        final path = cls.pack.length == 0 ? cls.name : cls.pack.join(".") + "." + cls.name;
        switch (path) {
            case "std.StringBuf" | "StringBuf":
                return "Vec::<u16>::new()";
            case "haxe.ds._Map.Map_Impl_":
                imports.require("std::collections::HashMap");
                return "HashMap::new()";
            case "haxe.io.BytesBuffer":
                imports.requireType(path, "BytesBuffer");
                return "BytesBuffer::new()";
            case "Array":
                return "Vec::new()";
            case _:
                if (args.length == 1 && state.messageOnlyExceptions.exists(cls.module)) {
                    imports.requireType(cls.module, cls.name);
                    return cls.name + "::new(" + exceptionMessageArg(args[0]) + ")";
                }
                if (args.length == 1 && state.exceptionPayloads.exists(cls.module)) {
                    return exceptionVariant(cls, args[0]);
                }
                imports.requireType(cls.module, cls.name);
                // The generic resident tables construct with explicit
                // type arguments: the empty-array arguments leave the
                // parameters otherwise unconstrained.
                final genericStr = params.length > 0 ? "::<" + [for (p in params) types.of(p)].join(", ") + ">" : "";
                // A throwing constructor lowers through the fallibility
                // machinery: `?` propagates inside a fallible function or
                // a try-region closure, and an infallible context
                // unwraps (feature spec 27).
                final ctorFallible = state.funcErrorEnums.exists(RustEmissionState.funcKey(cls.module, "new", false));
                final q = ctorFallible ? (isFallible ? "?" : ".unwrap()") : "";
                return cls.name + genericStr + "::new(" + ctorCallArgs(cls, args) + ")" + q;
        }
    }

    function isMapType(t:Type):Bool {
        return PolicyQueries.isMapType(t);
    }

    function isMapImplementation(cls:ClassType):Bool {
        return PolicyQueries.isMapImplementation(cls);
    }

    function mapBackingReceiver(e:TypedExpr):Null<TypedExpr> {
        return PolicyQueries.mapBackingReceiver(e);
    }

    function isMapBackingType(t:Type):Bool {
        return PolicyQueries.isMapBackingType(t);
    }

    function mapAssignment(e:TypedExpr):Null<{receiver:TypedExpr, key:TypedExpr}> {
        return PolicyQueries.mapAssignment(e);
    }

    function isHasOwnPropertyValue(e:TypedExpr):Bool {
        return PolicyQueries.isHasOwnPropertyValue(e);
    }

    function mapHasOwnPropertyCall(fn:TypedExpr, args:Array<TypedExpr>):Null<String> {
        if (args.length != 2)
            return null;
        return switch (stripWrap(fn).expr) {
            case TField(subject, FInstance(_, _, cf)) if (cf.get().name == "call" && isHasOwnPropertyValue(subject)):
                final receiver = mapBackingReceiver(args[0]);
                receiver == null ? null : expr(receiver)
                + ".contains_key(&"
                + rustMapKey(args[1])
                + ")";
            case _: null;
        };
    }

    function rustMapKey(e:TypedExpr):String {
        final rendered = expr(e);
        return isStringType(e.t) || isStringLiteral(e) ? rendered + ".to_string()" : rendered;
    }

    function isStringLiteral(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TConst(TString(_)): true;
            case _: false;
        };
    }

    /** Whether rendered text is a bare Rust string literal. */
    function isStringLiteralText(text:String):Bool {
        return StringTools.startsWith(text, "\"") && StringTools.endsWith(text, "\"");
    }

    function rustMapValue(e:TypedExpr):String {
        final rendered = expr(e);
        return isStringType(e.t) ? switch (stripWrap(e).expr) {
            case TConst(TString(_)): rendered + ".to_string()";
            case _: rendered;
        } : rendered;
    }

    /**
        Constructor arguments (feature spec 27): a String parameter takes
        &str, so a heap String argument borrows through .as_str() while a
        literal keeps its own static borrowing and a parameter of the
        enclosing function is already &str (`.as_str()` on &str is
        unstable); every other parameter renders as the plain expression,
        the convention the resident tables already construct under.
    **/
    function isSelfEnumField(expected:Null<Type>, en:EnumType):Bool {
        if (expected == null)
            return false;
        return switch (Context.follow(expected)) {
            case TEnum(e, _): final t = e.get(); t.module == en.module && t.name == en.name;
            case _: false;
        };
    }

    function ownedConstructorArg(expected:Null<Type>, arg:TypedExpr, constructed:Null<EnumType> = null, rendered:Null<String> = null):String {
        var text = rendered != null ? rendered : expr(arg);
        if (constructed != null && isSelfEnumField(expected, constructed))
            return "Box::new(" + text + ")";
        if (expected == null)
            return text;
        if (isStringType(expected) && isStringType(arg.t)) {
            if (!StringTools.endsWith(text, ".to_string()"))
                text += ".to_string()";
            return text;
        }
        // ReadOnlyArray literals and direct static arrays are emitted as Rust
        // arrays, while an owned constructor slot is Vec<T>.
        if (StaticFieldHelper.isArrayType(expected) && StaticFieldHelper.isArrayType(arg.t)) {
            if (!StringTools.endsWith(text, ".to_vec()"))
                return text + ".to_vec()";
        }
        // A value expression can still be rendered as a borrow after a
        // field or parameter read. Clone the referent to produce the
        // requested owned type.
        if (!isTypeCopy(expected) && StringTools.startsWith(text, "&")) {
            if (!StringTools.endsWith(text, ".clone()") && !StringTools.endsWith(text, ".to_vec()"))
                text = "(*" + text + ").clone()";
        }
        // Haxe constructor arguments are evaluated as reads from shared
        // object state. Rust's value slots would otherwise move a non-Copy
        // local or field, making a later argument (or a later loop iteration)
        // use the moved value. Clone only direct reusable reads; temporary
        // producers already have fresh ownership and must remain untouched.
        if (!isTypeCopy(expected) && isReusableOwnedRead(arg)
            && !StringTools.startsWith(text, "&")
            && !StringTools.endsWith(text, ".clone()")
            && !StringTools.endsWith(text, ".to_vec()")
            && !StringTools.endsWith(text, ".to_string()")) {
            text = ownedReadCloneText(arg, text);
        }
        return text;
    }

    /**
        ownedReadCloneText: clone a reusable read into an owned value slot. A
        borrowed loop item names a Rust reference, so its referent dereferences
        before the clone; a rendered reference dereferences the same way.
    **/
    function ownedReadCloneText(arg:TypedExpr, text:String):String {
        switch (stripWrap(arg).expr) {
            case TLocal(v) if (borrowedLoopVarIds.exists(v.id)):
                return ownedLoopItemCloneText(arg.t, text);
            case _:
        }
        return StringTools.startsWith(text, "&") ? "(*" + text + ").clone()" : "(" + text + ").clone()";
    }

    /**
        ownedLoopItemCloneText: a borrowed loop item names a Rust reference.
        Its referent dereferences before the clone only when the element type
        derives Clone; otherwise the reference-clone form stays, matching the
        element type's own derive decision.
    **/
    function ownedLoopItemCloneText(t:Type, text:String):String {
        return isCloneableValue(t) ? "(*" + text + ").clone()" : "(" + text + ").clone()";
    }

    /**
        isCloneableValue: whether the lowered value type derives Clone, the
        same gate the declaration emitter uses. Only class instances need the
        query; every other value shape is clone-capable on its own.
    **/
    function isCloneableValue(t:Type):Bool {
        final inner = isNullType(t) ? getNullInnerType(t) : t;
        return switch (Context.follow(inner)) {
            case TInst(c, _): RustDecl.isCloneableClass(c.get(), state.sealedCloneInterfaces);
            case _: true;
        };
    }

    /**
        Materializes a coalescing default at a constructor call site. The
        default expression may read earlier constructor parameters, so each
        rendered argument text is registered by parameter name for the
        duration of the default. A nested constructor argument renders its own
        defaults and restores this table around itself, so the enclosing site
        keeps every earlier parameter resolvable.
    **/
    function constructorDefaultAtCall(cls:ClassType, args:Array<TypedExpr>, paramTypes:Array<Type>, paramNames:Array<String>,
            coalescing:DefaultArgExpander.CoalescingDefaultValue, parameterType:Type):String {
        final savedSubstitutions = defaultParameterSubstitutions.copy();
        defaultParameterSubstitutions.clear();
        for (j in 0...args.length) {
            if (j >= paramNames.length)
                continue;
            final prior = isNullLiteral(args[j]) ? DefaultArgExpander.defaultAt(cls, "new", j) : null;
            final argText = expr(args[j]);
            final priorText = prior == null ? (isNullType(paramTypes[j]) && StringTools.startsWith(argText, "Some(")
                ? argText.substr(5, argText.length - 6) : argText) : switch (prior) {
                case VCoalescing(value): coalescingDefaultText(value, getNullInnerType(paramTypes[j]), false);
                default: defaultArgText(prior, paramTypes[j]);
            };
            defaultParameterSubstitutions.set(paramNames[j], priorText);
        }
        final rendered = coalescingDefaultText(coalescing, getNullInnerType(parameterType), true);
        defaultParameterSubstitutions.clear();
        for (name => text in savedSubstitutions)
            defaultParameterSubstitutions.set(name, text);
        return rendered;
    }

    function ctorCallArgs(cls:ClassType, args:Array<TypedExpr>):String {
        final fnType = cls.constructor != null ? cls.constructor.get().type : null;
        final paramTypes = fnType != null ? switch (Context.follow(fnType)) {
            case TFun(pargs, _): [for (p in pargs) p.t];
            case _: [];
        } : [];
        final paramNames = fnType != null ? switch (Context.follow(fnType)) {
            case TFun(pargs, _): [for (p in pargs) p.name];
            case _: [];
        } : [];
        final out:Array<String> = [];
        for (i in 0...args.length) {
            final arg = args[i];
            var argStr = expr(arg);
            // A proven-non-null nullable local feeding a non-null
            // constructor parameter unwraps the Option at the boundary so
            // the payload enters the slot; the payload clones because the
            // local stays readable. Mirrors the call-argument bridge.
            // (ProvenNonNullSlotUnwrap)
            if (i < paramTypes.length && paramTypes[i] != null && !isNullType(paramTypes[i])
                && (isNullType(arg.t) || isImplicitNullableLocal(arg))) {
                final proven = switch (stripWrap(arg).expr) {
                    case TLocal(v):
                        provenNonNullVarIds.exists(v.id)
                            || (provenContinueSubjects.exists(subjectTextOf(arg))
                                && !StringTools.startsWith(argStr, "*")
                                && !StringTools.startsWith(argStr, "(*")
                                && !StringTools.contains(argStr, ".as_ref().unwrap()")
                                && !StringTools.endsWith(argStr, ".unwrap_or(0)")
                                && !StringTools.endsWith(argStr, ".unwrap_or(0.0)"));
                    case _: provenMapGet(arg);
                };
                if (proven && RustShapeParse.shapeOf(argStr) != RustShape.ShapeBare) {
                    final inner = getNullInnerType(arg.t);
                    // A numeric scalar keeps the null-to-zero bridge: the
                    // final numeric boundary appends unwrap_or(0) for the
                    // nullable argument, and the two extractions would
                    // stack. (ProvenNonNullSlotUnwrap)
                    if (!isNumericScalarType(inner)) {
                        final ref = "(" + argStr + ").as_ref().unwrap()";
                        argStr = isTypeCopy(inner) ? "*" + ref : ref + ".clone()";
                    }
                }
            }
            if (i < paramTypes.length) {
                final pt = paramTypes[i];
                // A narrowed operand renders the dereferenced match binding;
                // a nullable constructor parameter still needs the Option
                // shape. (NarrowedNullableParam)
                if (isNullType(pt) && StringTools.startsWith(argStr, "*")
                    && !StringTools.startsWith(argStr, "*("))
                    argStr = "Some(" + argStr + ")";
                // A has-guarded zero ternary argument (both arms render the
                // inner value) into a nullable constructor slot wraps in
                // Some. (NarrowedNullableParam)
                if (isNullType(pt) && !isNullType(args[i].t)) {
                    switch (stripWrap(args[i]).expr) {
                        case TIf(_, t2, f2):
                            final tt = expr(t2);
                            final et = expr(f2);
                            final zeroElse = (et == "0" || et == "0.0f64" || et == "0.0"
                                || et == "(0 as f64)" || et == "(0.0f64)");
                            if (StringTools.contains(tt, ".unwrap()") && zeroElse
                                && !StringTools.startsWith(argStr, "Some("))
                                argStr = "Some(" + argStr + ")";
                        case _:
                    }
                }
                // A fallible constructor used as an argument must resolve its
                // Result before the value reaches the parameter. Interface
                // parameters then box the successful concrete value below.
                argStr = normalizeConstructorResult(arg, argStr);
                argStr = normalizeFallibleCallArgument(arg, argStr);
                final parameterName = i < paramNames.length ? paramNames[i] : null;
                final coalescing = parameterName == null ? null : DefaultArgExpander.coalescingDefaultForParam(cls, "new", parameterName);
                if (coalescing != null && isNullLiteral(arg)) {
                    out.push(constructorDefaultAtCall(cls, args, paramTypes, paramNames, coalescing, pt));
                    continue;
                }
                final registered = DefaultArgExpander.defaultAt(cls, "new", i);
                if (registered != null && isNullLiteral(arg)) {
                    if (isCoalescingDefault(registered)) {
                        out.push(argStr);
                        continue;
                    }
                    final d = defaultArgText(registered, pt);
                    out.push(isNullType(pt) && !isCoalescingDefault(registered) && registered != VNull ? "Some(" + d + ")" : d);
                    continue;
                }
                if (registered != null && isNullType(arg.t) && !isNullType(pt) && !isCoalescingDefault(registered)) {
                    out.push("(" + argStr + ").unwrap_or(" + defaultArgText(registered, getNullInnerType(pt)) + ")");
                    continue;
                }
                if (isNullType(pt) && isNullType(arg.t)
                    && (isNonNullRenderedLocal(arg) || isNonNullRenderedConditional(arg))
                    && !StringTools.startsWith(argStr, "Some(") && argStr != "None") {
                    // A null-coalesced local or inline ternary usually renders
                    // its inner value (the declaration collapsed the Option);
                    // an Option parameter re-wraps it so the slot's declared
                    // type matches. A local whose null branch stays null
                    // renders as Option already, so it passes through. A
                    // non-Copy payload clones so the source stays usable.
                    final inner = getNullInnerType(pt);
                    if (isStringType(inner) && !StringTools.endsWith(argStr, ".to_string()"))
                        out.push("Some(" + argStr + ".to_string())");
                    else if (isTypeCopy(inner))
                        out.push("Some(" + argStr + ")");
                    else
                        out.push("Some(" + ownedNullableReadText(argStr) + ")");
                    continue;
                }
                if (isNullType(pt) && isNullType(arg.t) && narrowedSubject(arg) != null) {
                    // A narrowed Option binding renders as a reference to the
                    // inner value (the match binding); an Option parameter
                    // re-wraps it so the slot's declared type matches. Copy
                    // inners dereference, owned inners clone the referent.
                    final inner = getNullInnerType(pt);
                    if (isTypeCopy(inner))
                        out.push("Some(*" + narrowedSubject(arg) + ")");
                    else
                        out.push("Some((*" + narrowedSubject(arg) + ").clone())");
                    continue;
                }
                // A nullable argument whose read renders no Option
                // construction (no Some/None, no composite of Option arms)
                // re-wraps at the Option slot. The decision reads the
                // rendered text, so it matches every other boundary on the
                // same expression. (TypedSlotBoundary, ShapeParse)
                if (isNullType(pt) && isNullType(arg.t)
                    && !StringTools.startsWith(argStr, "Some(") && argStr != "None"
                    && renderedArgShape(argStr, arg) == RustShape.ShapeBare) {
                    if (isTypeCopy(getNullInnerType(pt)))
                        out.push("Some(" + argStr + ")");
                    else
                        out.push("Some(" + ownedNullableReadText(argStr) + ")");
                    continue;
                }
                if (isNullType(pt) && isStringType(getNullInnerType(pt)) && isNullType(arg.t)) {
                    // A nullable-typed conditional whose arms are both
                    // non-null renders a plain String; wrap in Some at the
                    // Option parameter boundary. A nullable local or field
                    // keeps its Option shape and clones.
                    if (isNonNullRenderedConditional(arg))
                        out.push("Some(" + argStr + ")");
                    else
                        out.push(argStr + ".clone()");
                    continue;
                }
                if (isNullType(pt) && !isNullType(arg.t)) {
                    // A nullable constructor parameter takes an Option; a
                    // null literal already renders None, any other
                    // argument wraps.
                    if (argStr == "None" || StringTools.startsWith(argStr, "Some(")) {
                        out.push(argStr);
                        continue;
                    }
                    final inner = switch (stripWrap(arg).expr) {
                        case TConst(TString(s)): quoteString(s) + ".to_string()";
                        case _ if (isStringType(getNullInnerType(pt)) && isStringType(arg.t)):
                            StringTools.endsWith(argStr, ".to_string()") ? argStr : "(" + argStr + ").to_string()";
                        case _ if (isFloatType(getNullInnerType(pt)) && isIntType(emittedType(arg))):
                            intToFloatText(argStr);
                        case _ if (isOwnedVecType(getNullInnerType(pt))):
                            // A direct array static is a Rust array and a
                            // borrowed array parameter is a &Vec view; the
                            // nullable Vec slot owns its elements, so the
                            // Some payload converts once at the boundary.
                            nullableArrayPayload(arg, argStr);
                        case _:
                            if (isInterfaceType(getNullInnerType(pt)) && !isInterfaceType(arg.t))
                                renderValueForType(getNullInnerType(pt), arg, argStr);
                            else if (isReusableNullableRead(pt, arg, argStr))
                                ownedNullableReadText(argStr);
                            else
                                argStr;
                    };
                    out.push("Some(" + inner + ")");
                    continue;
                }
                if (isInterfaceType(pt)) {
                    out.push(renderValueForType(pt, arg, argStr));
                    continue;
                }
                if (stringLikeType(pt) && stringLikeType(arg.t)) {
                    out.push(switch (stripWrap(arg).expr) {
                        case TConst(TString(_)): argStr;
                        case _ if (nullableStringViewArg(arg)): "(" + expr(arg) + ").as_deref().unwrap_or(\"\")";
                        case TLocal(v) if (isBorrowedParamLocal(v)): argStr;
                        case _: argStr + ".as_str()";
                    });
                    continue;
                }
                final bytesParam = switch (Context.follow(pt)) {
                    case TInst(c, _): c.get().module == "haxe.io.Bytes";
                    case TType(d, _): d.get().module == "haxe.io.Bytes";
                    case _: false;
                };
                if (bytesParam) {
                    // A Bytes parameter renders as &[u8] (RustType.isParam);
                    // an owned expression (a producer call, an owned local)
                    // borrows with &, while a borrowed parameter local stays
                    // unchanged. renderCallArgs applies the same prefix at
                    // ordinary call sites.
                    final borrowedLocal = switch (stripWrap(arg).expr) {
                        case TLocal(v): isBorrowedLocal(v);
                        case _: false;
                    };
                    if (!borrowedLocal && !StringTools.startsWith(argStr, "&")) {
                        out.push("&" + argStr);
                        continue;
                    }
                }
                if (i < paramTypes.length) {
                    final pt = paramTypes[i];
                    if (isFloatType(pt) && isIntType(emittedType(arg))) {
                        argStr = numericAssignmentValue(pt, arg, argStr);
                    }
                }
            }
            // Constructor parameters are value slots unless their declared
            // type explicitly lowers to a borrow.  Keep this final boundary
            // adaptation here so record/Vec reads do not leak `&T` into a T.
            // An argument whose rendered text evaluates to the Option shape
            // (a wrapped ternary, an Option-returning read) enters a
            // non-null scalar constructor slot; the boundary unwraps it.
            // The decision reads the rendered text itself, so it agrees
            // with every other boundary on the same expression.
            // (ScalarSlotUnwrap, ShapeParse)
            if (i < paramTypes.length
                && !isNullType(paramTypes[i])
                && isNumericScalarType(paramTypes[i])
                && renderedArgShape(argStr, arg) == RustShape.ShapeOption)
                argStr = postfixAdapt(argStr, ".unwrap()");
            if (i < paramTypes.length)
                out.push(numericAssignmentValue(paramTypes[i], arg, ownedConstructorArg(paramTypes[i], arg, null, argStr), null, true));
            else
                out.push(argStr);
        }
        // A Haxe constructor call may omit trailing optional parameters; the
        // Rust signature carries no defaults, so the callee's registered
        // defaults must be materialized here at the call site.
        final omitted = DefaultArgExpander.omittedCallDefaults(cls.module, "new", args.length, cls.name);
        if (omitted != null) {
            for (o in omitted)
                out.push(coalescingDefaultText(o.value, o.type, isNullType(o.type)));
        }
        return out.join(", ");
    }

    function isCoalescingDefaultAt(cls:ClassType, index:Int):Bool
        return switch (DefaultArgExpander.defaultAt(cls, "new", index)) {
            case VCoalescing(_): true;
            case _: false;
        };

    function isCoalescingDefault(v:DefaultArgExpander.DefaultArgValue):Bool
        return switch (v) {
            case VCoalescing(_): true;
            case _: false;
        };

    function isNullLiteral(e:TypedExpr):Bool
        return switch (stripWrap(e).expr) {
            case TConst(TNull): true;
            case _: false;
        };

    function defaultArgText(v:DefaultArgExpander.DefaultArgValue, t:Type):String
        return switch (v) {
            case VInt(x): isFloatType(t) ? intToFloatText(Std.string(x)) : Std.string(x);
            case VFloat(x): x;
            case VString(x): quoteString(x) + ".to_string()";
            case VBool(x): x ? "true" : "false";
            case VNull: "None";
            case VEnum(e, f): e.get().name + "::" + RustImports.toSnakeCase(f.name);
            case VCoalescing(_): "None";
        };

    function numericAssignmentValue(expected:Type, actual:TypedExpr, rendered:String, targetOverride:Null<String> = null, signedBoundary:Bool = false):String {
        if (isFloatType(expected) && isIntType(emittedType(actual)))
            return intToFloatText(rendered);
        // A nullable target holds an Option; the rendered value is already
        // in the Option domain (a null literal renders None, a nullable
        // expression keeps its Option shape), so no null-to-zero bridge or
        // bit reinterpretation applies at this boundary.
        if (isNullType(expected))
            return rendered;
        if (!isIntType(expected))
            return rendered;
        final target = targetOverride != null ? targetOverride : types.of(expected, false);
        if (isNullType(actual.t)) {
            // An enclosing null guard already collapsed the Option: the
            // operand renders as the match binding, a reference to the
            // inner scalar, so the null-to-zero bridge dereferences the
            // match binding.
            final narrowed = narrowedSubject(actual);
            if (narrowed != null) {
                optionNarrowingHitCount++;
                final deref = "*" + narrowed;
                if ((target == "u32" || target == "i32") && (RuntimeResidents.isResident(imports.selfModule) ? "i32" : "u32") == target) {
                    return deref;
                }
                return RustConversions.reinterpret("(" + deref + ")", target);
            }
            final castAt = rendered.indexOf(" as ");
            final base = castAt >= 0 ? rendered.substr(0, castAt) : rendered;
            // A null-coalescing local materialized the inner value into a
            // scalar, so a read is already the inner domain and the
            // null-to-zero bridge would call unwrap_or on a non-Option.
            // Covers the coalesced-local argument family.
            if (isNullableCollapsedLocal(actual)) {
                final collapsedDomain = RuntimeResidents.isResident(imports.selfModule) ? "i32" : "u32";
                if ((target == "u32" || target == "i32") && collapsedDomain == target)
                    return base;
                return RustConversions.reinterpret("(" + base + ")", target);
            }
            // A collapsed Null<Int> renders its inner scalar; when that
            // scalar's domain is already the assignment target the
            // unwrap alone suffices.
            if ((target == "u32" || target == "i32") && isIntType(getNullInnerType(actual.t))) {
                final innerDomain = RuntimeResidents.isResident(imports.selfModule) ? "i32" : "u32";
                if (innerDomain == target) {
                    // Parentheses stay only when the base carries top-level
                    // operators that would change `.unwrap_or` binding.
                    return isSimpleValueText(base) ? base + ".unwrap_or(0)" : "(" + base + ".unwrap_or(0))";
                }
            }
            return RustConversions.reinterpret("(" + base + ".unwrap_or(0))", target);
        }
        if (!isIntType(actual.t))
            return rendered;
        if (target == "u8") {
            final folded = constantCast(actual, "u8");
            if (folded != null)
                return folded;
            return RustConversions.truncate(rendered, "u8");
        }
        // The rendered source already carries the module's Int domain unless
        // an i32-domain local or a shim parameter overrides it; when source
        // and target agree, `(x) as T` is a no-op and drops away. A
        // byte-extract renders a u8 element read while its Haxe type stays
        // the Int domain, so it widens back through From instead.
        if (target == "u32" || target == "i32") {
            final source = resolveExprType(actual);
            // A wrapping binop of i32-domain locals renders in i32 even
            // though its Haxe type is the module Int (business u32).
            final i32Source = target == "i32" && i32LocalDomain(actual);
            // A signed rendering reaching a u32 constructor slot reinterprets
            // its bits; an assignment target owns its declared domain and
            // keeps the source rendering.
            final signedRender = signedBoundary && target == "u32" && rendersSignedIntArg(actual, rendered);
            if ((source == target || i32Source) && !signedRender) {
                if (rendered.indexOf(".to_be_bytes()[") >= 0)
                    return target + "::from(" + rendered + ")";
                // Fold an integer constant to a typed literal: the fold
                // keeps the binding's type anchored exactly like the old
                // `as` did (a `let x = 0; x = 256;` chain infers {integer}
                // without a typed assignment).
                final folded = constantCast(actual, target);
                if (folded != null)
                    return folded;
                return rendered;
            }
        }
        return target == "u32" || target == "i32" ? RustConversions.reinterpret(rendered, target) : rendered;
    }

    function containsNullDefault(value:DefaultArgExpander.CoalescingDefaultValue):Bool {
        // A default that can evaluate to null must not be fed to
        // unwrap_or_else (which would produce unwrap_or_else(|| None)); the
        // parameter stays Option and the null default is preserved. This is
        // the same null-capability test the struct initializer uses, so a
        // bare null default and either branch of a conditional count.
        return DefaultArgExpander.coalescingCanBeNull(value);
    }

    // Unsigned wrapping keeps the historical form: the left operand carries
    // the boundary cast, the right operand stays bare. Signed wrapping casts
    // an operand only when it crosses domains; i32-domain locals and integer
    // literals assign to i32 without a cast.

    /**
        One operand of a wrapping binop, rendered in the operation's wrap
        domain. An operand that renders in the other same-width domain
        reinterprets its bits (T5); the right operand of unsigned wrapping
        keeps its historical bare form.
    **/
    function wrappingOperand(e:TypedExpr, op:Binop, wrapDomain:String, isLeft:Bool):String {
        final text = wrappingArg(e, op, isLeft);
        // An operand already rendered in the wrap domain needs no cast: an Int
        // local or field in business is u32 and a wrapping arithmetic result
        // carries it; dropping the redundant `(x) as u32` keeps the emitted
        // code free of no-op casts. Only operands that render in a different
        // width or signedness cross the boundary here.
        if (types.of(e.t, false) == wrapDomain)
            return text;
        // A Null<Int> operand already unwrapped renders its inner scalar
        // in the module domain (unwrap_or was already applied), so the
        // Option wrapper in the static type is not the rendering domain.
        if (isNullType(e.t) && isIntType(getNullInnerType(e.t))) {
            final isParseIntLocal = switch (stripWrap(e).expr) {
                case TLocal(v): parseIntLocals.exists(v.id);
                case _: false;
            };
            final innerDomain = (isParseIntLocal || RuntimeResidents.isResident(imports.selfModule)) ? "i32" : "u32";
            if (innerDomain == wrapDomain)
                return text;
        }
        if (wrapDomain != "i32") {
            if (isParameterOfDomain(e, wrapDomain) || !isLeft)
                return text;
            return RustConversions.reinterpret(text, wrapDomain);
        }
        if (i32OperandDomain(e))
            return text;
        switch (stripWrap(e).expr) {
            case TConst(TInt(_)):
                return text;
            case _:
        }
        return RustConversions.reinterpret(text, "i32");
    }

    function isParameterOfDomain(e:TypedExpr, domain:String):Bool {
        return switch (stripWrap(e).expr) {
            case TLocal(v) if (paramVarIds.exists(v.id)): types.of(e.t) == domain;
            case _: false;
        };
    }

    function wrappingArg(e:TypedExpr, parent:Binop, isRight:Bool):String {
        final value = operand(e, parent, isRight);
        // Only strip an outer grouping when the parens actually delimit the
        // whole rendered source. A compound operand such as a length division
        // `(RANGES.to_vec().len()) / (3)` starts and ends with parens but the
        // outer pair does not wrap the entire expression; stripping them
        // would corrupt the text and glue the sibling wrapping argument into
        // a tuple.
        return StringTools.startsWith(value, "(") && StringTools.endsWith(value, ")") && matchingParens(value) ? value.substr(1, value.length - 2) : value;
    }

    function isClosureParam(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TLocal(v): closureParamIds.exists(v.id);
            case _: false;
        };
    }

    function isGenericLocal(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TLocal(v): genericParamIds.exists(v.id);
            case _: false;
        };
    }

    function i32LocalDomain(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            // A range loop variable renders as the u32 loop counter
            // (`for m in 0..bound`); the underflow-prone bound comparison
            // that marked it i32 must not leak into its arithmetic.
            case TLocal(v): i32Locals.exists(v.id) && !paramVarIds.exists(v.id) && !rangeLoopVars.exists(v.id);
            case TBinop(OpAdd | OpSub | OpMult | OpMod | OpAnd | OpOr | OpXor | OpUShr | OpShr | OpShl, left, right): i32LocalDomain(left) || i32LocalDomain(right);
            // Unary negation lowers in the signed i32 domain in a business
            // module, so a direct return or assignment reinterprets it at the
            // u32 boundary and the i32 rendering does not leak.
            case TUnop(OpNeg, _, subj): isIntType(subj.t) && !RuntimeResidents.isResident(imports.selfModule);
            case _: false;
        };
    }

    function i32OperandDomain(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TLocal(v) if (paramVarIds.exists(v.id)): types.of(e.t) == "i32";
            case TLocal(_): i32LocalDomain(e);
            case TBinop(OpAdd | OpSub | OpMult | OpMod, left, right): i32OperandDomain(left) || i32OperandDomain(right);
            case _: false;
        };
    }

    function wrappingMethod(op:Binop):String {
        return switch (op) {
            case OpAdd: "wrapping_add";
            case OpSub: "wrapping_sub";
            case OpMult: "wrapping_mul";
            case _: "";
        };
    }

    function isLocalOrFieldTarget(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TLocal(_): true;
            case TField(subj, FInstance(_, _, _)) | TField(subj, FAnon(_)): isLocalOrFieldTarget(subj);
            default: false;
        };
    }

    /** The local variable id of a plain local assignment target, else -1. */
    function stripAssignTargetLocal(e:TypedExpr):Int {
        return switch (stripWrap(e).expr) {
            case TLocal(v): v.id;
            case _: -1;
        };
    }

    function assignTarget(e:TypedExpr):String {
        return AssignTargetPlan.assignTarget(e, (arr, idx) -> optionContainerIndexAccess(arr, idx, true), e -> {
            final target = staticAssignmentTarget(e);
            return switch (e.expr) {
                case TField(_, FStatic(c, cf)): target != null ? target : staticRef(c.get(), cf.get().name);
                case _: fail(e, "assignment target has no Rust lowering");
            };
        }, (subj, kind, _) -> switch (kind) {
            case Instance(_, cf) | Anonymous(cf): expr(subj) + "." + RustImports.toSnakeCase(cf.get().name);
        },
            v -> {
            // A shared closure scalar writes through the dereferenced guard;
            // the Mutex supplies the interior mutability the Fn contract
            // forbids on captured bindings (SharedClosureScalars).
            final name = RustImports.toSnakeCase(localName(v));
            sharedClosureScalars.exists(v.id) ? "*" + name + ".lock().unwrap()" : name;
        }, (e, _) -> fail(e, "assignment target has no Rust lowering: " + Std.string(e.expr)));
    }

    function objectLiteral(e:TypedExpr, fields:Array<{name:String, expr:TypedExpr}>):String {
        final typeName = resolveTypeName(e.t);
        final fieldTypes = objectFieldTypes(e.t);
        final parts = [
            for (f in fields) {
                var val = if (isStringType(f.expr.t)) {
                    switch (stripWrap(f.expr).expr) {
                        case TConst(TString(_)): expr(f.expr) + ".to_string()";
                        case TLocal(v) if (isBorrowedParamLocal(v)): expr(f.expr) + ".to_string()";
                        case _: expr(f.expr) + ".clone()";
                    }
                } else {
                    expr(f.expr);
                };
                final fieldType = fieldTypes.get(f.name);
                // An interface-typed field is a Box slot; a concrete
                // initializer boxes at the literal, matching the interface
                // result and argument rules. The field type widens a cast
                // constructor to the interface, so the boxing decision reads
                // the cast target.
                if (fieldType != null && isInterfaceSlotType(fieldType))
                    val = renderValueForType(fieldType, stripWrap(f.expr), val);
                else if (fieldType != null && !isStringType(fieldType)) {
                    val = ownedObjectFieldText(fieldType, f.expr, val);
                    val = renderValueForType(fieldType, f.expr, val);
                    // A business u32 Int field reinterprets a signed rendering
                    // so the struct literal field carries the declared domain.
                    if (isIntType(fieldType) && types.of(fieldType, false) == "u32"
                        && !StringTools.startsWith(val, "u32::") && rendersSignedIntArg(f.expr, val))
                        val = RustConversions.reinterpret(val, "u32");
                }
                RustImports.toSnakeCase(f.name) + ": " + val;
            }
        ];
        return typeName + " { " + parts.join(", ") + " }";
    }

    /**
        ownedObjectFieldText: an object literal field is an owned value slot.
        A borrowed loop item names a Rust reference, so its referent clones at
        the field boundary; a rendered reference dereferences the same way.
        Interface and String slots keep their dedicated lowering.
    **/
    function ownedObjectFieldText(expected:Type, fieldExpr:TypedExpr, text:String):String {
        if (isTypeCopy(expected))
            return text;
        switch (stripWrap(fieldExpr).expr) {
            case TLocal(v) if (borrowedLoopVarIds.exists(v.id)):
                return isCloneableValue(expected) ? "(*" + text + ").clone()" : "(" + text + ").clone()";
            case _:
        }
        if (StringTools.startsWith(text, "&") && !StringTools.endsWith(text, ".clone()"))
            return isCloneableValue(expected) ? "(*" + text + ").clone()" : text;
        return text;
    }

    /** The declared field types of a named or anonymous structure type. */
    function objectFieldTypes(t:Type):Map<String, Type> {
        final out = new Map<String, Type>();
        switch (Context.follow(t)) {
            case TType(def, _):
                switch (def.get().type) {
                    case TAnonymous(anon):
                        for (f in anon.get().fields)
                            out.set(f.name, f.type);
                    case _:
                }
            case TAnonymous(anon):
                for (f in anon.get().fields)
                    out.set(f.name, f.type);
            case _:
        }
        return out;
    }

    function resolveTypeName(t:Type):String {
        return switch (t) {
            case TType(def, _):
                final d = def.get();
                imports.requireType(d.module, d.name);
                d.name;
            case TAnonymous(anon):
                final match = state.structTypedefs.get(RustDecl.structureSignature(anon));
                if (match == null) {
                    Context.error("anonymous structure literal has no matching named typedef", Context.currentPos());
                    null;
                } else {
                    imports.requireType(match.module, match.name);
                    match.name;
                }
            case _:
                Context.error("object literal must be typed by a named typedef before translation", Context.currentPos());
                null;
        }
    }

    // ------------------------------------------------------------------
    // Local analysis
    // ------------------------------------------------------------------

    /**
        Whether an interface method writes through its receiver. The
        interface field has no body, so the aggregated implementation
        shape decides; a call on an interface-typed local or field then
        needs the mutable binding marker.
    **/
    function interfaceMethodWritesReceiver(iface:Ref<ClassType>, cf:ClassField):Bool {
        final ifaceType = iface.get();
        if (!ifaceType.isInterface)
            return false;
        final shape = state.interfaceMethodShapes.get(RustEmissionState.interfaceMethodKey(ifaceType.module, ifaceType.name, cf.name));
        return shape != null && shape.isMutating;
    }

    function scanLocals(e:TypedExpr):Void {
        switch (e.expr) {
            case TVar(v, init):
                PolicyQueries.noteDeclaredLocalName(v, usedNames, false);
                if (v.name != "`" && init == null) {
                    // Deferred locals are assigned by control flow below; only
                    // mark them mutable when scanLocals observes such an assignment.
                    deferredLocals.set(v.id, true);
                }
                if (init != null) {
                    // Wire reads and reader positions arrive as unsigned values;
                    // remember the locals so negative-domain checks lower as
                    // upper-bound checks.
                    switch (stripWrap(init).expr) {
                        case TCall(fn, _):
                            if (isFpHelperInt64Call(fn))
                                fpInt64Halves.set(v.id, true);
                            if (isFpHelperI32Call(fn))
                                i32Locals.set(v.id, true);
                            if (isStdParseIntCall(init))
                                parseIntLocals.set(v.id, true);
                            switch (fn.expr) {
                                case TField(_, FInstance(_, _, cf)) | TField(_, FStatic(_, cf)):
                                    final n = cf.get().name;
                                    if (n == "readU16" || n == "readU32" || n == "remaining" || n == "consumed") {
                                        unsignedLocals.set(v.id, true);
                                    }
                                case _:
                            }
                        case _:
                    }
                    // The declaration decides the binding domain: an Int
                    // initializer that renders in the business u32 domain (a
                    // constant, a u32-source read, a length) keeps that domain
                    // even when a later comparison looks signed. A wrapping
                    // binop or String.indexOf initializer renders i32 and is
                    // exempt. The comparison heuristic consults this fact so
                    // the sentinel exemption cannot override a u32 binding.
                    if (isIntType(v.t) && !isNullType(v.t) && !declarationRendersI32(init)) {
                        declaredUnsignedIntLocals.set(v.id, true);
                    }
                    // A local derived from an i32-domain operand keeps the
                    // signed rendering, matching the Rust type inference of
                    // its declaration.
                    if (isIntType(v.t) && !isNullType(v.t) && i32LocalDomain(init))
                        i32Locals.set(v.id, true);
                }
            case TTry(body, _):
                collectTryAssignments(body);
            case TBlock(stmts):
                // A countdown loop the renderer will shift to an unsigned
                // guard keeps the u32 domain; collect its variable here so
                // the zero-comparison rule below can exclude it.
                for (i in 0...stmts.length) {
                    if (i + 1 < stmts.length) {
                        final cd = matchCountdownLoop(stmts[i], stmts[i + 1]);
                        if (cd != null)
                            countdownShiftedVars.set(cd.readVar.id, true);
                    }
                }
                // A countdown loop whose guard is `>= 0` but whose step is
                // not a unit (transformCountdownLoops only shifts unit
                // steps) exits only when the value goes negative, so the
                // signed domain is required even though the declaration
                // renders u32. Record it so the sentinel heuristic keeps
                // the i32 exemption for these variables.
                for (i in 0...stmts.length) {
                    if (i + 1 < stmts.length) {
                        final cd = matchCountdownLoop(stmts[i], stmts[i + 1]);
                        if (cd == null) {
                            switch [stmts[i].expr, stmts[i + 1].expr] {
                                case [TVar(readVar, init), TWhile(cond, body, true)] if (init != null && isIntType(init.t)):
                                    if (hasGteZeroCheck(cond, readVar.id)
                                        && !mentionsUnitDecrement(statementsOf(body), readVar.id)
                                        && mentionsAnyDecrement(statementsOf(body), readVar.id))
                                        signedCountdownVars.set(readVar.id, true);
                                case _:
                            }
                        }
                    }
                }
            case TBinop(OpEq | OpNotEq, left, right):
                final local = switch ([stripWrap(left).expr, stripWrap(right).expr]) {
                    case [TLocal(v), _] if (isTNull(right) || isZero(right)): v;
                    case [_, TLocal(v)] if (isTNull(left) || isZero(left)): v;
                    case _: null;
                };
                if (local != null)
                    nullableSensitiveLocals.set(local.id, true);
            case TBinop(cmpOp, left, right) if (cmpOp == OpLte || cmpOp == OpLt || cmpOp == OpGt || cmpOp == OpGte):
                // A comparison that contemplates negative values keeps the
                // local in the signed i32 Int domain: `>= 0`, `< 0`, and
                // `<= 0` can all observe a negative value, and a comparison
                // against an expression that can underflow below zero does
                // too. A bare `> 0` is a positive check on a business u32
                // index and never needs the signed domain, so it leaves the
                // local unsigned. The declaration decides the binding
                // domain: a local whose initializer renders u32 (a constant
                // or u32-source read) keeps that domain even under a
                // signed-looking comparison, so the sentinel exemption
                // cannot override the u32 binding. A countdown loop
                // variable (decremented under a `>= 0` guard with a
                // non-unit step) is the exception: its loop exits only when
                // the value goes negative, so it keeps the signed domain.
                // A comparison against an expression that can underflow
                // below zero (`x <= length - k`) needs the signed domain
                // regardless of the declaration: the bound goes
                // negative when the length is short, and an unsigned
                // wrapping bound would keep the loop running past the end.
                switch ([stripWrap(left).expr, stripWrap(right).expr]) {
                    case [TLocal(v), _] if (isUnderflowProneIntExpr(right)):
                        if (isIntType(v.t) && !isNullType(v.t) && !unsignedLocals.exists(v.id) && !countdownShiftedVars.exists(v.id)) i32Locals.set(v.id, true);
                    case [_, TLocal(v)] if (isUnderflowProneIntExpr(left)):
                        if (isIntType(v.t) && !isNullType(v.t) && !unsignedLocals.exists(v.id) && !countdownShiftedVars.exists(v.id)) i32Locals.set(v.id, true);
                    case _:
                }
                // A sentinel comparison against literal zero (`< 0`,
                // `>= 0`, `<= 0`) follows the declaration's domain: a
                // local whose initializer renders u32 (a constant or
                // u32-source read) keeps that domain, so the sentinel
                // exemption cannot override the u32 binding. A countdown
                // loop variable (decremented under a `>= 0` guard with a
                // non-unit step) is the exception: its loop exits only when
                // the value goes negative, so it keeps the signed domain.
                switch ([stripWrap(left).expr, stripWrap(right).expr]) {
                    case [TLocal(v), _] if ((cmpOp == OpLte || cmpOp == OpLt || cmpOp == OpGte) && isZero(right)):
                        if (isIntType(v.t) && !isNullType(v.t) && (!declaredUnsignedIntLocals.exists(v.id) || signedCountdownVars.exists(v.id)) && !unsignedLocals.exists(v.id) && !countdownShiftedVars.exists(v.id)) i32Locals.set(v.id, true);
                    case [_, TLocal(v)] if ((cmpOp == OpLte || cmpOp == OpGt || cmpOp == OpGte) && isZero(left)):
                        if (isIntType(v.t) && !isNullType(v.t) && (!declaredUnsignedIntLocals.exists(v.id) || signedCountdownVars.exists(v.id)) && !unsignedLocals.exists(v.id) && !countdownShiftedVars.exists(v.id)) i32Locals.set(v.id, true);
                    case _:
                }
            case TBinop(OpAssign, t, _) | TBinop(OpAssignOp(_), t, _):
                switch (stripWrap(t).expr) {
                    case TLocal(v):
                        mutated.set(v.id, true);
                        #if boring_fold_debug
                        Sys.stderr().writeString("MSITE2 id=" + v.id + " name=" + v.name + "\n");
                        #end
                    case TArray(arr, _):
                        final receiver = mapBackingReceiver(arr);
                        switch (stripWrap(receiver == null ? arr : receiver).expr) {
                            case TLocal(v):
                                mutated.set(v.id, true);
                                #if boring_fold_debug
                                Sys.stderr().writeString("MSITE3 id=" + v.id + " name=" + v.name + "\n");
                                #end
                            case _:
                        }
                    case TField(subj, _):
                        // Assigning through a field of a local requires the binding to be mutable;
                        // the chain can be arbitrarily deep (a.b.c = ... marks a).
                        var inner = subj;
                        while (true) {
                            switch (stripWrap(inner).expr) {
                                case TLocal(v):
                                    mutated.set(v.id, true);
                                    #if boring_fold_debug
                                    Sys.stderr().writeString("MSITE4 id=" + v.id + " name=" + v.name + "\n");
                                    #end
                                    break;
                                case TField(next, _):
                                    inner = next;
                                case _:
                                    break;
                            }
                        }
                    case _:
                }
            case TUnop(OpIncrement | OpDecrement, _, subj):
                // An `x++` / `x--` statement arrives as a unary op that
                // renders as `+= 1` / `-= 1`; the mutation goes through
                // the same path as a compound assignment.
                switch (stripWrap(subj).expr) {
                    case TLocal(v):
                        mutated.set(v.id, true);
                        #if boring_fold_debug
                        Sys.stderr().writeString("MSITE5 id=" + v.id + " name=" + v.name + "\n");
                        #end
                    case _:
                }
            case TCall(fn, args):
                switch (fn.expr) {
                    case TField(subj, FInstance(iface, _, cf)):
                        final n = cf.get().name;
                        if (n == "readU16" || n == "readU32" || n == "readF64" || n == "readAscii" || n == "writeU16" || n == "writeU32" || n == "writeF64"
                            || n == "writeAscii" || n == "addByte" || n == "push" || n == "insert" || n == "unshift" || n == "splice" || n == "finish" || n == "put" || n == "set" || n == "update"
                            || n == "add" || n == "addChar") {
                            // The receiver-mutation name list covers the
                            // mutating sequence operations the emitter renders
                            // as owned updates; `insert` and `unshift` belong
                            // with `push` because each extends the receiver
                            // in place. A field-chain receiver marks its root
                            // binding for the same reason as a field
                            // assignment. Covers the receiver sequence-update
                            // family and the receiver-sequence field-root
                            // family.
                            var receiver = subj;
                            while (true) {
                                switch (stripWrap(receiver).expr) {
                                    case TLocal(v):
                                        mutated.set(v.id, true);
                                        #if boring_fold_debug
                                        Sys.stderr().writeString("MSITE6 id=" + v.id + " name=" + v.name + "\n");
                                        #end
                                        break;
                                    case TField(inner, _):
                                        receiver = inner;
                                    case _:
                                        break;
                                }
                            }
                        } else {
                            // A call through a receiver-writing method mutates
                            // the receiver binding itself: the declaration
                            // renders that method with a mutable receiver, so
                            // a local receiver needs the mutable marker.
                            // Covers the receiver-writing call family.
                            switch (stripWrap(subj).expr) {
                                case TLocal(v):
#if boring_fold_debug
                                    Context.warning("MUTPROBE m=" + cf.get().name + " fw=" + RustDecl.fieldWritesReceiver(cf.get()) + " iw=" + interfaceMethodWritesReceiver(iface, cf.get()) + " vf=" + Std.string(cf.get().expr() != null), e.pos);
#end
                                    if (RustDecl.fieldWritesReceiver(cf.get()) || interfaceMethodWritesReceiver(iface, cf.get()))
                                        mutated.set(v.id, true);
                                        #if boring_fold_debug
                                        Sys.stderr().writeString("MSITE7 id=" + v.id + " name=" + v.name + "\n");
                                        #end
                                case _:
                            }
                        }
                    case _:
                }
                final isInstancePush = switch (fn.expr) {
                    case TField(_, FInstance(_, _, cf)) if (cf.get().name == "push"): true;
                    default: false;
                };
                // renderCallArgs reads the callee's declared parameter
                // types through cf.get().type, so the declaration decides
                // the borrow: a parameter declared as Array lowers to a
                // mutating borrow that drains the vector, while a param
                // left as an unbound type parameter borrows shared. The
                // call-site type fn.t binds that parameter to Array and
                // would mark a local the shared borrow never mutates.
                final declaredFnType = switch (fn.expr) {
                    case TField(_, FInstance(_, _, cf)) | TField(_, FStatic(_, cf)): cf.get().type;
                    default: fn.t;
                };
                if (!isInstancePush) {
                    final paramTypes = switch (Context.follow(declaredFnType)) {
                        case TFun(pargs, _): [for (p in pargs) p.t];
                        default: [];
                    };
                    // When the callee is a class field its body decides which
                    // positions mutate: renderCallArgs borrows &mut exactly
                    // the positions mutableParamPositions reports, so a
                    // shared-borrow position must not mark the local mutated.
                    final mutableAt = switch (fn.expr) {
                        case TField(_, FInstance(_, _, cf)) | TField(_, FStatic(_, cf)): mutableParamPositions(cf.get());
                        default: null;
                    };
                    for (i in 0...args.length)
                        if (i < paramTypes.length && isPassByRef(paramTypes[i]))
                            switch (Context.follow(paramTypes[i])) {
                                case TInst(c, _) if (c.get().name == "Array"):
                                    // The mark must match the borrow: renderCallArgs emits
                    // `&mut` only at positions mutableParamPositions reports,
                    // and a callee without declared positions borrows shared.
                    // (CallArgMarkBorrowAgreement)
                    if (mutableAt != null && mutableAt.indexOf(i) >= 0) switch (stripWrap(args[i]).expr) {
                                        case TField(subj, _): switch (stripWrap(subj).expr) {
                                                case TLocal(v): mutated.set(v.id, true);
                                                #if boring_fold_debug
                                                Sys.stderr().writeString("MSITE8 id=" + v.id + " name=" + v.name + "\n");
                                                #end
                                                case _:
                                            }
                                        case TLocal(v): mutated.set(v.id, true);
                                        #if boring_fold_debug
                                        Sys.stderr().writeString("MSITE9 id=" + v.id + " name=" + v.name + "\n");
                                        #end
                                        default:
                                    }
                                default:
                            }
                }
            case _:
        }
        TypedExprTools.iter(e, scanLocals);
    }

    /**
        Marks local function values whose body can throw. Their closure
        signatures carry `Result<_, E>` so the throw propagates at each call
        and the unit closure no longer carries it. The error
        type is the enclosing function's already-computed union. Detection
        walks direct throws and calls to other fallible locals to a fixed
        point so mutually recursive locals agree.
    **/
    function scanLocalFunctionFallibility(e:TypedExpr):Void {
        fallibleLocalFunctionErrors.clear();
        final functions:Array<{id:Int, body:TypedExpr}> = [];
        function collect(x:TypedExpr):Void {
            switch (stripWrap(x).expr) {
                case TVar(v, init) if (init != null):
                    switch (stripWrap(init).expr) {
                        case TFunction(f):
                            functions.push({id: v.id, body: f.expr});
                            collect(f.expr);
                        case _:
                            TypedExprTools.iter(init, collect);
                    }
                case _:
                    TypedExprTools.iter(x, collect);
            }
        }
        collect(e);
        if (functions.length == 0)
            return;
        final fallible:Map<Int, Bool> = [];
        var changed = true;
        while (changed) {
            changed = false;
            for (fn in functions) {
                if (fallible.exists(fn.id))
                    continue;
                if (localFunctionBodyThrows(fn.body) || localFunctionBodyCallsFallible(fn.body, fallible)) {
                    fallible.set(fn.id, true);
                    changed = true;
                }
            }
        }
        if (errorTypeName == null)
            return;
        for (fn in functions)
            if (fallible.exists(fn.id))
                fallibleLocalFunctionErrors.set(fn.id, errorTypeName);
    }

    function localFunctionBodyThrows(e:TypedExpr):Bool {
        var found = false;
        function walk(x:TypedExpr):Void {
            if (found)
                return;
            switch (stripWrap(x).expr) {
                case TThrow(_): found = true;
                case _: TypedExprTools.iter(x, walk);
            }
        }
        walk(e);
        return found;
    }

    function localFunctionBodyCallsFallible(e:TypedExpr, fallible:Map<Int, Bool>):Bool {
        var found = false;
        function walk(x:TypedExpr):Void {
            if (found)
                return;
            switch (stripWrap(x).expr) {
                case TCall({expr: TLocal(v)}, _) if (fallible.exists(v.id)): found = true;
                case _: TypedExprTools.iter(x, walk);
            }
        }
        walk(e);
        return found;
    }

    function scanReadsAfter(e:TypedExpr):Void {
        // A local copied into another local must clone when the source is
        // read anywhere later in the function and also inside other blocks:
        // a branch body may copy a local that a sibling statement after the
        // branch still reads (E0382 borrow-after-move). Collect every
        // `x = source` declaration, then check the whole function body for
        // a later mention of the source.
        final copies:Array<{source:TVar, decl:TypedExpr}> = [];
        function collect(node:TypedExpr):Void {
            switch (node.expr) {
                case TVar(_, init) if (init != null):
                    switch (stripWrap(init).expr) {
                        case TLocal(source): copies.push({source: source, decl: node});
                        case TField(subj, _):
                            switch (stripWrap(subj).expr) {
                                case TLocal(source): copies.push({source: source, decl: node});
                                case _:
                            }
                        case _:
                    }
                case _:
            }
            TypedExprTools.iter(node, collect);
        }
        collect(e);
        for (c in copies) {
            // The declaration itself mentions the source; a later read
            // anywhere in the function (excluding this decl) forces a clone.
            var found = false;
            function walk(node:TypedExpr):Void {
                if (found)
                    return;
                if (node == c.decl)
                    return;
                if (mentionsLocal(node, c.source)) {
                    found = true;
                    return;
                }
                TypedExprTools.iter(node, walk);
            }
            walk(e);
            if (found)
                readsAfterDeclaration.set(c.source.id, true);
        }
    }

    function collectTryAssignments(e:TypedExpr):Void {
        function walk(x:TypedExpr):Void {
            switch (x.expr) {
                case TBinop(OpAssign, target, _) | TBinop(OpAssignOp(_), target, _):
                    switch (stripWrap(target).expr) {
                        case TLocal(v): tryCapturedAssignments.set(v.id, true);
                        case _:
                    }
                case _:
            }
            TypedExprTools.iter(x, walk);
        }
        walk(e);
    }

    function mentionsLocal(e:TypedExpr, v:TVar):Bool {
        return PolicyQueries.mentionsLocal(e, v);
    }

    /** Whether the expression mentions a local with the given name. Haxe
        creates fresh TVar instances per reference, so id comparison misses
        the same source local in a different node; name comparison is stable
        within one function. **/
    function mentionsLocalName(e:TypedExpr, name:String):Bool {
        var found = false;
        function walk(x:TypedExpr) {
            if (found)
                return;
            switch (x.expr) {
                case TLocal(l) if (l.name == name): found = true;
                case _:
            }
            haxe.macro.TypedExprTools.iter(x, walk);
        }
        walk(e);
        return found;
    }

    function localName(v:TVar):String {
        if (v.name != "`") {
            return v.name;
        }
        if (hiddenNames.exists(v.id)) {
            return hiddenNames.get(v.id);
        }
        final candidates = ["i", "j", "k", "n", "m", "index", "write", "read"];
        final taken:Map<String, Bool> = [];
        for (name in hiddenNames)
            taken.set(name, true);
        for (c in candidates) {
            if (!usedNames.exists(c) && !taken.exists(c)) {
                hiddenNames.set(v.id, c);
                return c;
            }
        }
        hiddenCounter += 1;
        final generated = "t" + hiddenCounter;
        hiddenNames.set(v.id, generated);
        return generated;
    }

    public function payloadName(ef:EnumField, index:Int):String {
        return switch (ef.type) {
            case TFun(args, _) if (index < args.length):
                RustImports.toSnakeCase(args[index].name);
            case _:
                "param" + index;
        };
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    function symbolOf(op:Binop):String {
        return switch (op) {
            case OpAdd: "+";
            case OpMult: "*";
            case OpDiv: "/";
            case OpSub: "-";
            case OpEq: "==";
            case OpNotEq: "!=";
            case OpGt: ">";
            case OpGte: ">=";
            case OpLt: "<";
            case OpLte: "<=";
            case OpBoolAnd: "&&";
            case OpBoolOr: "||";
            case OpMod: "%";
            case OpAnd: "&";
            case OpOr: "|";
            case OpXor: "^";
            case OpShl: "<<";
            case OpShr: ">>";
            case _: fail(null, "operator symbol has no Rust lowering: " + Std.string(op));
        }
    }

    function precedenceOf(op:Binop):Int {
        return switch (op) {
            case OpMult | OpDiv | OpMod: 11;
            case OpAdd | OpSub: 10;
            case OpShl | OpShr | OpUShr: 9;
            case OpLt | OpLte | OpGt | OpGte: 8;
            case OpEq | OpNotEq: 7;
            case OpAnd: 6;
            case OpXor: 5;
            case OpOr: 4;
            case OpBoolAnd: 3;
            case OpBoolOr: 2;
            case OpAssign | OpAssignOp(_): 1;
            case _: 0;
        }
    }

    function associative(op:Binop):Bool {
        return switch (op) {
            case OpAdd | OpMult | OpAnd | OpOr | OpXor | OpBoolAnd | OpBoolOr: true;
            case _: false;
        }
    }

    function stripWrap(e:TypedExpr):TypedExpr {
        return switch (e.expr) {
            case TParenthesis(inner) | TMeta(_, inner) | TCast(inner, _): stripWrap(inner);
            case _: e;
        }
    }

    function unwrapLambda(e:TypedExpr):Null<TFunc> {
        return PolicyQueries.unwrapLambda(e);
    }

    function lambdaBody(e:TypedExpr):TypedExpr {
        return PolicyQueries.lambdaBody(e);
    }

    function stripCast(e:TypedExpr):TypedExpr {
        return switch (e.expr) {
            case TCast(inner, _) | TMeta(_, inner): stripCast(inner);
            case _: e;
        }
    }

    function fieldName(fa:FieldAccess):String {
        return switch (fa) {
            case FInstance(_, _, cf) | FStatic(_, cf) | FAnon(cf) | FClosure(_, cf): cf.get().name;
            case FEnum(_, ef): ef.name;
            case FDynamic(n): n;
        }
    }

    function isBytes(e:TypedExpr):Bool {
        return switch (e.t) {
            case TInst(c, _): c.get().module == "haxe.io.Bytes";
            case TType(d, _): d.get().module == "haxe.io.Bytes";
            case _: false;
        }
    }

    function isString(e:TypedExpr):Bool {
        return switch (e.t) {
            case TInst(c, _): c.get().name == "String";
            // A Null<String> receiver is still a String method receiver; the
            // method lowering unwraps the Option at the call boundary.
            case TAbstract(a, params) if (a.get().name == "Null" && params.length == 1):
                switch (Context.follow(params[0])) {
                    case TInst(c, _): c.get().name == "String";
                    case _: false;
                };
            case _: false;
        }
    }

    function quoteString(s:String):String {
        // Keep each source newline escape at the end of its own literal.
        // Rust accepts adjacent string literals, so this bounds generated JSON
        // evidence lines without changing the resulting string bytes.
        final parts = s.split("\n");
        if (parts.length == 1)
            return '"' + escapedPart(parts[0]) + '"';
        final literals = [for (i in 0...parts.length) {
            final suffix = i < parts.length - 1 ? "\\n" : "";
            '"' + escapedPart(parts[i]) + suffix + '"';
        }];
        // Rust does not implicitly concatenate adjacent literals. concat! keeps
        // the generated source split while remaining a single &'static str.
        return "concat!(" + literals.join(",\n") + ")";
    }

    function escapedPart(s:String):String {
        return s.split("\\")
            .join("\\\\")
            .split("\"")
            .join("\\\"")
            .split("\r")
            .join("\\r")
            .split("\t")
            .join("\\t");
    }

    function renderArrayLiteral(elements:Array<String>, vec:Bool):String {
        final prefix = vec ? "vec![" : "[";
        final suffix = "]";
        if (elements.length == 0 || (elements.length == 1 && elements[0] == ""))
            return prefix + suffix;
        // Small arrays stay on one ruled single line (the array-root contract);
        // larger literals emit one deterministic element per line, which keeps
        // big data tables readable and bounds every generated line.
        final single = prefix + elements.join(", ") + suffix;
        if (single.length <= 100)
            return single;
        return prefix + "\n    " + elements.join(",\n    ") + ",\n" + suffix;
    }

    function renderArrayLiteralExpr(elements:Array<TypedExpr>, vec:Bool):String {
        return renderArrayLiteral([for (x in elements) expr(x)], vec);
    }

    function indent(depth:Int):String {
        var s = "";
        for (_ in 0...depth)
            s += "    ";
        return s;
    }

    /** Whether a rendered value is a lone atom: no top-level operator
        whose precedence could capture a trailing method call. */
    static function isSimpleValueText(s:String):Bool {
        var depth = 0;
        for (i in 0...s.length) {
            final ch = s.charAt(i);
            switch (ch) {
                case "(" | "[":
                    depth++;
                case ")" | "]":
                    depth--;
                default:
                    if (depth == 0)
                        switch (ch) {
                            case "+" | "-" | "*" | "/" | "%" | "&" | "|" | "^" | "<" | ">": return false;
                            case _:
                        }
            }
        }
        return true;
    }

    function matchingParens(s:String):Bool {
        var depth = 0;
        for (i in 0...s.length) {
            if (s.charAt(i) == "(")
                depth++;
            else if (s.charAt(i) == ")") {
                depth--;
                if (depth == 0 && i < s.length - 1)
                    return false;
            }
        }
        return depth == 0;
    }

    function fail(e:Null<TypedExpr>, msg:String):String {
        final pos = e != null ? e.pos : Context.currentPos();
        Context.error(msg, pos);
        return "";
    }

    function collectOrTerms(e:TypedExpr, out:Array<TypedExpr>):Void {
        final inner = stripWrap(e);
        switch (inner.expr) {
            case TBinop(OpOr, l, r):
                collectOrTerms(l, out);
                collectOrTerms(r, out);
            case _:
                out.push(inner);
        }
    }

    function isSameExpr(a:TypedExpr, b:TypedExpr):Bool {
        if (a == null || b == null)
            return a == b;
        final sa = stripWrap(a);
        final sb = stripWrap(b);
        return switch [sa.expr, sb.expr] {
            case [TLocal(v1), TLocal(v2)]: v1.id == v2.id;
            case [TConst(c1), TConst(c2)]: Std.string(c1) == Std.string(c2);
            case [TField(s1, fa1), TField(s2, fa2)]: fieldName(fa1) == fieldName(fa2) && isSameExpr(s1, s2);
            case _: false;
        };
    }

    function extractByteRead(e:TypedExpr):Null<{buf:TypedExpr, base:TypedExpr, offset:Int}> {
        final inner = stripWrap(e);
        var bufExpr:Null<TypedExpr> = null;
        var idxExpr:Null<TypedExpr> = null;
        switch (inner.expr) {
            case TCall(fn, args) if (args.length == 1):
                switch (stripWrap(fn).expr) {
                    case TField(subj, fa) if (fieldName(fa) == "get"):
                        bufExpr = subj;
                        idxExpr = args[0];
                    case _:
                }
            case TArray(arr, idx):
                bufExpr = arr;
                idxExpr = idx;
            case _:
        }
        if (bufExpr == null || idxExpr == null) {
            return null;
        }
        final strippedIdx = stripWrap(idxExpr);
        switch (strippedIdx.expr) {
            case TBinop(OpAdd, l, r):
                switch [stripWrap(l).expr, stripWrap(r).expr] {
                    case [_, TConst(TInt(k))]:
                        return {buf: bufExpr, base: l, offset: k};
                    case [TConst(TInt(k)), _]:
                        return {buf: bufExpr, base: r, offset: k};
                    case _:
                }
            case _:
                return {buf: bufExpr, base: idxExpr, offset: 0};
        }
        return null;
    }

    function tryMatchFromBeBytes(e:TypedExpr):Null<String> {
        final terms:Array<TypedExpr> = [];
        collectOrTerms(e, terms);
        if (terms.length != 2 && terms.length != 4 && terms.length != 8) {
            return null;
        }
        final n = terms.length;
        final extracted:Array<{
            buf:TypedExpr,
            base:TypedExpr,
            offset:Int,
            shift:Int
        }> = [];
        for (i in 0...n) {
            final term = terms[i];
            var readExpr:TypedExpr = term;
            var shift = 0;
            switch (term.expr) {
                case TBinop(OpShl, inner, s):
                    readExpr = inner;
                    switch (stripWrap(s).expr) {
                        case TConst(TInt(sh)): shift = sh;
                        case _: return null;
                    }
                case _:
                    shift = 0;
            }
            final expectedShift = (n - 1 - i) * 8;
            if (shift != expectedShift) {
                return null;
            }
            final read = extractByteRead(readExpr);
            if (read == null) {
                return null;
            }
            if (read.offset != i) {
                return null;
            }
            if (i > 0) {
                if (!isSameExpr(read.buf, extracted[0].buf) || !isSameExpr(read.base, extracted[0].base)) {
                    return null;
                }
            }
            extracted.push({
                buf: read.buf,
                base: read.base,
                offset: read.offset,
                shift: shift
            });
        }

        final typeName = switch (n) {
            case 2: "u16";
            case 4: "u32";
            case 8: "u64";
            case _: return null;
        };

        final bufStr = expr(extracted[0].buf);
        final baseStr = expr(extracted[0].base);
        // A byte buffer's element is already u8, so the element read needs
        // no cast in the from_be_bytes array; an Int-word buffer (registry
        // hashing pads a Vec<u32> with bytes) narrows each element the way
        // the old `as u8` did, through the T4 mask.
        final byteSource = isBytes(stripWrap(extracted[0].buf));
        final elems = [];
        for (i in 0...n) {
            final idx = i == 0 ? usizeIndex(baseStr) : usizeIndex(baseStr + " + " + i);
            final elem = byteSource ? "(" + bufStr + "[" + idx + "])" : RustConversions.truncate(bufStr + "[" + idx + "]", "u8");
            elems.push("(" + elem + ")");
        }
        return typeName + "::from_be_bytes([\n    " + elems.join(",\n    ") + "\n])";
    }

    function isStringIndexOf(fn:TypedExpr):Bool {
        return switch (fn.expr) {
            case TField(subj, FInstance(_, _, cf))
                if ((cf.get().name == "indexOf" || cf.get().name == "lastIndexOf" || cf.get().name == "last_index_of")
                    && isString(stripCast(subj))): true;
            case _: false;
        };
    }

    /** Whether the expression is a Std.parseInt call, whose result is i32. */
    function isStdParseIntCall(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TCall(fn, _): switch (stripWrap(fn).expr) {
                    case TField(_, FStatic(c, cf)): c.get().module == "Std" && cf.get().name == "parseInt";
                    case _: false;
                };
            case _: false;
        };
    }

    function isStringCharCodeAt(fn:TypedExpr):Bool {
        return switch (fn.expr) {
            case TField(subj, FInstance(_, _, cf)) if (cf.get().name == "charCodeAt" && isString(stripCast(subj))): true;
            case _: false;
        };
    }

    function isStringCharCodeAtCall(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TCall(fn, _) if (isStringCharCodeAt(fn)): true;
            case _: false;
        };
    }

    function isNullableCharCodeExpr(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TCall(fn, _) if (isStringCharCodeAt(fn)): true;
            case _: false;
        };
    }

    function resolveExprType(e:TypedExpr):String {
        final inner = stripWrap(e);
        switch (inner.expr) {
            case TLocal(v):
                if (i32Locals.exists(v.id))
                    return "i32";
                // argTypes accumulates across functions; a current-function
                // parameter is the only valid name-keyed lookup.
                if (paramVarIds.exists(v.id) && argTypes.exists(v.name))
                    return argTypes.get(v.name);
            case _:
        }
        return types.of(e.t);
    }

    function tryMatchByteExtract(e:TypedExpr):Null<String> {
        final inner = stripWrap(e);
        var target:TypedExpr = inner;
        var shift = 0;
        switch (inner.expr) {
            case TBinop(OpUShr | OpShr, t, s):
                target = t;
                switch (stripWrap(s).expr) {
                    case TConst(TInt(sh)): shift = sh;
                    case _: return null;
                }
            case _:
                shift = 0;
        }
        final strippedTarget = stripWrap(target);
        switch (strippedTarget.expr) {
            case TCall(fn, _) if (isStringCharCodeAt(fn)):
                // A nullable code unit lowers to Option<u32>; the byte
                // extract rewrite replaces a `& 0xFF` binop whose Haxe
                // semantics unbox null to 0, so unwrap the Option to 0
                // the same way before the value feeds a u8 context.
                return expr(target) + (isNullType(target.t) || isStringCharCodeAtCall(target) ? ".unwrap_or(0)" : "");
            case _:
        }
        final targetType = resolveExprType(target);
        final bitWidth = switch (targetType) {
            case "u16": 16;
            case "u32": 32;
            case "u64": 64;
            case "u8": 8;
            case _: 32;
        };
        if (bitWidth == 8) {
            return expr(target);
        }
        if ((bitWidth - 8 - shift) % 8 != 0 || shift < 0 || shift > bitWidth - 8) {
            return null;
        }
        final byteIndex = Std.int((bitWidth - 8 - shift) / 8);
        return expr(target) + ".to_be_bytes()[" + byteIndex + "]";
    }

    function isPassByRef(t:Type):Bool {
        if (isNullType(t))
            return false;
        return switch (Context.follow(t)) {
            case TAbstract(a, _) if (a.get().name == "ReadOnlyArray"
                || (a.get().pack.join(".") == "std" && a.get().name == "ReadOnlyArray")): true;
            case TInst(c, _)
                if (c.get().name == "Array"
                    || c.get().name == "Bytes"
                    || (c.get().pack.join(".") == "haxe.io" && c.get().name == "Bytes")
                    || c.get().name == "String"
                    || c.get().name == "StringBuf"
                    || (c.get().module == "std" && c.get().name == "StringBuf")): true;
            case _: false;
        };
    }

    function isInterfaceType(t:Null<Type>):Bool {
        if (t == null)
            return false;
        return switch (Context.follow(t)) {
            case TInst(c, _): c.get().isInterface;
            case _: false;
        };
    }

    /** Whether a slot declares an interface, directly or through Null. */
    function isInterfaceSlotType(t:Null<Type>):Bool {
        if (t == null)
            return false;
        return isInterfaceType(t) || (isNullType(t) && isInterfaceType(getNullInnerType(t)));
    }

    /**
        The payload of a Box<dyn Trait> construction. Non-Copy concrete
        locals clone before boxing so the source stays alive for later
        reads; Haxe object references are shared, while Rust Box takes
        ownership. Covers the boxed-interface-local family (E0382).
    **/
    function boxedInterfacePayload(actual:TypedExpr, rendered:String):String {
        final inner = normalizeConstructorResult(actual, rendered);
        return switch (stripWrap(actual).expr) {
            case TLocal(_): "(" + inner + ").clone()";
            case _: inner;
        };
    }

    /** Numeric scalar slots (Bool, Int, Float) that cannot hold an Option
        at runtime. (ScalarSlotUnwrap) */
    function isNumericScalarType(t:Type):Bool {
        return switch (Context.follow(t)) {
            case TAbstract(a, _): {
                final n = a.get().name;
                n == "Bool" || n == "Int" || n == "Float" || n == "Int64";
            };
            case _: false;
        };
    }

    /** An argument reading a local whose declaration still renders the
        Option shape. (ScalarSlotUnwrap) */
    /** The canonical answer to "does reading this local render the Option
        shape at this site?" Every gate must consult this single predicate:
        the bare-render registries (the guarded ternary and forcing
        read, non-null render) each disqualify, and otherwise the emitted
        declaration shape decides. (ScalarSlotUnwrap) */
    function localReadIsOption(v:TVar):Bool {
        if (nullableCollapsedLocals.exists(v.id)
            || hasGuardedTernaryLocals.exists(v.id)
            || forcingReadLocals.exists(v.id)
            || nonNullRenderedLocals.exists(v.id))
            return false;
        return optionRenderedLocals.exists(v.id);
    }

    /** Record the initializer text a declaration emitted so slot
        boundaries parse the shape from the same text.
        (DeclShapeRecord) */
    function recordDeclInit(v:TVar, initText:String):Void {
        declInitTexts.set(v.id, initText);
    }

    function isOptionRenderedLocalArg(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TLocal(v): localReadIsOption(v) && narrowedSubject(e) == null;
            case _: false;
        };
    }

    /** The Option-shape answer for an already-rendered expression. The
        rendered text decides; forms whose text carries no shape (a local
        name, an index or field read, a bare call) fall back to the typed
        expression, with a guard-narrowed subject reading as the bare
        payload its guard proved. (ShapeParse) */
    /** The Option-shape answer parsed from a local's declaration
        initializer text, cached per local. Uninitialized declarations
        carry no shape. (DeclShapeRecord, ShapeParse) */
    function declInitShape(v:TVar):RustShape {
        if (declShapeCache.exists(v.id))
            return declShapeCache.get(v.id);
        final initText = declInitTexts.get(v.id);
        final shape = initText == null ? RustShape.ShapeUnknown : RustShapeParse.shapeOf(initText);
        declShapeCache.set(v.id, shape);
        return shape;
    }

    /** The Option-shape answer for an already-rendered expression. The
        rendered text is the first authority: constructions, forcing
        reads, and composite arms are visible in the text, so the boundary
        reads exactly what the value is. A bare local name falls back to
        the shape parsed from its own declaration text; a guard-narrowed
        subject reads as the bare payload its guard proved. Everything
        else stays Unknown and no boundary adapts it.
        (DeclShapeRecord, ShapeParse) */
    function renderedArgShape(text:String, e:TypedExpr):RustShape {
        final fromText = RustShapeParse.shapeOf(text);
        if (fromText != RustShape.ShapeUnknown)
            return fromText;
        final inner = stripWrap(e);
        switch (inner.expr) {
            case TLocal(v):
                if (narrowedSubject(e) != null)
                    return RustShape.ShapeBare;
                final fromDecl = declInitShape(v);
                if (fromDecl != RustShape.ShapeUnknown)
                    return fromDecl;
            case TArray(_):
                // An index read renders bare text and carries the element
                // type at runtime: a nullable element read is an Option.
                // (ShapeParse)
                if (isNullType(e.t))
                    return RustShape.ShapeOption;
            case _:
        }
        return RustShape.ShapeUnknown;
    }

    /** Append a postfix method to an already-rendered text, parenthesizing
        composite forms so the postfix binds to the whole value.
        (ShapeParse) */
    function postfixAdapt(text:String, postfix:String):String {
        final t = StringTools.trim(text);
        final composite = StringTools.startsWith(t, "if ") || StringTools.startsWith(t, "match")
            || StringTools.startsWith(t, "{");
        return composite ? "(" + text + ")" + postfix : text + postfix;
    }

    function renderValueForType(expected:Null<Type>, actual:TypedExpr, rendered:String):String {
        if (expected == null || actual == null)
            return rendered;
        // A non-null Haxe local initialized to null stores Option<T> until
        // assigned. At a non-null value boundary Haxe's declaration contract
        // requires its payload; Copy values may consume the Option, while
        // owned values clone the proven payload so later Haxe reads remain
        // available.
        if (!isNullType(expected) && isNoneInitializedLocal(actual))
            if (RustShapeParse.shapeOf(rendered) != RustShape.ShapeBare)
                return isTypeCopy(actual.t) ? rendered + ".unwrap()" : rendered + ".as_ref().unwrap().clone()";
        // A scalar whose read still renders the Option shape (a wrapped
        // ternary, an Option-returning read) enters a non-null scalar
        // slot; the boundary unwraps it, and the None path has no
        // sample-defined value. The decision reads the rendered text
        // itself, so it agrees with every other boundary on the same
        // expression. (ScalarSlotUnwrap, ShapeParse)
        if (!isNullType(expected)
            && isNumericScalarType(expected)
            && renderedArgShape(rendered, actual) == RustShape.ShapeOption)
            return postfixAdapt(rendered, ".unwrap()");
        // Haxe unifies Int and Float; widen Int values to Float when the
        // target slot expects Float.
        if (isFloatType(expected) && isIntType(emittedType(actual)))
            return intToFloatText(rendered);
        // Methods returning an owned class value cannot leak the borrowed
        // `self` receiver into the return slot.
        if (!isTypeCopy(expected) && switch (stripWrap(actual).expr) {
            case TConst(TThis): true;
            case _: false;
        })
            return "(" + rendered + ").clone()";
        // A borrowed Copy value becomes a scalar at a value slot.
        // Dereference the generated reference before the Rust call.
        if (!isNullType(expected) && !isNullType(actual.t)
            && isTypeCopy(actual.t) && StringTools.startsWith(rendered, "&")) {
            return rendered.substr(0, 5) == "&mut " ? "*" + rendered.substr(5) : "*" + rendered.substr(1);
        }
        // Rust represents
        // concrete implementor therefore enters an interface slot through
        // the one sanctioned Box::new construction; an expression already
        // typed as the interface is already boxed by its declaration site.
        if (!isNullType(expected) && !isNullType(actual.t) && isStringType(expected) && isStringType(actual.t)) {
            final borrowedParam = switch (stripWrap(actual).expr) {
                case TLocal(v): isBorrowedParamLocal(v);
                case _: false;
            };
            if (borrowedParam)
                return rendered + ".to_string()";
        }
        if (isNullType(expected) && !isNullType(actual.t)
            && isFloatType(getNullInnerType(expected)) && isIntType(emittedType(actual)))
            return "Some(" + intToFloatText(rendered) + ")";
        if (isNullType(expected) && isNullType(actual.t) && isStringType(getNullInnerType(expected))) {
            final borrowedParam = switch (stripWrap(actual).expr) {
                case TLocal(v): isBorrowedParamLocal(v);
                case _: false;
            };
            if (borrowedParam)
                return "match &(" + rendered + ") { Some(v) => Some(v.to_string()), None => None }";
        }
        // charCodeAt is represented as Option<u32>; crossing into a plain
        // value parameter applies Haxe's null-to-zero bridge exactly once.
        if (!isNullType(expected) && isStringCharCodeAtCall(actual) && isNullType(actual.t)) {
            return rendered + ".unwrap_or(0)";
        }
        if (!isNullType(expected) && isInterfaceType(expected) && !isInterfaceType(actual.t)) {
            return "Box::new(" + boxedInterfacePayload(actual, rendered) + ")";
        }
        // Haxe unifies an object-literal field value's type to the interface
        // even when the value is a concrete constructor. Recover the concrete
        // class from the expression node so the implementor still boxes into
        // the Box<dyn Trait> slot.
        if (!isNullType(expected) && isInterfaceType(expected) && isConcreteConstructor(actual)) {
            return "Box::new(" + boxedInterfacePayload(actual, rendered) + ")";
        }
        // An interface-typed reusable read (a field of an owned object)
        // entering an owned interface slot clones: Haxe's read leaves the
        // source object intact, and Rust's value slot would move the
        // field out of it. (InterfaceSlotClone)
        if (!isNullType(expected) && isInterfaceType(expected) && isInterfaceType(actual.t)
            && !isTypeCopy(actual.t) && isReusableOwnedRead(actual)
            && !StringTools.endsWith(rendered, ".clone()"))
            return rendered + ".clone()";
        // A non-Copy narrowed Option binding names a reference to the inner
        // value; an owned value slot clones the referent so the slot carries
        // the owned type its signature declares.
        if (!isNullType(expected) && isNullType(actual.t)) {
            final narrowed = narrowedSubject(actual);
            if (narrowed != null && !isTypeCopy(getNullInnerType(actual.t)))
                return "(*" + narrowed + ").clone()";
        }
        if (isNullType(expected) && isInterfaceType(getNullInnerType(expected)) && !isNullType(actual.t)) {
            if (rendered == "None" || StringTools.startsWith(rendered, "Some("))
                return rendered;
            // An actual already typed as the interface carries its own
            // Box<dyn Trait>; only a concrete value boxes here. The Option
            // wrapper is the sole addition the nullable slot needs.
            final payload = isInterfaceType(actual.t) ? rendered : "Box::new(" + normalizeConstructorResult(actual, rendered) + ")";
            return "Some(" + payload + ")";
        }
        // Haxe unifies a nullable interface slot's value type to the
        // interface even for a concrete constructor; recover the concrete
        // class so the implementor still boxes into the Option<Box<dyn Trait>>.
        if (isNullType(expected) && isInterfaceType(getNullInnerType(expected)) && isConcreteConstructor(actual)) {
            return "Some(Box::new(" + normalizeConstructorResult(actual, rendered) + "))";
        }
        if (!isInterfaceType(expected) && !isNullType(expected) && isFallibleConstructor(actual)) {
            return normalizeConstructorResult(actual, rendered);
        }
        // Static methods and static function fields are emitted as callable
        // items/pointers, while every non-static function value is already an
        // Arc at its declaration site. Adapt the former only when a ruled
        // Arc-held function slot receives it.
        if (isFunctionType(expected) && isFunctionType(actual.t) && !isBoxedFunctionExpr(actual)) {
            imports.require("std::sync::Arc");
            return "Arc::new(" + rendered + ")";
        }
        return rendered;
    }

    function isBoxedFunctionExpr(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TFunction(_): true;
            case TLocal(_): true;
            case TCall(_, _): true;
            case TField(_, FInstance(_, _, cf)) if (isFunctionType(cf.get().type)): true;
            case TField(_, FStatic(_, _)): false;
            case _: false;
        };
    }

    /** A generic receiver's method field reports its declared parameter
        types with the class type parameters unresolved (TTypeParameter);
        the receiver's applied parameters substitute them so the nullable
        slot adaptations below see the concrete slot types. Monomorphic
        receivers leave the declared types untouched. (AppliedReceiverParams) */
    function appliedReceiverParamTypes(fnType:Type, receiverType:Null<Type>):Null<Array<Type>> {
        if (receiverType == null)
            return null;
        final receiver = Context.follow(receiverType);
        final applied = switch (receiver) {
            case TInst(_, params): params;
            case _: return null;
        };
        if (applied.length == 0)
            return null;
        final names = switch (receiver) {
            case TInst(c, _): [for (p in c.get().params) p.name];
            case _: return null;
        };
        return switch (Context.follow(fnType)) {
            case TFun(pargs, _): [for (p in pargs) substituteClassParams(p.t, names, applied)];
            case _: null;
        };
    }

    function substituteClassParams(t:Type, names:Array<String>, applied:Array<Type>):Type {
        final followed = Context.follow(t);
        // In the macro API a type parameter manifests as a class reference
        // whose kind is KTypeParameter; its name matches the receiver's
        // declared parameter list positionally. (AppliedReceiverParams)
        final pname = switch (followed) {
            case TInst(c, _):
                switch (c.get().kind) {
                    case KTypeParameter(_): c.get().name;
                    case _: null;
                }
            case _: null;
        };
        if (pname != null) {
            var substituted = t;
            for (i in 0...names.length) {
                if (names[i] == pname) {
                    substituted = applied[i];
                    break;
                }
            }
            return substituted;
        }
        return switch (followed) {
            case TInst(c, pl) if (pl.length > 0): TInst(c, [for (p in pl) substituteClassParams(p, names, applied)]);
            case TAbstract(a, pl) if (pl.length > 0): TAbstract(a, [for (p in pl) substituteClassParams(p, names, applied)]);
            case TEnum(e, pl) if (pl.length > 0): TEnum(e, [for (p in pl) substituteClassParams(p, names, applied)]);
            case TType(d, pl) if (pl.length > 0): TType(d, [for (p in pl) substituteClassParams(p, names, applied)]);
            case TFun(fargs, ret):
                TFun([for (a in fargs) {name: a.name, opt: a.opt, t: substituteClassParams(a.t, names, applied)}],
                    substituteClassParams(ret, names, applied));
            case _: t;
        };
    }

    function renderCallArgs(fnType:Null<Type>, args:Array<TypedExpr>, signedPositions:Null<Array<Int>> = null, paramOffset:Int = 0,
            mutablePositions:Null<Array<Int>> = null, receiverType:Null<Type> = null):String {
        final paramTypes = if (fnType != null) {
            final applied = appliedReceiverParamTypes(fnType, receiverType);
            if (applied != null)
                applied;
            else
                switch (Context.follow(fnType)) {
                    case TFun(pargs, _): [for (p in pargs) p.t];
                    case _: [];
                };
        } else [];
        final stdTableReceiver = receiverType != null && isStdTableType(receiverType);
        final rendered = [];
        for (i in 0...args.length) {
            final arg = args[i];
            final paramIndex = i + paramOffset;
            final pt = paramIndex < paramTypes.length ? paramTypes[paramIndex] : null;
            var argStr = renderValueForType(pt, arg, expr(arg));
#if boring_fold_debug
            if (Std.string(arg).indexOf("TInt") >= 0)
                Context.warning("RC INTLIT pt=" + Std.string(pt).substr(0, 50) + " argStr=[" + argStr.substr(0, argStr.length > 20 ? 20 : argStr.length) + "]", arg.pos);
#end
            // A narrowed operand renders the dereferenced match binding (a
            // bare `*name`), which is the inner value; a nullable parameter
            // slot still needs the Option shape, so the value wraps once in
            // Some. (NarrowedNullableParam)
            if (pt != null && isNullType(pt) && StringTools.startsWith(argStr, "*")
                && !StringTools.startsWith(argStr, "*("))
                argStr = "Some(" + argStr + ")";
            // A borrowed match binding (`__option6`) feeding a nullable slot
            // wraps the cloned inner value in Some: the binding itself is a
            // reference into the matched subject. (BorrowedBindingSomeWrap)
            if (pt != null && isNullType(pt) && !isTNull(arg)
                && StringTools.startsWith(argStr, "__option"))
                argStr = "Some((*" + argStr + ").clone())";
            if (pt != null && isNullType(pt) && !isTNull(arg)
                && StringTools.startsWith(argStr, "&(") && StringTools.endsWith(argStr, ")")
                && StringTools.contains(argStr, "__option"))
                argStr = "Some((*" + argStr.substr(2, argStr.length - 3) + ").clone())";
            // A ternary whose else arm is the null literal renders as an
            // Option shape; a non-null slot unwraps it, and the null path
            // panics exactly where the Haxe source would pass an undefined
            // value. (NullElseTernaryUnwrap)
            if (pt != null && !isNullType(pt) && !isNullType(arg.t)) {
                switch (stripWrap(arg).expr) {
                    case TIf(_, _, elseArm) if (elseArm != null && isTNull(elseArm)):
                        argStr = "(" + argStr + ").unwrap()";
                    case _:
                }
            }
            // The mirrored form: a has-guarded get ternary with a zero
            // fallback renders both arms as the inner value; a nullable slot
            // wraps the whole conditional in Some.
            // (NullElseTernaryUnwrap)
            if (pt != null && isNullType(pt) && !isNullType(arg.t)) {
                switch (stripWrap(arg).expr) {
                    case TIf(_, t2, f2):
                        final tt = expr(t2);
                        final et = expr(f2);
                        final zeroElse = (et == "0" || et == "0.0f64" || et == "0.0"
                            || et == "(0 as f64)" || et == "(0.0f64)");
                        if (StringTools.contains(tt, ".unwrap()") && zeroElse)
                            argStr = "Some(" + argStr + ")";
                    case _:
                }
            }
            // A borrowed match binding (`__option6`, bare or wrapped as
            // `&(__option6)`) feeding a nullable slot wraps the cloned inner
            // value in Some: the binding is a reference into the matched
            // subject. (BorrowedBindingSomeWrap)
            if (pt != null && isNullType(pt) && !isNullType(arg.t) && !isTNull(arg)
                && StringTools.startsWith(argStr, "__option"))
                argStr = "Some((*" + argStr + ").clone())";
            if (pt != null && isNullType(pt) && !isNullType(arg.t) && !isTNull(arg)
                && StringTools.startsWith(argStr, "&(") && StringTools.endsWith(argStr, ")")
                && StringTools.contains(argStr, "__option"))
                argStr = "Some((*" + argStr.substr(2, argStr.length - 3) + ").clone())";
            // A proven-non-null nullable local feeding a non-null parameter
            // unwraps the Option at the call boundary so the parameter slot
            // receives the inner value. The guard (early exit or && chain)
            // proved the source is Some; the bridge extracts the payload.
            if (pt != null && !isNullType(pt) && (isNullType(arg.t) || isImplicitNullableLocal(arg))) {
                final proven = switch (stripWrap(arg).expr) {
                    case TLocal(v):
                        provenNonNullVarIds.exists(v.id)
                            || (provenContinueSubjects.exists(subjectTextOf(arg))
                                // An argument whose rendering already
                                // extracted the inner value (a match binding
                                // dereference, a proven unwrap, a zero
                                // bridge) must not gain a second one.
                                && !StringTools.startsWith(argStr, "*")
                                && !StringTools.startsWith(argStr, "(*")
                                && !StringTools.contains(argStr, ".as_ref().unwrap()")
                                && !StringTools.endsWith(argStr, ".unwrap_or(0)")
                                && !StringTools.endsWith(argStr, ".unwrap_or(0.0)"));
                    case _: provenMapGet(arg);
                };
                if (proven && RustShapeParse.shapeOf(argStr) != RustShape.ShapeBare) {
                    final inner = getNullInnerType(arg.t);
                    final ref = "(" + argStr + ").as_ref().unwrap()";
                    argStr = isTypeCopy(inner) ? "*" + ref : ref + ".clone()";
                } else if (hasGuardedGetExpr(arg)
                    // A text that already consumed its Option (the fallible
                    // unwrap suffix) must not gain an as_ref bridge on the
                    // bare value. (BuilderValueNullability, ShapeParse)
                    && RustShapeParse.shapeOf(argStr) != RustShape.ShapeBare) {
                    // A `map.get(key)` under a matching `map.has(key)` guard
                    // holds the inner value; unwrap the Option.
                    final inner = getNullInnerType(arg.t);
                    argStr = isTypeCopy(inner) ? "*((" + argStr + ").as_ref().unwrap())" : "(" + argStr + ").as_ref().unwrap()";
                } else if (switch (stripWrap(arg).expr) {
                    case TLocal(v):
                        nullElseTernaryLocals.exists(v.id) && !isNullType(pt);
                    case TField(_, _):
                        isNullType(arg.t) && StringTools.contains(argStr, ".as_ref().unwrap()");
                    case _: false;
                }) {
                    // A nullable field read on an already-unwrapped chain:
                    // the guard proved the receiver, the field itself stays
                    // nullable and unwraps at the call boundary.
                    // (GuardedChainFieldUnwrap)
                    argStr = "(" + argStr + ").unwrap()";
                } else {
                    // A preceding fill guard (`if (x == null) x = fill;`)
                    // guarantees the local holds Some; the call reads the
                    // inner value through get_or_insert_with so the fill
                    // materializes on the absent path.
                    final filled = filledSubjectOf(arg);
                    if (filled != null) {
                        final inner = getNullInnerType(arg.t);
                        final ref = argStr + ".get_or_insert_with(|| " + filled + ")";
                        argStr = isTypeCopy(inner) ? "*" + ref : ref + ".clone()";
                    } else {
                        // No proof, no guard, no fill: the nullable value
                        // still enters the non-null slot, so the boundary
                        // unwraps it, and the None path panics exactly where
                        // the Haxe source would have dereferenced an
                        // undefined value. Only locals whose declaration
                        // still renders the Option shape qualify: collapsed
                        // locals, non-null-rendered locals, and every
                        // non-local form already render the inner value, so
                        // no unwrap applies. (NonNullSlotUnwrap)
                        final optionRenderedLocal = narrowedSubject(arg) == null
                            && switch (stripWrap(arg).expr) {
                                case TLocal(v): optionRenderedLocals.exists(v.id);
                                case _: false;
                            };
                        if (optionRenderedLocal && RustShapeParse.shapeOf(argStr) != RustShape.ShapeBare) {
                            final inner = getNullInnerType(arg.t);
                            var bare = stripRenderedParens(expr(stripWrap(arg)));
                            if (StringTools.startsWith(bare, "&"))
                                bare = bare.substr(1);
                            final ref = "(" + stripRenderedParens(bare) + ").as_ref().unwrap()";
                            argStr = isTypeCopy(inner) ? "*" + ref : (isPassByRef(pt) ? ref : ref + ".clone()");
                        }
                    }
                }
            }
            // An i32-domain argument crossing into a u32 business parameter
            // reinterprets bits (T5); a same-domain pass (a resident runtime
            // calling another resident runtime) needs no cast.
            if (pt != null && isIntType(pt)) {
                final targetType = types.of(pt, false);
                final sourceType = resolveExprType(arg);
                final signedSource = sourceType == "i32" || rendersSignedIntArg(arg, argStr);
                if (signedSource && targetType == "u32") {
                    argStr = RustConversions.reinterpret(argStr, "u32");
                } else if (sourceType == "u32" && targetType == "i32") {
                    argStr = RustConversions.reinterpret(argStr, "i32");
                }
            }
            if (paramIndex < paramTypes.length) {
#if boring_fold_debug
                if (pt != null && (isNullType(pt) || isNullType(arg.t)))
                    Context.warning("SLOTDBG pt=" + Std.string(pt).substr(0, 50) + " argT=" + Std.string(arg.t).substr(0, 50)
                        + " argStr=" + argStr.substr(0, 60)
                        + " reg=" + (switch (stripWrap(arg).expr) {
                            case TLocal(v): Std.string(optionRenderedLocals.exists(v.id))
                                + "/col=" + Std.string(nullableCollapsedLocals.exists(v.id));
                            case x: Std.string(x).substr(0, 20);
                        }), arg.pos);
#end
                if (isNullType(pt) && isNullType(arg.t)
                    && (isNonNullRenderedLocal(arg) || isNonNullRenderedConditional(arg))
                    && !StringTools.startsWith(argStr, "Some(") && argStr != "None") {
                    // A null-coalesced local or inline ternary usually renders
                    // its inner value (the declaration collapsed the Option);
                    // an Option parameter re-wraps it so the slot's declared
                    // type matches. A local whose null branch stays null
                    // renders as Option already, so it passes through. A
                    // non-Copy payload clones so the source stays usable.
                    final inner = getNullInnerType(pt);
                    if (isStringType(inner) && !StringTools.endsWith(argStr, ".to_string()"))
                        argStr = "Some(" + argStr + ".to_string())";
                    else if (isTypeCopy(inner))
                        argStr = "Some(" + argStr + ")";
                    else
                        argStr = "Some(" + ownedNullableReadText(argStr) + ")";
                } else if (isNullType(pt) && isNullType(arg.t) && narrowedSubject(arg) != null) {
                    // A narrowed Option binding renders as a reference to the
                    // inner value (the match binding); an Option parameter
                    // re-wraps it so the slot's declared type matches. Copy
                    // inners dereference, owned inners clone the referent.
                    final inner = getNullInnerType(pt);
                    if (isTypeCopy(inner))
                        argStr = "Some(*" + narrowedSubject(arg) + ")";
                    else
                        argStr = "Some((*" + narrowedSubject(arg) + ").clone())";
                } else if (isNullType(pt) && isStringType(getNullInnerType(pt)) && isNullType(arg.t)) {
                    // A nullable-typed conditional whose arms are both
                    // non-null renders a plain String (guardedMatchExpression
                    // leaves both arms unwrapped when neither is a null
                    // literal); such a value must wrap in Some at the Option
                    // parameter boundary. A nullable local or field renders
                    // as an Option and keeps the clone. A nullable-collapsed
                    // local already holds the inner String and wraps in Some.
                    if (isNonNullRenderedConditional(arg) || isNullableCollapsedLocal(arg))
                        argStr = "Some(" + argStr + ")";
                    else
                        argStr = argStr + ".clone()";
                } else if (isNullType(pt) && isNullType(arg.t) && isNonNullRenderedConditional(arg)) {
                    // A nullable-typed conditional whose arms are both
                    // non-null renders a plain scalar (a null-guard match
                    // leaves both arms unwrapped); the Option parameter
                    // boundary wraps it in Some.
                    argStr = "Some(" + argStr + ")";
                } else if (isNullType(pt) && (!isNullType(arg.t) || isNullableCollapsedLocal(arg))) {
                    if (argStr == "None" || StringTools.startsWith(argStr, "Some(")) {
                        // already None or Some(...)
                    } else {
                        final inner = switch (stripWrap(arg).expr) {
                            case TConst(TString(s)): quoteString(s) + ".to_string()";
                            case _ if (isStringType(getNullInnerType(pt)) && isStringType(arg.t)):
                                StringTools.endsWith(argStr, ".to_string()") ? argStr : "(" + argStr + ").to_string()";
                            case _ if (isFloatType(getNullInnerType(pt)) && isIntType(emittedType(arg))):
                                intToFloatText(argStr);
                            case _ if (isOwnedVecType(getNullInnerType(pt))):
                                nullableArrayPayload(arg, argStr);
                            case _:
                                if (isInterfaceType(getNullInnerType(pt)) && !isInterfaceType(arg.t))
                                    renderValueForType(getNullInnerType(pt), arg, argStr);
                                else if (isReusableNullableRead(pt, arg, argStr))
                                    ownedNullableReadText(argStr);
                                else
                                    argStr;
                        };
                        argStr = "Some(" + inner + ")";
                    }
                } else if (RustType.isTypeParam(pt)) {
#if boring_fold_debug
                    Context.warning("RC tp-branch pt=" + Std.string(pt).substr(0, 30), arg.pos);
#end
                    final borrowed = switch (stripWrap(arg).expr) {
                        case TLocal(v): isBorrowedLocal(v);
                        case _: false;
                    };
                    if (isStringType(arg.t)) {
                        // A generic T is owned in its return position. A Haxe
                        // String argument therefore specializes T as String,
                        // even when the source expression itself is a borrowed
                        // string parameter or a literal.
                        argStr = "&(" + argStr + ").to_string()";
                    } else if (!borrowed && !StringTools.startsWith(argStr, "&")) {
                        argStr = "&(" + argStr + ")";
                    }
                } else if (isPassByRef(pt)) {
                    final provenString = switch (stripWrap(arg).expr) {
                        case TLocal(v) if (provenNonNullVarIds.exists(v.id) && isNullType(arg.t) && isStringType(pt)): true;
                        case _: false;
                    };
                    // A null-checked nullable array passed to a borrowed Array
                    // parameter unwraps the Option to its Vec view. A local
                    // whose null-coalescing initializer materialized the inner
                    // value already renders non-null and keeps its borrow.
                    final argRendersNullable = isNullType(arg.t) && !(switch (stripWrap(arg).expr) {
                        case TLocal(v): nullableCollapsedLocals.exists(v.id)
                            || hasGuardedTernaryLocals.exists(v.id);
                        case _: false;
                    });
                    final nullableArrayParam = argRendersNullable
                        && isArrayType(getNullInnerType(arg.t))
                        && isArrayType(pt);
                    if (provenString) {
                        argStr = expr(arg) + ".as_deref().unwrap_or(\"\")";
                    } else if (nullableArrayParam) {
                        // A narrowed arg already renders as the match binding,
                        // a reference to the inner Vec; unwrapping it again
                        // would ask Vec for an as_ref that does not exist.
                        final narrowed = narrowedSubject(arg);
                        argStr = narrowed != null ? expr(arg)
                            : (RustShapeParse.shapeOf(expr(arg)) != RustShape.ShapeBare ? "(" + expr(arg) + ").as_ref().unwrap()" : expr(arg));
                    } else {
                        // The mutating faces are arrays and the writer and reader
                        // fronts; every other borrowed parameter reads only.
                        final isArray = switch (Context.follow(pt)) {
                            case TInst(c, _): c.get().name == "Array";
                            default: false;
                        };
                        // A compile-time data table is a static declared at file scope:
                        // it borrows immutably even where the parameter
                        // accepts mutation.
                        final isTableArg = switch (stripWrap(arg).expr) {
                            case TField(_, FStatic(_, tableField)): DataTableHelper.isDataTableField(tableField.get());
                            case _: false;
                        };
                        final isMutableBuffer = switch (Context.follow(pt)) {
                            case TInst(c, _): c.get().name == "StringBuf";
                            case _: false;
                        };
                        final prefix = if (isMutableBuffer
                            || (isArray
                                && !isTableArg
                                && (mutablePositions != null && mutablePositions.indexOf(paramIndex) >= 0))) {
                            switch (stripWrap(arg).expr) {
                                case TLocal(v) if (isBorrowedLocal(v)): "&mut *";
                                case _: "&mut ";
                            }
                        } else "&";
                        if (isMutableBuffer || (isArray && !isTableArg && mutablePositions != null && mutablePositions.indexOf(paramIndex) >= 0)) {
                            final borrowedArg = switch (stripWrap(arg).expr) {
                                case TLocal(v): isBorrowedLocal(v);
                                case _: false;
                            };
                            if (borrowedArg) {
                                // Already borrowed; leave the expression unchanged.
                            } else if (StringTools.startsWith(argStr, "&"))
                                argStr = "&mut " + (StringTools.startsWith(argStr, "&mut ") ? argStr.substr(5) : argStr.substr(1));
                            else
                                argStr = "&mut " + argStr;
                        } else if (!StringTools.startsWith(argStr, "&")) {
                            argStr = prefix + argStr;
                        }
                    }
#if boring_fold_debug
                    if (Std.string(arg).indexOf("TInt") >= 0)
                        Context.warning("RC4 std=" + stdTableReceiver + " lenOK=" + (i < paramTypes.length) + " num=" + (i < paramTypes.length && isNumericScalarType(paramTypes[i]) ? true : false) + " pt=" + Std.string(i < paramTypes.length ? paramTypes[i] : null).substr(0, 30), arg.pos);
#end
                    if (stdTableReceiver && stringLikeType(pt) && stringLikeType(arg.t)
                        && switch (stripWrap(arg).expr) {
                            case TConst(TString(_)): true;
                            case _: false;
                        }) {
                        // A string literal key of a std table owns its
                        // storage: the table key is a String, so the literal
                        // converts once at the boundary.
                        // (AppliedReceiverParams)
                        argStr = "&(" + argStr + ").to_string()";
                    }
                    if (stdTableReceiver && i < paramTypes.length
                        && isNumericScalarType(paramTypes[i])
                        && switch (stripWrap(arg).expr) {
                            case TConst(TInt(_)): true;
                            case _: false;
                        }) {
                        // A business Int literal entering a std table slot
                        // names the u32 domain explicitly so the borrow
                        // targets the slot's element type.
                        // (AppliedReceiverParams)
#if boring_fold_debug
                        Context.warning("RC11711 fired", arg.pos);
#end
                        argStr = "&(" + argStr + "u32)";
                    }
                    if (!stdTableReceiver && stringLikeType(pt) && stringLikeType(arg.t)) {
                        argStr = switch (stripWrap(arg).expr) {
                            case TConst(TString(_)): argStr;
                            case _ if (nullableStringViewArg(arg)): "(" + expr(arg) + ").as_deref().unwrap_or(\"\")";
                            case TLocal(v) if (isBorrowedParamLocal(v)): expr(arg);
                            case _: expr(arg) + ".as_str()";
                        };
                    }
                } else if (isRecordValueType(arg.t) && switch (stripWrap(arg).expr) {
                    case TLocal(_): true;
                    case _: false;
                    }) {
                    argStr = StringTools.startsWith(argStr, "&") ? "(*" + argStr + ").clone()" : "(" + argStr + ").clone()";
                    } else if (!isPassByRef(pt)
                    && !isTypeCopy(arg.t)
                    && isReusableOwnedRead(arg)
                    && !StringTools.startsWith(argStr, "&")
                    && !StringTools.endsWith(argStr, ".clone()")
                    && !StringTools.endsWith(argStr, ".to_vec()")
                    && !StringTools.endsWith(argStr, ".to_string()")) {
                    final provenEnum = switch (stripWrap(arg).expr) {
                        case TLocal(v) if (provenNonNullVarIds.exists(v.id) && isNullType(arg.t)): true;
                        case _: false;
                    };
                    if (provenEnum)
                        argStr = expr(arg) + ".unwrap()";
                    else
                        argStr = ownedReadCloneText(arg, argStr);
                }
                // A nullable Bool argument into a non-null Bool parameter:
                // Haxe's null-to-Bool coercion is false, so the boundary
                // supplies it. (NullableBoolCoercion)
                if (i < paramTypes.length && pt != null && !isNullType(pt)
                    && isBoolType(pt) && isNullType(arg.t) && !isTNull(arg)
                    // Only the caller's own nullable parameter binding is
                    // guaranteed to hold Option storage here.
                    && switch (stripWrap(arg).expr) {
                        case TLocal(v): paramVarIds.exists(v.id);
                        case _: false;
                    })
                    argStr = argStr + ".unwrap_or(false)";
                // A collection length is usize in Rust while a Haxe Int
                // function parameter is u32 in business modules. The
                // declared function type is the call boundary, so narrow
                // exactly there (the same convention as buf.len() as u32); the
                // stored function type remains unchanged.
                if (isIntType(pt) && isUsizeExpr(arg) && (signedPositions == null || signedPositions.indexOf(i) < 0)) {
                    final targetType = types.of(pt, false);
                    if (targetType == "u32") {
                        argStr = RustConversions.truncate(argStr, "u32");
                    } else if (targetType == "i32") {
                        argStr = RustConversions.narrowI32(argStr);
                    }
                }
            }
            if (signedPositions != null && signedPositions.indexOf(i) >= 0) {
                // The position is a resident i32 slot: fold a literal,
                // leave a resident caller's i32 value bare, and reinterpret
                // a business u32 value (T5).
                argStr = castSignedI32(arg);
            }
            // A std-table put's value slot borrows (&V): an integer
            // literal entering a std table names the u32 domain and takes
            // the borrow. The pass-by-ref adaptations above skip plain
            // numeric parameters, so this boundary owns the literal form.
            // (AppliedReceiverParams)
            if (stdTableReceiver && pt != null && !isPassByRef(pt)
                && isNumericScalarType(pt)
                && switch (stripWrap(arg).expr) {
                    case TConst(TInt(_)): true;
                    case _: false;
                })
                argStr = "&(" + argStr + "u32)";
            rendered.push(argStr);
        }
        return rendered.join(", ");
    }

    /**
        reusableOwnedRead: value arguments are evaluated as Haxe reads and may
        be used again. Clone locals, direct field reads, and the borrowed `self`
        receiver at an owned value boundary; constructors, calls, and object
        literals already produce fresh ownership. This covers fields of local
        records and objects without cloning arbitrary expressions.
    **/
    function isReusableOwnedRead(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TConst(TThis): true;
            case TLocal(_) | TField(_, _): true;
            case _: false;
        };
    }

    function isTemporaryOwnedExpr(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TFunction(_) | TNew(_, _, _) | TObjectDecl(_): true;
            case _: false;
        };
    }

    function isUsizeExpr(e:TypedExpr):Bool {
        if (e == null)
            return false;
        return switch (stripWrap(e).expr) {
            case TField(subj, fa) if (fieldName(fa) == "length" || fieldName(fa) == "get_length"):
                return false;
            case TBinop(OpAdd | OpSub | OpMult | OpDiv, l, r): isUsizeExpr(l) || isUsizeExpr(r);
            default: false;
        };
    }

    function isScalarType(t:Type):Bool {
        final followed = Context.follow(t);
        return switch (followed) {
            case TAbstract(a, _): final name = a.get().name; name == "Bool" || name == "Int" || name == "Float";
            case TInst(c, _):
                c.get().name == "String";
            case _: false;
        };
    }

    function scalarTypeKind(t:Type):String {
        final followed = Context.follow(t);
        return switch (followed) {
            case TAbstract(a, _): a.get().name;
            case TInst(c, _): c.get().name;
            case _: "Unknown";
        };
    }

    function recordAggregateType(t:Type):Void {
        switch (t) {
            case TInst(c, params):
                final cls = c.get();
                if (cls.name == "Array") {
                    final key = "Array_" + formatTypeKey(params[0]);
                    if (!state.testReachableTypes.exists(key)) {
                        state.testReachableTypes.set(key, t);
                        recordAggregateType(params[0]);
                    }
                } else if (cls.name == "Bytes" || (cls.pack.join(".") == "haxe.io" && cls.name == "Bytes")) {
                    if (!state.testReachableTypes.exists("Bytes")) {
                        state.testReachableTypes.set("Bytes", t);
                    }
                }
            case TAbstract(a, params) if (a.get().name == "ReadOnlyArray"
                || (a.get().pack.join(".") == "std" && a.get().name == "ReadOnlyArray")):
                final key = "Array_" + formatTypeKey(params[0]);
                if (!state.testReachableTypes.exists(key)) {
                    state.testReachableTypes.set(key, t);
                    recordAggregateType(params[0]);
                }
            case TType(def, params):
                final d = def.get();
                final key = d.module + "." + d.name;
                if (!state.testReachableTypes.exists(key)) {
                    state.testReachableTypes.set(key, t);
                    switch (d.type) {
                        case TAnonymous(anon):
                            for (f in anon.get().fields) {
                                recordAggregateType(f.type);
                            }
                        case _:
                    }
                }
            case TEnum(e, params):
                final en = e.get();
                final key = en.module + "." + en.name;
                if (!state.testReachableTypes.exists(key)) {
                    state.testReachableTypes.set(key, t);
                }
            case _:
        }
    }

    function formatTypeKey(t:Type):String {
        return switch (t) {
            case TAbstract(a, params):
                if (a.get().name == "ReadOnlyArray" || (a.get().pack.join(".") == "std" && a.get().name == "ReadOnlyArray")) "Array_"
                    + formatTypeKey(params[0]) else a.get().name;
            case TInst(c, params):
                final cls = c.get();
                if (cls.name == "Array") "Array_" + formatTypeKey(params[0]); else if (cls.name == "Bytes"
                    || (cls.pack.join(".") == "haxe.io" && cls.name == "Bytes")) "Bytes"; else cls.module + "." + cls.name;
            case TType(def, params): def.get().module + "." + def.get().name;
            case TEnum(e, params): e.get().module + "." + e.get().name;
            case _: "Unknown";
        };
    }

    function aggregateAssertFuncName(t:Type):String {
        return switch (t) {
            case TInst(c, params) if (c.get().name == "Array"):
                "assert_equals_vec_" + typeSafeSnake(params[0]);
            case TAbstract(a, params) if (a.get().name == "ReadOnlyArray"
                || (a.get().pack.join(".") == "std" && a.get().name == "ReadOnlyArray")):
                "assert_equals_vec_" + typeSafeSnake(params[0]);
            case TInst(c, _) if (c.get().name == "Bytes" || (c.get().pack.join(".") == "haxe.io" && c.get().name == "Bytes")):
                "assert_equals_bytes";
            case TType(def, _):
                "assert_equals_" + RustImports.toSnakeCase(def.get().name);
            case TEnum(e, _):
                "assert_equals_" + RustImports.toSnakeCase(e.get().name);
            case _: "assert_equals_unknown";
        };
    }

    function typeSafeSnake(t:Type):String {
        return switch (t) {
            case TAbstract(a, _):
                switch (a.get().name) {
                    case "Int": "u32";
                    case "Float": FloatPrecision.isF32() ? "f32" : "f64";
                    case "Bool": "bool";
                    case "String": "string";
                    case _: RustImports.toSnakeCase(a.get().name);
                }
            case TInst(c, _):
                switch (c.get().name) {
                    case "String": "string";
                    case "Bytes": "bytes";
                    case _: RustImports.toSnakeCase(c.get().name);
                }
            case TType(def, _): RustImports.toSnakeCase(def.get().name);
            case TEnum(e, _): RustImports.toSnakeCase(e.get().name);
            case _: "unknown";
        };
    }

    function renderOptArg(e:TypedExpr, kind:String):String {
        // Both sides must reach the helper as Option. A Null-typed
        // expression already lowers to Option; any other expression
        // renders the inner value and is wrapped into Some. The String
        // kind clones because the same local may be borrowed by the
        // actual argument of the same call.
        return switch (e.expr) {
            case TConst(TNull): kind == "String" ? "None::<String>" : "None::<u32>";
            case _ if (isNullType(e.t)): expr(e);
            case TConst(TString(s)) if (kind == "String"): "Some(" + quoteString(s) + ".to_string())";
            case TConst(TInt(i)) if (kind == "Int"): "Some(" + Std.string(i) + ")";
            case _: kind == "String" ? "Some(" + expr(e) + ".clone())" : "Some(" + expr(e) + ")";
        };
    }

    /**
     * Nullable container indexing policy: Haxe permits indexing a nullable
     * container after its runtime null contract has been established. Rust
     * still sees Option<T>, so extract T only when the typed receiver remains
     * a Rust fallible wrapper. Non-nullable containers retain direct indexing.
     * The mutable form is used only for indexed assignment.
     */
    function optionContainerIndexAccess(arr:TypedExpr, idx:TypedExpr, mutable:Bool):String {
        final receiver = expr(arr);
        // A narrowed receiver already renders as the match binding, a
        // reference to the inner Vec (match &(opt) { Some(name) => ... }).
        // Applying `.as_ref().unwrap()` to that reference would ask Vec for
        // an as_ref that does not exist (E0282 on the element type); the
        // binding is already the unwrapped container.
        final narrowed = narrowedSubject(arr);
        if (narrowed != null) {
            return "(" + receiver + ")" + "[" + castArg(idx, "usize") + "]";
        }
        // Nullable container indexing can lose the Null abstract in macro
        // type following while the emitted receiver remains Option<Vec<T>>.
        // Use the emitted Rust boundary contract so indexing never targets
        // the Option itself (NullableContainerIndexing).
        final emittedReceiverType = arr.t == null ? "" : types.of(arr.t, false);
        final emittedOptionContainer = StringTools.startsWith(emittedReceiverType, "Option<");
        // A has-guarded ternary local holds the bare inner container (its
        // declaration unwrapped the Option); indexing targets the Vec
        // directly. (HasGuardedTernaryLocals)
        final guardedCollapse = switch (stripWrap(arr).expr) {
            case TLocal(v): nullableCollapsedLocals.exists(v.id)
                || hasGuardedTernaryLocals.exists(v.id);
            case _: false;
        };
        final unwrapOption = !guardedCollapse
            && (isNullType(arr.t) || receiverCarriesFallibleWrapper(arr) || emittedOptionContainer);
        if (unwrapOption) {
            final coerce = mutable ? ".as_mut().unwrap()" : ".as_ref().unwrap()";
            return "(" + receiver + ")" + coerce + "[" + castArg(idx, "usize") + "]";
        }
        final receiverText = StringTools.startsWith(receiver, "&*") ? "(" + receiver + ")" : receiver;
        return receiverText + "[" + castArg(idx, "usize") + "]";
    }

    function arrayArgBorrow(e:TypedExpr):String {
        // A direct array access can be borrowed without the value-read
        // clone; the borrow consumers above do not need the copy.
        return switch (e.expr) {
            case TArray(arr, idx): optionContainerIndexAccess(arr, idx, false);
            case _: expr(e);
        };
    }

    function isNullType(t:Type):Bool {
        if (t == null)
            return false;
        return switch (t) {
            case TAbstract(a, _): a.get().name == "Null";
            case _: false;
        };
    }

    function isBoolType(t:Type):Bool {
        if (t == null)
            return false;
        return switch (Context.follow(t)) {
            case TAbstract(a, _): a.get().name == "Bool";
            case _: false;
        };
    }

    /** Strips every Null wrapper (the typer can double-wrap a ternary
        joining null with an interface-valued call as Null<Null<T>>).
        (DoubleNullableFlatten) */
    function flattenNullable(t:Type):Type {
        var cur = t;
        var guard = 0;
        while (isNullType(cur) && guard < 4) {
            cur = getNullInnerType(cur);
            guard++;
        }
        return cur;
    }

    function getNullInnerType(t:Type):Type {
        return switch (t) {
            case TAbstract(a, params) if (a.get().name == "Null"): params[0];
            case _: t;
        };
    }

    function isInt64Type(t:Type):Bool {
        if (t == null)
            return false;
        return StringTools.contains(Std.string(Context.follow(t)), "Int64");
    }

    public function isFloatType(t:Type):Bool {
        if (t == null)
            return false;
        return switch (Context.follow(t)) {
            case TAbstract(a, _): a.get().name == "Float";
            case _: false;
        };
    }

    /** Convert an integer expression text to Float (as f64 / as f32). */
    public function intToFloatText(text:String):String {
        final precision = FloatPrecision.isF32() ? "f32" : "f64";
        // Call-site rendering may already parenthesize integer literals. Avoid
        // producing redundant parentheses around the resulting cast.
        if (~/^\(-?[0-9]+\)$/.match(text))
            return text.substr(1, text.length - 2) + " as " + precision;
        // Literal call arguments are already parenthesized by expression
        // lowering; normalize the cast itself so `(8 as f64)` is avoided.
        if (~/^-?[0-9]+$/.match(text))
            return text + " as " + precision;
        // Function calls, method calls, and parenthesized expressions are
        // already atomic; the `as` cast binds tighter than any surrounding
        // binary operator so wrapping them in extra parentheses is redundant.
        if (~/\)$/.match(text))
            return text + " as " + precision;
        return "(" + text + " as " + precision + ")";
    }

    /**
        The "emitted" type of an expression: the type of the value the
        generator will actually emit as text. Haxe unification types
        Int-as-Float contexts as Float while the generator still emits
        Int text for the original Int sub-expression.
     */
    public function emittedType(e:TypedExpr):Null<Type> {
        switch (stripWrap(e).expr) {
            case TConst(TInt(_)):
                return Context.getType("Int");
            case TIf(_, t, f):
                final tt = emittedType(t);
                return tt != null ? tt : emittedType(f);
            case TBinop(op, l, r):
                switch (op) {
                    case OpAdd | OpSub | OpMult | OpDiv | OpMod:
                        final lt = emittedType(l);
                        final rt = emittedType(r);
                        // Haxe widens an arithmetic result to Float when
                        // either operand is Float, so the emitted type follows
                        // the Float operand before the Int one.
                        if (lt != null && isFloatType(lt))
                            return lt;
                        if (rt != null && isFloatType(rt))
                            return rt;
                        if (lt != null && isIntType(lt))
                            return lt;
                        return rt;
                    case OpEq | OpNotEq | OpGt | OpGte | OpLt | OpLte:
                        final lt = emittedType(l);
                        if (lt != null)
                            return lt;
                        return emittedType(r);
                    case _:
                }
            case TLocal(v):
                return e.t;
            case TField(_, _):
                return e.t;
            case TCall(_, _):
                return e.t;
            case TParenthesis(inner):
                return emittedType(inner);
            case TCast(inner, _):
                return emittedType(inner);
            case _:
        }
        return e.t;
    }

    public function isIntType(t:Type):Bool {
        if (t == null)
            return false;
        return switch (Context.follow(t)) {
            case TAbstract(a, _): a.get().name == "Int";
            case _: false;
        };
    }

    /** Whether a division reads a length and divides by an Int, the
        shape the OpDiv lowering renders as truncating integer
        division; a general Int/Int division lowers through the module
        real (f64 by default, f32 under the precision switch). */
    function isLengthDivision(e:TypedExpr):Bool {
        return switch (e.expr) {
            case TBinop(OpDiv, l, r): isIntType(r.t) && StringTools.endsWith(operand(l, OpDiv, false), ".len()");
            case _: false;
        };
    }

    /** An Int/Int division under Std.int, which truncates the Float
        quotient: Rust integer division on the same operands matches, so
        the division renders without the Float round-trip. Returns null
        when the operand is not such a division. */
    function intDivisionOf(e:TypedExpr):Null<String> {
        return switch (stripWrap(e).expr) {
            case TBinop(OpDiv, l, r) if (isIntType(l.t) && isIntType(r.t)):
                switch (stripWrap(r).expr) {
                    case TConst(TInt(k)) if (k != 0): "(" + expr(l) + ") / (" + expr(r) + ")";
                    case _: null;
                };
            case _: null;
        };
    }

    /** The parameter positions of one function type that carry Int. */
    function intParamPositions(fnType:Null<Type>):Null<Array<Int>> {
        if (fnType == null)
            return null;
        return switch (Context.follow(fnType)) {
            case TFun(pargs, _):
                final positions:Array<Int> = [];
                for (i in 0...pargs.length) {
                    if (isIntType(pargs[i].t)) {
                        positions.push(i);
                    }
                }
                positions;
            case _: null;
        };
    }

    /** Whether one function type returns Int. */
    function returnsInt(fnType:Null<Type>):Bool {
        if (fnType == null)
            return false;
        return switch (Context.follow(fnType)) {
            case TFun(_, ret): isIntType(ret);
            case _: false;
        };
    }

    /** Whether a type mentions a type parameter through any wrapper. */
    function typeHasParam(t:Null<Type>):Bool {
        if (t == null)
            return false;
        if (RustType.isTypeParam(t))
            return true;
        return switch (t) {
            case TAbstract(a, params): [for (p in params) typeHasParam(p)].indexOf(true) >= 0;
            case TInst(_, params): [for (p in params) typeHasParam(p)].indexOf(true) >= 0;
            case TFun(pargs, ret): [for (p in pargs) typeHasParam(p.t)].indexOf(true) >= 0 || typeHasParam(ret);
            case TLazy(f): typeHasParam(f());
            case _: false;
        };
    }

    /** Whether the expression is a call to a generic static function. */
    function genericStaticCallArg(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TCall(fn, _): switch (stripWrap(fn).expr) {
                    case TField(_, FStatic(_, cf)): typeHasParam(cf.get().type);
                    case _: false;
                };
            case _: false;
        };
    }

    function isStringBuf(e:TypedExpr):Bool {
        return PolicyQueries.isStringBuf(e);
    }

    function isTNull(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TConst(TNull): true;
            default: false;
        };
    }

    /**
        A nullable-typed null-guard conditional (`x == null ? A : B` or
        `x != null ? A : B`) whose arms are both non-null renders as a
        plain value: guardedMatchExpression narrows the subject to its
        match binding and leaves both arms unwrapped when neither is a null
        literal, so the match yields the inner type while the result type
        stays nullable. A local subject narrows to the inner value; a
        field subject keeps the match binding but still renders the bare
        inner value (the null-guard only fires on a nullable subject, so
        the narrowed arm's type is always nullable and the outer Some wrap
        in guardedMatchExpression never applies). Either way the argument
        must wrap in Some at an Option parameter boundary.
    **/
    function isNonNullRenderedConditional(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TIf(cond, ifTrue, ifFalse) if (ifFalse != null):
                final guard = nullGuardOf(cond);
                if (guard == null || isTNull(ifTrue) || isTNull(ifFalse))
                    return false;
                // A nullable interface result wraps both arms in Some inside
                // the match (the nullableResult rule in
                // guardedMatchExpression), so the conditional renders an
                // Option value and a method receiver on it still needs the
                // as_ref forcing read.
                if (isNullType(e.t) && isInterfaceType(getNullInnerType(e.t))
                    && (isConcreteConstructor(ifTrue) || isConcreteConstructor(ifFalse)))
                    return false;
                true;
            case _: false;
        };
    }

    /** A null-guarded ternary whose arms are both non-null renders a plain
        value (guardedMatchExpression renders it as a plain String match),
        including the case where the guard subject is a field. **/
    function isNullGuardedTernary(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TIf(cond, ifTrue, ifFalse) if (ifFalse != null):
                final guard = nullGuardOf(cond);
                guard != null && !isTNull(ifTrue) && !isTNull(ifFalse);
            case _: false;
        };
    }

    /**
        One branch of a two-arm conditional. A string literal renders as
        &str while a sibling member call that returns an owned String
        renders as String; Rust rejects the mismatched pair as one
        expression, so the lone literal branch converts. Two literals stay
        &str on both arms, and a sibling that renders as a borrow keeps
        the literal as &str too.
    **/
    function conditionalBranchText(branch:TypedExpr, sibling:TypedExpr, resultType:Null<Type> = null):String {
        final text = expr(branch);
        if (resultType != null && isStringType(resultType)) {
            if (StringTools.endsWith(text, ".to_string()") || StringTools.endsWith(text, ".clone()"))
                return text;
            return text + ".to_string()";
        }
        if (text.indexOf("u_string::count") >= 0 && resolveExprType(sibling) == "i32") {
            return RustConversions.reinterpret(text, "i32");
        }
        if (!isStringType(branch.t) || !isStringType(sibling.t)) {
            return text;
        }
        if (!isStringLiteral(branch) || isStringLiteral(sibling)) {
            return text;
        }
        final siblingText = expr(sibling);
        final ownedStringCall = StringTools.endsWith(siblingText, ".to_string()")
            || StringTools.endsWith(siblingText, ".to_string()?")
            || StringTools.endsWith(siblingText, ".to_string().unwrap()");
        return ownedStringCall ? text + ".to_string()" : text;
    }

    /** Renders an if-else branch, wrapping a non-null branch in Some(...) when
        the result type is nullable, so both arms produce matching Option
        values. Haxe's ternary type is the join of its arms; a non-null arm
        joined with a nullable one is nullable, and Rust's if-else requires
        matching arm types. Preserves the string conversions that
        conditionalBranchText applies. **/
    function wrapBranchForNullableResult(branch:TypedExpr, resultType:Null<Type>, sibling:TypedExpr):String {
        final text = expr(branch);
        if (resultType != null && isNullType(resultType)) {
            // A null-literal arm of a nullable result renders as None; an
            // already-nullable arm keeps its Option shape; any other arm
            // wraps in Some(...) with the string coercion applied inside.
            if (isTNull(branch))
                return "None";
            // A collapsed or forcing-read local renders the bare inner
            // value: it must not return early, it falls through to the Some
            // wrapper so both arms share the slot's Option shape.
            // (NullableReturnUnwrap)
            final branchLocalId = switch (stripWrap(branch).expr) {
                case TLocal(v): v.id;
                case _: -1;
            };
            if ((isNullType(branch.t) || StaticFieldHelper.isNullableType(branch.t))
                && !isNullableCollapsedLocal(branch) && !forcingReadLocals.exists(branchLocalId))
                return text;
            final inner = getNullInnerType(resultType);
            final coerced = coerceBranchText(branch, text, inner, sibling);
            // A concrete implementor branch of a Null<Interface> result
            // boxes inside the Some; an already-interface-typed branch is
            // already boxed by its declaration site. Haxe unifies a
            // concrete constructor's branch type to the interface, so the
            // concrete class is recovered from the expression node.
            if (isInterfaceType(inner) && (!isInterfaceType(branch.t) || isConcreteConstructor(branch))) {
                return "Some(Box::new(" + normalizeConstructorResult(branch, coerced) + ") as " + types.of(inner, false) + ")";
            }
            return "Some(" + coerced + ")";
        }
        return coerceBranchText(branch, text, resultType, sibling);
    }

    /** The non-nullable arm coercions: owned-string conversion and the
        u_string count reinterpret, applied unchanged for both result
        shapes. **/
    function coerceBranchText(branch:TypedExpr, text:String, resultType:Null<Type>, sibling:TypedExpr):String {
        // A concrete arm of a nullable interface result boxes before the
        // Some wrapper. The cast pins the arm to the trait object, so a
        // local initialized from the conditional infers the boxed shape.
        if (resultType != null && isNullType(resultType) && isInterfaceType(getNullInnerType(resultType))
            && !isInterfaceType(branch.t))
            return "Box::new(" + text + ") as " + types.of(getNullInnerType(resultType), false);
        if (resultType != null && isStringType(resultType)) {
            if (StringTools.endsWith(text, ".to_string()") || StringTools.endsWith(text, ".clone()"))
                return text;
            return text + ".to_string()";
        }
        // An owned Vec result slot that receives a borrowed array parameter
        // clones the referent, so both arms of the conditional carry one
        // Rust type.
        if (resultType != null && isOwnedVecType(resultType) && borrowedArrayRead(branch)) {
            return "(*" + text + ").clone()";
        }
        if (text.indexOf("u_string::count") >= 0 && resolveExprType(sibling) == "i32") {
            return RustConversions.reinterpret(text, "i32");
        }
        return text;
    }

    function matchGroupByBody(body:Array<TypedExpr>):Null<{
        prefix:Array<TypedExpr>,
        entryVar:TVar,
        entryInit:TypedExpr,
        builderSubj:TypedExpr,
        keyArg:TypedExpr,
        valArg:TypedExpr
    }> {
        if (body.length == 0)
            return null;
        final last = body[body.length - 1];
        final coreStmts:Null<Array<TypedExpr>> = switch (last.expr) {
            case TBlock(s) if (s.length == 4): s;
            default:
                if (body.length == 4) body else null;
        };
        if (coreStmts == null)
            return null;
        final prefix = if (coreStmts == body) [] else body.slice(0, body.length - 1);
        final entry = switch (coreStmts[0].expr) {
            case TVar(v, init) if (init != null): {v: v, init: init};
            default: return null;
        };
        final builderInfo = switch (coreStmts[1].expr) {
            case TVar(bucketV, init) if (init != null):
                switch (stripWrap(init).expr) {
                    case TCall(fn, args) if (args.length == 1):
                        switch (fn.expr) {
                            case TField(subj, fa) if (fieldName(fa) == "get" && (isSortedTable(subj) || isSortedBuilder(subj))):
                                {bucketVar: bucketV, builderSubj: subj, keyArg: args[0]};
                            default: return null;
                        }
                    default: return null;
                }
            default: return null;
        };
        if (builderInfo == null)
            return null;
        final pushInfo = switch (coreStmts[coreStmts.length - 1].expr) {
            case TCall(fn, args) if (args.length == 1):
                switch (fn.expr) {
                    case TField(subj, fa) if (fieldName(fa) == "push"):
                        switch (stripWrap(subj).expr) {
                            case TLocal(v) if (v.id == builderInfo.bucketVar.id):
                                {valArg: args[0]};
                            default: return null;
                        }
                    default: return null;
                }
            default: return null;
        };
        if (pushInfo == null)
            return null;
        return {
            prefix: prefix,
            entryVar: entry.v,
            entryInit: entry.init,
            builderSubj: builderInfo.builderSubj,
            keyArg: builderInfo.keyArg,
            valArg: pushInfo.valArg
        };
    }
}
#end
