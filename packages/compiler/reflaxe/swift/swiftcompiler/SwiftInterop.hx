package swiftcompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.macro.Type.AbstractType;
import haxe.macro.Type.ClassField;
import haxe.macro.Type.ClassType;
import haxe.macro.Type.TypedExpr;
import StringTools;

/**
    The declaration-side interface for C interop on the Swift target.

    The target emits one Swift module, so references between generated Haxe
    modules never need imports; a platform framework is the exception because
    its symbols live in another Swift module. `:swiftImport` names that
    dependency on the source declaration whose generated file needs it, so the
    import is scoped to that file, never a build-wide switch.

    A C API wants a representation the translatable subset does not have (a
    CFString, a C string pointer, a buffer pointer) while the Haxe value is a
    String. `:swiftNativeType` on an abstract gives the abstract a Swift
    spelling while Haxe still sees its underlying type, and `:swiftBridge`
    on that abstract declares how the underlying value becomes the native
    type at an extern argument position. The bridge may declare a lifetime
    bracket: a C string or a buffer pointer is valid only inside
    `withCString` / `withUnsafeBufferPointer`, which a plain argument
    expression cannot express.

    A `CF_ENUM` member reaches Swift under a derived spelling
    (`CTFontUIFontType.system`) while the C name (`kCTFontUIFontSystem`) is
    not in scope, so `:swiftName` on a `:topLevel` extern static overrides
    the emitted spelling. The same override admits initializer-shaped seams
    such as `Int`.

    Metadata shapes:

        @:swiftImport("CoreText", "CoreGraphics")
        @:swiftNativeType("CFString")
        @:swiftBridge("String", "String(decoding: $0, as: UTF16.self) as CFString")
        @:swiftNativeType("UnsafePointer<CChar>")
        @:swiftBridge("String", "String(decoding: $0, as: UTF16.self)",
            "$0.withCString { $1 in $body }", "$1")
        @:topLevel @:swiftName("CTFontUIFontType.system")
        static final kCTFontUIFontSystem:CTFontUIFontType;
**/
class SwiftInterop {
    public static final IMPORT_META = ":swiftImport";
    public static final NATIVE_TYPE_META = ":swiftNativeType";
    public static final BRIDGE_META = ":swiftBridge";
    public static final NAME_META = ":swiftName";
    public static final LABELS_META = ":swiftLabels";

    /**
        The C release family is unavailable in Swift: Core Foundation and
        Core Graphics objects are automatically memory managed. A binding that
        declares one of these symbols is rejected at generation time.
    **/
    /** Swift constants a constant bridge can name, collected from the source scope. */
    static final declaredSwiftConstants:Map<String, Bool> = [];

    static final ARC_MANAGED_RELEASE:Map<String, Bool> = [
        "CFRelease" => true,
        "CFRetain" => true,
        "CGContextRelease" => true,
        "CGColorSpaceRelease" => true,
        "CGPathRelease" => true,
    ];

    public static function isArcManagedRelease(name:String):Bool {
        return ARC_MANAGED_RELEASE.exists(name);
    }

    /** Target support types: out parameters, C buffers, and opaque pointers. */
    public static final OUT_MODULE = "swift.Out";
    public static final BUFFER_MODULE = "swift.Buffer";
    public static final CONST_BUFFER_MODULE = "swift.ConstBuffer";
    public static final OPAQUE_MODULE = "swift.Opaque";
    public static final RAW_POINTER_MODULE = "swift.RawPointer";

    static function classOf(type:Null<Type>):Null<ClassType> {
        return switch (type == null ? null : Context.follow(withoutNull(type))) {
            case TInst(ref, _): ref.get();
            case _: null;
        };
    }

    /** Whether the parameter is the Swift target's out-parameter wrapper. */
    public static function isOutParam(type:Null<Type>):Bool {
        final cls = classOf(type);
        return cls != null && cls.module == OUT_MODULE;
    }

    /** Whether the parameter is a mutable C buffer. */
    public static function isMutableBuffer(type:Null<Type>):Bool {
        final cls = classOf(type);
        return cls != null && cls.module == BUFFER_MODULE;
    }

