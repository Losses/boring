#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.macro.Type.TypedExpr;
import haxe.macro.Type.TypedExprDef;

enum EnumQueryKind {
	QCollection;
	QName;
	QLookup;
}

/** Common typed expansion and on-demand artifact registry for feature 28. */
class EnumQueryExpander {
	static final uses:Map<String, {collection:Bool, name:Bool, lookup:Bool, en:EnumType}> = [];
	static final aliases:Map<Int, EnumType> = [];
	static inline final MARKER = ":enumValueQuery";

	public static function expandRootExpr(root:TypedExpr):Void {
		if(root == null) return;
		collectAliases(root);
		walk(root, "other");
	}

	public static function usage(en:EnumType):Null<{collection:Bool, name:Bool, lookup:Bool, en:EnumType}> {
		return uses.get(en.module);
	}

	public static function markerKind(e:TypedExpr):Null<EnumQueryKind> {
		return switch(e.expr) {
			case TMeta(meta, _) if(meta.name == MARKER && meta.params.length == 1):
				switch(meta.params[0].expr) {
					case EConst(CString("collection")): QCollection;
					case EConst(CString("name")): QName;
					case EConst(CString("lookup")): QLookup;
					case _: null;
				}
			case _: null;
		};
	}

	public static function markerInner(e:TypedExpr):TypedExpr return switch(e.expr) {
		case TMeta(_, inner): inner;
		case _: e;
	};

	public static function enumOf(e:TypedExpr):Null<EnumType> {
		final inner = markerInner(e);
		return switch(inner.expr) {
			case TCall(_, args):
				final kind = markerKind(e);
				if(kind == QName) enumFromType(args[0].t) else enumTypeRef(args[0]);
			case TLocal(v): aliases.get(v.id);
			case _: null;
		};
	}

	public static function aliasEnum(e:TypedExpr):Null<EnumType> return switch(e.expr) {
		case TLocal(v): aliases.get(v.id);
		case TMeta(_, inner): aliasEnum(inner);
		case _: null;
	};
	public static function aliasById(id:Int):Null<EnumType> return aliases.get(id);

	public static function collectionEnum(e:TypedExpr):Null<EnumType> {
		if(markerKind(e) == QCollection) return enumOf(e);
		return aliasEnum(e);
	}

	public static function callArgs(e:TypedExpr):Array<TypedExpr> return switch(markerInner(e).expr) {
		case TCall(_, args): args;
		case _: [];
	};

	public static function constructorCount(en:EnumType):Int {
		var count = 0;
		for(_ in en.constructs) count++;
		return count;
	}

	public static function upperSnake(name:String):String {
		final out = new StringBuf();
		for(i in 0...name.length) {
			final c = name.charAt(i);
			if(i > 0 && c >= "A" && c <= "Z") out.add("_");
			out.add(c.toUpperCase());
		}
		return out.toString();
	}

	public static function lowerFirst(name:String):String return name.charAt(0).toLowerCase() + name.substr(1);

	static function collectAliases(e:TypedExpr):Void {
		switch(e.expr) {
			case TVar(v, init) if(init != null):
				final en = allEnumsType(init);
				if(en != null) aliases.set(v.id, en);
			default:
		}
		haxe.macro.TypedExprTools.iter(e, collectAliases);
	}

