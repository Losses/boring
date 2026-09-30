package dcpe;

#if macro

import haxe.macro.Context;
import haxe.macro.Type;
import haxe.macro.Type.ClassField;
import haxe.macro.Type.ClassType;
import haxe.macro.Type.FieldAccess;
import haxe.macro.Type.ModuleType;
import haxe.macro.Type.Ref;
import haxe.macro.Type.TypedExpr;
import haxe.macro.Type.TypedExprDef;

/**
    Typer probe for the dc-promoted-eval fixture.

    Runs as `--macro dcpe.SubjectProbe.run()` after `--macro Intercept.run(...)`,
    so it observes the typed AST exactly as the target emitters receive it for
    the parsed fixture classes. For every method of every `dcpe.` class it

      * counts the calls to that class's own side-effecting `nextKind()`
        (`METHOD-PROBE ... calls=N`), and
      * prints every statement-position switch together with the statement that
        precedes it inside the same block, the subject shape, and the number of
        `nextKind()` calls inside the promoted local's initializer
        (`BLOCK-PROBE ... initCalls=N`).

    `calls=1` with `initCalls=1` is the structural form of the runtime claim the
    runner measures: the subject call appears once in the typed AST and lands in
    the synthetic local's initializer, not in the switch subject.
**/
class SubjectProbe {
	public static function run():Void {
		Context.onAfterTyping(function (modules) {
			for (module in modules) {
				switch (module) {
					case ModuleType.TClassDecl(classRef):
						final owner = classRef.toString();
						if (owner.indexOf("dcpe.") != 0)
							continue;
						if (owner.indexOf("SubjectProbe") >= 0 || owner.indexOf("ProbeEntry") >= 0)
							continue;
						final classType = classRef.get();
						dumpFields(classType.statics.get(), owner, "static");
						dumpFields(classType.fields.get(), owner, "instance");
					default:
						// enum declarations carry no method bodies
				}
			}
		});
	}

	static function dumpFields(fields:Array<ClassField>, owner:String, scope:String):Void {
		for (field in fields) {
			if (field.expr == null)
				continue;
			final body = field.expr();
			if (body == null)
				continue;
			final name = owner + "." + field.name;
			trace("METHOD-PROBE owner=" + name + " scope=" + scope + " calls=" + countSubjectCalls(body));
			dump(body, name, "root");
		}
	}

	static function dump(e:TypedExpr, owner:String, parentKind:String):Void {
		if (e == null)
			return;
		switch (e.expr) {
			case TBlock(stmts):
				for (i in 0...stmts.length) {
					final isSwitchStmt = stmts[i] != null && switch (stmts[i].expr) {
						case TSwitch(_, _, _):
							true;
						default:
							false;
					}
					if (isSwitchStmt) {
						final prev = i > 0 ? varStmtShape(stmts[i - 1]) : "(first-statement)";
						final initCalls = i > 0 ? countSubjectCalls(stmts[i - 1]) : 0;
						final switchExpr = stmts[i];
						final detail = switch (switchExpr.expr) {
							case TSwitch(subj, cases, def):
								"initCalls=" + initCalls
								+ " subject=" + shapeOf(subj)
								+ " subjectType=" + typeString(subj.t)
								+ " cases=" + cases.length
								+ " default=" + (def == null ? "none" : "present");
							default:
								"initCalls=" + initCalls;
						}
						trace("BLOCK-PROBE owner=" + owner + " " + posOf(e)
							+ " switchIndex=" + i + " blockLen=" + stmts.length
							+ " prevStmt=" + prev + " " + detail);
					}
				}
				recurse(e, owner, "TBlock");
			case TSwitch(_, _, _):
				trace("SWITCH-PROBE owner=" + owner + " " + posOf(e) + " parent=" + parentKind
					+ " subject=" + shapeOf(switch (e.expr) { case TSwitch(s, _, _): s; default: e; }));
				recurse(e, owner, "TSwitch");
			default:
				recurse(e, owner, kindName(e.expr));
		}
	}

	static function recurse(e:TypedExpr, owner:String, parentKind:String):Void {
		if (e == null)
			return;
		haxe.macro.TypedExprTools.iter(e, child -> dump(child, owner, parentKind));
	}