    /** Whether the parameter is a read-only C buffer. */
    public static function isConstBuffer(type:Null<Type>):Bool {
        final cls = classOf(type);
        return cls != null && cls.module == CONST_BUFFER_MODULE;
    }

    /** Whether the declaration is a support type with no Swift declaration. */
    public static function isSupportClass(cls:ClassType):Bool {
        return cls.module == BUFFER_MODULE || cls.module == CONST_BUFFER_MODULE || cls.module == OPAQUE_MODULE;
    }

    /** The Swift spelling an extern class declares for opaque C values. */
    public static function nativeTypeOfClass(cls:ClassType):Null<String> {
        final params = stringParams(cls.meta, NATIVE_TYPE_META, cls.pos);
        if (params.length == 0) {
            return null;
        }
        if (params.length != 1 || params[0].length == 0) {
            Context.error(NATIVE_TYPE_META + " takes exactly one non-empty Swift type spelling", cls.pos);
        }
        if (StringTools.contains(params[0], "$T") && cls.params.length == 0) {
            Context.error(NATIVE_TYPE_META + " uses $T but " + cls.name + " has no type parameter", cls.pos);
        }
        return params[0];
    }

    /** Replaces the element placeholder in a class native-type spelling. */
    public static function applyNativeType(template:String, params:Array<Type>, render:Type->String):String {
        if (!StringTools.contains(template, "$T")) {
            return template;
        }
        if (params.length == 0) {
            return template;
        }
        return StringTools.replace(template, "$T", render(params[0]));
    }

    /** A plain local or field is addressable; a call or literal is not. */
    public static function isStableLValue(expr:TypedExpr):Bool {
        return switch (expr.expr) {
            case TLocal(_): true;
            case TField(_, FInstance(_, _, _)): true;
            case TField(_, FStatic(_, _)): true;
            case _: false;
        };
    }

    /**
        The Swift spelling of an abstract that wraps a Haxe representation
        for a C boundary, or null when the abstract keeps its underlying
        rendering. Only a source declaration may mint one; the wrapper is a
        per-declaration annotation, never a global type override.
    **/
    public static function nativeTypeName(abs:AbstractType):Null<String> {
        final params = stringParams(abs.meta, NATIVE_TYPE_META, abs.pos);
        if (params.length == 0) {
            return null;
        }
        if (params.length != 1 || params[0].length == 0) {
            Context.error(NATIVE_TYPE_META + " takes exactly one non-empty Swift type spelling", abs.pos);
        }
        return params[0];
    }

    /**
        The conversion an extern parameter's native-type abstract declares for
        one Haxe value type, or null when the parameter is not a bridged
        boundary. The source type is the declared Haxe spelling ("String"), so
        the bridge applies only to values the declaration claims to convert.
    **/
    public static function bridgeOf(paramType:Null<Type>):Null<SwiftBridge> {
        if (paramType == null) {
            return null;
        }
        final abs = switch (Context.follow(withoutNull(paramType))) {
            case TAbstract(ref, _): ref.get();
            case _: return null;
        }
        final native = nativeTypeName(abs);
        if (native == null) {
            return null;
        }
        final params = stringParams(abs.meta, BRIDGE_META, abs.pos);
        if (params.length == 0) {
            return null;
        }
        if (params.length < 2 || params.length > 4) {
            Context.error(BRIDGE_META
                + " takes (sourceType, valueExpression[, scopeExpression, argumentExpression])", abs.pos);
        }
        final source = resolveSource(params[0], abs.pos);
        final scope = params.length >= 3 ? params[2] : null;
        final argument = params.length >= 4 ? params[3] : null;
        final valueTemplate = params[1];
        final hasValue = StringTools.contains(valueTemplate, "$0");
        final isIdentifier = ~/^[A-Za-z_][A-Za-z0-9_]*$/.match(valueTemplate);
        if (!hasValue && !isIdentifier) {
            Context.error("value template must reference $0 or be a declared Swift constant", abs.pos);
        }
        if (!hasValue && isIdentifier && !declaredSwiftConstants.exists(valueTemplate)) {
            Context.error("no declaration for Swift constant " + valueTemplate, abs.pos);
        }
        if (scope != null && (!StringTools.contains(scope, "$body") || !StringTools.contains(scope, "$1"))) {
            Context.error(BRIDGE_META + " scope expression must contain $1 (bound value) and $body (enclosing expression)", abs.pos);
        }
        if (scope != null && argument == null) {
            Context.error(BRIDGE_META + " scope expression needs the fourth argument expression that names $1", abs.pos);
        }
        return { native: native, source: source, value: params[1], scope: scope, argument: argument };
    }