	static function walk(e:TypedExpr, position:String):Void {
		if(e == null) return;
		if(markerKind(e) != null) return;
		switch(e.expr) {
			case TLocal(v) if(aliases.exists(v.id) && position == "other"):
				Context.fatalError("Type.allEnums expands in length and index positions only", e.pos);
			case _:
		}
		final all = allEnumsType(e);
		if(all != null) {
			ensureValueEnum(all, e.pos);
			if(position != "length" && position != "index" && position != "alias") Context.fatalError("Type.allEnums expands in length and index positions only", e.pos);
			register(all, QCollection);
			mark(e, "collection");
			return;
		}
		switch(e.expr) {
			case TVar(_, init): if(init != null) walk(init, allEnumsType(init) != null ? "alias" : "other");
			case TField(subj, fa):
				final name = switch(fa) { case FInstance(_, _, cf) | FAnon(cf): cf.get().name; case FDynamic(n): n; case _: ""; };
				if(name == "length" && (allEnumsType(subj) != null || aliasEnum(subj) != null)) walk(subj, "length"); else walk(subj, "other");
			case TArray(subj, index):
				if(allEnumsType(subj) != null || aliasEnum(subj) != null) walk(subj, "index"); else walk(subj, "other");
				walk(index, "other");
			case TCall(callee, args):
				final member = typeMember(callee);
				switch(member) {
					case "enumConstructor":
						if(args.length != 1) Context.fatalError("Type.enumConstructor accepts parameterless enum values only", e.pos);
						final en = enumFromType(args[0].t);
						if(en == null) Context.fatalError("Type.enumConstructor accepts parameterless enum values only", args[0].pos);
						ensureValueEnum(en, args[0].pos); register(en, QName); mark(e, "name");
					case "createEnum":
						if(args.length != 2 && !(args.length == 3 && switch(args[2].expr) { case TConst(TNull): true; case _: false; })) Context.fatalError("Type.createEnum accepts the two-argument form only", e.pos);
						final en = enumTypeRef(args[0]);
						if(en == null) Context.fatalError("Type.createEnum accepts the two-argument form only", args[0].pos);
						ensureValueEnum(en, args[0].pos); walk(args[1], "other"); register(en, QLookup); mark(e, "lookup");
					case "allEnums": Context.fatalError("Type.allEnums accepts an enum type reference only", e.pos);
					case _: haxe.macro.TypedExprTools.iter(e, child -> walk(child, "other"));
				}
			default: haxe.macro.TypedExprTools.iter(e, child -> walk(child, "other"));
		}
	}

	static function mark(e:TypedExpr, kind:String):Void {
		final inner = {expr:e.expr, pos:e.pos, t:e.t};
		e.expr = TMeta({name:MARKER, params:[macro $v{kind}], pos:e.pos}, inner);
	}

	static function register(en:EnumType, kind:EnumQueryKind):Void {
		var use = uses.get(en.module);
		if(use == null) { use = {collection:false, name:false, lookup:false, en:en}; uses.set(en.module, use); }
		switch(kind) { case QCollection: use.collection = true; case QName: use.name = true; case QLookup: use.lookup = true; }
	}

	static function typeMember(e:TypedExpr):Null<String> return switch(e.expr) {
		case TField(_, FStatic(cls, field)) if(cls.get().name == "Type"): field.get().name;
		case _: null;
	};

	static function allEnumsType(e:TypedExpr):Null<EnumType> return switch(e.expr) {
		case TParenthesis(inner) | TCast(inner, _) | TMeta(_, inner): allEnumsType(inner);
		case TCall(callee, args) if(typeMember(callee) == "allEnums"):
			if(args.length != 1) Context.fatalError("Type.allEnums accepts an enum type reference only", e.pos);
			final en = enumTypeRef(args[0]);
			if(en == null) Context.fatalError("Type.allEnums accepts an enum type reference only", args[0].pos);
			en;
		case _: null;
	};

	static function enumTypeRef(e:TypedExpr):Null<EnumType> return switch(e.expr) {
		case TTypeExpr(TEnumDecl(en)): en.get();
		case TParenthesis(inner) | TCast(inner, _) | TMeta(_, inner): enumTypeRef(inner);
		case _: null;
	};

	static function enumFromType(t:Type):Null<EnumType> return switch(Context.follow(t)) {
		case TEnum(en, _): en.get();
		case _: null;
	};

	static function ensureValueEnum(en:EnumType, pos:haxe.macro.Expr.Position):Void {
		for(ef in en.constructs) switch(Context.follow(ef.type)) {
			case TFun(args, _) if(args.length > 0): Context.fatalError("enum queries accept enums without constructor parameters only", pos);
			case _:
		}
	}
}
#end