	/** Number of calls to a static `nextKind` reachable from `e`. **/
	static function countSubjectCalls(e:TypedExpr):Int {
		if (e == null)
			return 0;
		var n = switch (e.expr) {
			case TCall(fn, _):
				isSubjectCallee(fn) ? 1 : 0;
			default:
				0;
		}
		haxe.macro.TypedExprTools.iter(e, child -> n += countSubjectCalls(child));
		return n;
	}

	static function isSubjectCallee(fn:TypedExpr):Bool {
		if (fn == null)
			return false;
		return switch (fn.expr) {
			case TField(_, FStatic(_, cf)):
				cf.get().name == "nextKind";
			default:
				false;
		}
	}

	static function posOf(e:TypedExpr):String {
		final infos = Context.getPosInfos(e.pos);
		final line = Std.int(infos.min / 65536) + 1;
		return "src=" + infos.file + ":" + line + "(min=" + infos.min + ")";
	}

	static function varStmtShape(stmt:TypedExpr):String {
		switch (stmt.expr) {
			case TVar(v, init):
				return "TVar(" + v.name + " type=" + typeString(v.t) + ", init="
					+ (init == null ? "none" : shapeOf(init)) + ")";
			default:
				return shapeOf(stmt);
		}
	}

	static function shapeOf(e:TypedExpr):String {
		if (e == null)
			return "null";
		switch (e.expr) {
			case TEnumIndex(inner):
				return "TEnumIndex(" + shapeOf(inner) + ")";
			case TLocal(v):
				return "TLocal(" + v.name + ")";
			case TField(base, fa):
				return "TField(" + fieldAccessOf(fa) + " on " + shapeOf(base) + ")";
			case TCall(fn, args):
				return "TCall(" + shapeOf(fn) + ", " + args.length + " args)";
			case TConst(c):
				return "TConst(" + Std.string(c) + ")";
			case TParenthesis(inner):
				return "TParenthesis(" + shapeOf(inner) + ")";
			case TMeta(m, inner):
				return "TMeta(" + m.name + ")(" + shapeOf(inner) + ")";
			case TCast(inner, _):
				return "TCast(" + shapeOf(inner) + ")";
			case TBlock(stmts):
				return "TBlock(" + stmts.length + " stmts)";
			case TVar(v, _):
				return "TVar(" + v.name + ")";
			case TReturn(v):
				return "TReturn(" + (v == null ? "void" : shapeOf(v)) + ")";
			default:
				return Std.string(e.expr);
		}
	}

	static function fieldAccessOf(fa:FieldAccess):String {
		switch (fa) {
			case FInstance(c, _, cf):
				return "FInstance(" + c.toString() + "." + cf.toString() + ")";
			case FStatic(c, cf):
				return "FStatic(" + c.toString() + "." + cf.toString() + ")";
			case FAnon(cf):
				return "FAnon(" + cf.toString() + ")";
			case FDynamic(s):
				return "FDynamic(" + s + ")";
			case FClosure(c, cf):
				return "FClosure(" + (c == null ? "null" : c.c.toString()) + "." + cf.toString() + ")";
			case FEnum(en, ef):
				return "FEnum(" + en.toString() + "." + ef.name + ")";
		}
	}

	static function kindName(d:TypedExprDef):String {
		switch (d) {
			case TLocal(_): return "TLocal";
			case TField(_, _): return "TField";
			case TCall(_, _): return "TCall";
			case TEnumIndex(_): return "TEnumIndex";
			case TBlock(_): return "TBlock";
			case TSwitch(_, _, _): return "TSwitch";
			case TReturn(_): return "TReturn";
			case TVar(_, _): return "TVar";
			case TParenthesis(_): return "TParenthesis";
			case TMeta(_, _): return "TMeta";
			default: return Std.string(d);
		}
	}

	static function typeString(t:Null<Type>):String {
		if (t == null)
			return "null-type";
		switch (t) {
			case TEnum(c, params):
				return "TEnum(" + c.toString() + ", " + params.length + " params)";
			case TInst(c, params):
				return "TInst(" + c.toString() + ", " + params.length + " params)";
			case TAbstract(a, params):
				return "TAbstract(" + a.toString() + ", " + params.length + " params)";
			default:
				return Std.string(t);
		}
	}
}

#else

/** Stub for target compilations: nothing references the probe outside probe.hxml. **/
class SubjectProbe {
}

#end