    /** The converted value expression: the bridge's value template with `$0` replaced. */
    public static function applyValue(bridge:SwiftBridge, text:String):String {
        return StringTools.replace(bridge.value, "$0", text);
    }

    /** The argument expression inside the bridge's bracket. */
    public static function applyArgument(bridge:SwiftBridge, bound:String):String {
        return bridge.argument == null ? bound : StringTools.replace(bridge.argument, "$1", bound);
    }

    /** The enclosing expression wrapped in the bridge's lifetime bracket. */
    public static function wrapScope(scope:String, value:String, bound:String, body:String):String {
        final scoped = StringTools.replace(StringTools.replace(scope, "$0", value), "$1", bound);
        return StringTools.replace(scoped, "$body", body);
    }

    /** Module names one declaration asks the generated file to import. */
    public static function moduleImports(cls:ClassType):Array<String> {
        final params = stringParams(cls.meta, IMPORT_META, cls.pos);
        final out:Array<String> = [];
        for (name in params) {
            if (name.length == 0) {
                Context.error(IMPORT_META + " requires a non-empty module name", cls.pos);
            }
            if (!~/^[A-Za-z_][A-Za-z0-9_]*$/.match(name)) {
                Context.error(IMPORT_META + " module name must be a Swift module identifier: " + name, cls.pos);
            }
            if (out.indexOf(name) < 0) {
                out.push(name);
            }
        }
        return out;
    }

    /**
        The Swift argument labels a marked extern static declares, in
        declaration order, from a `|`-separated spelling. An empty entry
        keeps the argument unlabeled.
    **/
    public static function labelNames(field:ClassField):Array<String> {
        final params = stringParams(field.meta, LABELS_META, field.pos);
        if (params.length == 0) {
            return [];
        }
        if (params.length != 1) {
            Context.error(LABELS_META + " takes exactly one label list", field.pos);
        }
        return params[0].length == 0 ? [] : params[0].split("|");
    }

    /** The Swift spelling a marked extern static declares, or null when it keeps its Haxe name. */
    public static function externalName(field:ClassField):Null<String> {
        final params = stringParams(field.meta, NAME_META, field.pos);
        if (params.length == 0) {
            return null;
        }
        if (params.length != 1 || params[0].length == 0) {
            Context.error(NAME_META + " takes exactly one non-empty Swift spelling", field.pos);
        }
        return params[0];
    }

