package swiftcompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Type;

/**
	Registry of the composite types Test.equals reaches
	(docs/specs/features/19-test-entry.md). Scalar arguments route to
	TestCore directly; every other argument type registers here, and the
	output stage generates the canonical formatter and the assertion
	function for it. Equality itself needs no generated function: the
	lane's structs, enums, arrays, and optionals all conform to
	Equatable, so the assertion compares with the native operator.
**/
class SwiftTestTypes {
	/** Tag to the Haxe type it names, in first-encounter order. */
	public static final registered: Array<{tag: String, type: Type}> = [];

	static final known: Map<String, Bool> = [];

	/**
		The generated-name tag of a test value type. Tags spell out the
		Swift shape (Int32, OptInt32, Int32Array) so the generated
		function names read without decoding. Typedefs and the special
		abstracts keep their identity: `Context.follow` would unwrap a
		named record to its anonymous structure and lose the name, so
		only lazy wrappers resolve here.
	**/
	public static function tagOf(t: Type): String {
		return switch(t) {
			case TAbstract(a, params):
				switch(a.get().name) {
					case "Int": "Int32";
					case "Float": "Double";
					case "Bool": "Bool";
					case "Null": "Opt" + tagOf(params[0]);
					// The read-only view formats exactly as the array it
					// wraps (features/18).
					case "ReadOnlyArray": tagOf(params[0]) + "Array";
					case _: fail(t);
				}
			case TInst(c, params):
				switch(c.get().name) {
					case "String": "String";
					case "Bytes": "Bytes";
					case "Array": tagOf(params[0]) + "Array";
					case _: fail(t);
				}
			case TType(d, _): d.get().name;
			case TAnonymous(anon):
				// The typer keeps an object literal's own type anonymous;
				// the nominal record comes from the shape registry.
				final def = SwiftDecl.structTypedefs.get(SwiftDecl.structureSignature(anon));
				if(def == null) {
					Context.error("test assertion record literal must match a named structure typedef", Context.currentPos());
				}
				def.get().name;
			case TEnum(e, _): e.get().name;
			case TLazy(f): tagOf(f());
			case _: fail(t);
		}
	}

	/**
		Whether a Test.equals argument routes to a TestCore scalar
		assertion without registration.
	**/
	public static function isScalarRoute(t: Type): Bool {
		return switch(t) {
			case TAbstract(a, _):
				final name = a.get().name;
				name == "Int" || name == "Float" || name == "Bool";
			case TInst(c, _):
				c.get().name == "String";
			case TLazy(f): isScalarRoute(f());
			case _: false;
		}
	}

	/**
		Registers a type and every type nested inside it, marking before
		recursing so a recursive structure terminates.
	**/
	public static function register(t: Type): String {
		registerInto(t);
		return tagOf(t);
	}

	static function registerInto(t: Type): Void {
		final tag = tagOf(t);
		if(known.exists(tag)) {
			return;
		}
		known.set(tag, true);
		registered.push({tag: tag, type: t});
		// No `Context.follow` here: it would unwrap Null<T> and the
		// named records this walk must descend into.
		switch(t) {
			case TAbstract(a, params) if(a.get().name == "Null"):
				registerInto(params[0]);
			case TAbstract(a, params) if(a.get().name == "ReadOnlyArray"):
				registerInto(params[0]);
			case TInst(c, params) if(c.get().name == "Array"):
				registerInto(params[0]);
			case TType(d, _):
				registerStructFields(d.get());
			case TAnonymous(an):
				// Follow unwraps a named record to this shape; resolve the
				// name back through the registry so both spellings walk
				// the same declaration's fields.
				final def = SwiftDecl.structTypedefs.get(SwiftDecl.structureSignature(an));
				if(def != null) {
					registerStructFields(def.get());
				}
			case TEnum(e, _):
				for(name => construct in e.get().constructs) {
					switch(construct.type) {
						case TFun(args, _):
							for(arg in args) {
								registerInto(arg.t);
							}
						case _: registerInto(construct.type);
					}
				}
			case TLazy(f):
				registerInto(f());
			case _:
		}
	}

	static function registerStructFields(d: DefType): Void {
		switch(d.type) {
			case TAnonymous(an):
				for(f in an.get().fields) {
					registerInto(f.type);
				}
			case _:
		}
	}

	static function fail(t: Type): String {
		Context.error("test assertion type has no Swift lowering in the subset: " + Std.string(t), Context.currentPos());
		return "";
	}
}
#end