    /**
        Declaration-side rules. Unknown metadata that is silently ignored is a
        lie in the source, so each shape is validated where it is cheapest to
        explain: the native type and bridge belong to an abstract, the import
        belongs to a file-producing declaration, and the spelling override
        belongs to a marked top-level static.
    **/
    public static function validate(mtypes:Array<ModuleType>):Void {
        // Constants first: a bridge may name one, and the bridge is validated
        // while the declarations are scanned.
        declaredSwiftConstants.clear();
        for (mt in mtypes) {
            switch (mt) {
                case TClassDecl(ref):
                    final cls = ref.get();
                    if (!PolicyQueries.inSourceScope(cls.pos)) {
                        continue;
                    }
                    for (field in cls.fields.get().concat(cls.statics.get())) {
                        final spelled = externalName(field);
                        if (spelled != null) {
                            declaredSwiftConstants.set(spelled, true);
                        }
                        if (cls.isExtern && StaticFunctionMarkers.isMarked(field)) {
                            declaredSwiftConstants.set(field.name, true);
                        }
                    }
                case _:
            }
        }
        for (mt in mtypes) {
            switch (mt) {
                case TClassDecl(ref):
                    final cls = ref.get();
                    if (!PolicyQueries.inSourceScope(cls.pos)) {
                        continue;
                    }
                    if (cls.meta.has(IMPORT_META)) {
                        if (cls.isExtern) {
                            Context.error(IMPORT_META + " belongs on the declaration whose generated file needs the import, not on " + cls.name, cls.pos);
                        }
                        moduleImports(cls);
                    }
                    if (cls.meta.has(BRIDGE_META)) {
                        Context.error(BRIDGE_META + " declares a representation conversion and belongs on an abstract that wraps a C boundary", cls.pos);
                    }
                    nativeTypeOfClass(cls);
                    if (cls.isExtern) {
                        for (field in cls.fields.get().concat(cls.statics.get())) {
                            if (!StaticFunctionMarkers.isMarked(field)) {
                                continue;
                            }
                            final emittedMarked = externalName(field);
                            final emittedMarkedName = emittedMarked == null ? field.name : emittedMarked;
                            if (isArcManagedRelease(emittedMarkedName)) {
                                Context.error(emittedMarkedName
                                    + " is ARC-managed in Swift; remove the retain/release call and hold the class reference", field.pos);
                            }
                        }
                    }
                    for (field in cls.fields.get()) {
                        if (!field.meta.has(NAME_META)) {
                            continue;
                        }
                        if (!cls.isExtern || !StaticFunctionMarkers.isMarked(field)) {
                            Context.error(NAME_META + " belongs on a @:topLevel or @:extension extern static", field.pos);
                        }
                        final emitted = externalName(field);
                        final emittedName = emitted == null ? field.name : emitted;
                        if (isArcManagedRelease(emittedName)) {
                            Context.error(emittedName
                                + " is ARC-managed in Swift; remove the retain/release call and hold the class reference", field.pos);
                        }
                        if (field.meta.has(LABELS_META)) {
                            final labels = labelNames(field);
                            final arity = switch (Context.follow(field.type)) {
                                case TFun(args, _): args.length;
                                case _: -1;
                            };
                            if (arity < 0 || labels.length != arity) {
                                Context.error(LABELS_META + " must name one label per extern argument", field.pos);
                            }
                        }
                    }
                case TAbstract(ref):
                    final abs = ref.get();
                    if (!PolicyQueries.inSourceScope(abs.pos)) {
                        continue;
                    }
                    if (abs.meta.has(IMPORT_META)) {
                        Context.error(IMPORT_META + " belongs on a class in the module whose generated file needs the import, not on abstract " + abs.name, abs.pos);
                    }
                    nativeTypeName(abs);
                    bridgeOf(TAbstract(ref, []));
                case _:
            }
        }
    }

    static function resolveSource(path:String, pos:haxe.macro.Expr.Position):Type {
        try {
            return Context.getType(path);
        } catch (_:Dynamic) {
            Context.error(BRIDGE_META + " source type is not a known Haxe type: " + path, pos);
            return null;
        }
    }

    /** Drops the optional wrapper; a null value at an extern boundary keeps its own spelling. */
    static function withoutNull(type:Type):Type {
        return switch (Context.follow(type)) {
            case TAbstract(ref, params) if (ref.get().name == "Null" && params.length == 1): withoutNull(params[0]);
            case TLazy(next): withoutNull(next());
            case other: other;
        };
    }

    static function stringParams(meta:MetaAccess, name:String, pos:haxe.macro.Expr.Position):Array<String> {
        final out:Array<String> = [];
        for (entry in meta.extract(name)) {
            for (param in entry.params) {
                switch (param.expr) {
                    case EConst(CString(value)): out.push(value);
                    case _: Context.error(name + " accepts string literals only", param.pos);
                }
            }
        }
        return out;
    }
}

typedef SwiftBridge = {
    /** The Swift type the bridged abstract renders as. */
    var native:String;
    /** The Haxe type the bridge converts from. */
    var source:Type;
    /** The value expression template ($0 is the converted argument). */
    var value:String;
    /** The lifetime bracket, or null for a plain value conversion. */
    var scope:Null<String>;
    /** The argument expression inside the bracket ($1 is the bound name). */
    var argument:Null<String>;
}
#end
