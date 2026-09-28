package;

#if macro
import haxe.macro.Context;
import haxe.macro.Type;
import ComparatorPlan.ComparatorFieldKind;
import PolicyQueries;
import StaticFieldHelper;
import swiftcompiler.SwiftArrayBoundary;
import swiftcompiler.SwiftType;
#end

/**
	Compile-time observation of source container classification. The probe
	obtains real typed forms from the declarations in the classifier package
	through the macro Context during the typecheck phase, calls the shared
	helpers and the invocable target helpers at their real entry points, and
	prints one record per case. It changes no compiler decision and renders
	no target text; it is an observation harness only.

	The stage it observes is source typing (the typer's forms, read before
	ordinary emission). It does not run Boring generation, a target compiler,
	or a target runtime, and a result here establishes only that stage. The
	expected case identities are enumerated independently of the traversal
	and checked against the visited labels so a missing or duplicated case is
	detectable.

	Run: nix develop -c bash tests/haxe/classifier/run.sh
**/
class ClassifierProbe {
	public static function main():Void {}

#if macro
	static final lines:Array<String> = [];
	static var caseIndex:Int = 0;
	static var visited:Map<String, Int> = [];
	static var labelCheckFailed:Bool = false;

	public static function run():Void {
		record("classifier probe");
		sourceFieldCases();
		expressionCases();
		syntheticCases();
		lazyCases();
		comparatorCases();
		recordLabelCheck();
		record("");
		record("END " + caseIndex + " cases");
		for (line in lines)
			Sys.println(line);
		Sys.exit(labelCheckFailed ? 1 : 0);
	}

	static function record(line:String):Void {
		lines.push(line);
	}

	// ------------------------------------------------------------------
	// Independent case-identity expectation, checked against the traversal
	// ------------------------------------------------------------------

	/** The case labels the probe declares it will visit, from the fixture source. */
	static final EXPECTED_CASE_LABELS:Array<String> = [
		"static field plainArray",
		"static field readOnly",
		"static field nullableReadOnly",
		"static field nullablePlain",
		"static field elementNullable",
		"static field aliasReadOnly",
		"static field userNamed",
		"static field aliasNamed",
		"static field nullableUserNamed",
		"static field emptyReadOnly",
		"instance field instPlainArray",
		"instance field instReadOnly",
		"instance field instNullableReadOnly",
		"instance field instElementNullable",
		"instance field instAliasReadOnly",
		"instance field instUserNamed",
		"instance field instAliasNamed",
		"instance field instNullableUserNamed",
		"expression alias annotated",
		"expression array annotated",
		"synthetic null over read-only",
		"synthetic read-only over null element",
		"constructor type of classifier.Recursive",
		"constructor of classifier.Fixtures",
		"macro constructed lazy",
	];

	/** The instance field names the comparator matrix classifies. */
	static final INSTANCE_FIELD_NAMES:Array<String> = [
		"instPlainArray",
		"instReadOnly",
		"instNullableReadOnly",
		"instElementNullable",
		"instAliasReadOnly",
		"instUserNamed",
		"instAliasNamed",
		"instNullableUserNamed",
	];

	static function expectedComparatorLabels():Array<String> {
		final out:Array<String> = [];
		for (outer in [false, true]) {
			for (inner in [false, true]) {
				for (name in INSTANCE_FIELD_NAMES)
					out.push("comparator outer=" + outer + " inner=" + inner + " " + name);
			}
		}
		return out;
	}

	/** Records one visited case identity for the coverage check. */
	static function note(label:String):Void {
		final current = visited.exists(label) ? visited.get(label) : 0;
		visited.set(label, current + 1);
	}

	static function recordLabelCheck():Void {
		final expectedAll:Array<String> = EXPECTED_CASE_LABELS.concat(expectedComparatorLabels());
		final expected:Map<String, Bool> = [];
		for (label in expectedAll)
			expected.set(label, true);
		final missing:Array<String> = [];
		final extra:Array<String> = [];
		final duplicates:Array<String> = [];
		for (label in expected.keys())
			if (!visited.exists(label))
				missing.push(label);
		for (label in visited.keys()) {
			if (!expected.exists(label))
				extra.push(label);
			else if (visited.get(label) > 1)
				duplicates.push(label);
		}
		missing.sort(Reflect.compare);
		extra.sort(Reflect.compare);
		duplicates.sort(Reflect.compare);
		var visitedCount = 0;
		for (label in visited.keys())
			visitedCount++;
		record("");
		record("SECTION label check: expected case identities vs visited labels");
		record("  expected = " + expectedAll.length);
		record("  visited  = " + visitedCount);
		if (missing.length == 0 && extra.length == 0 && duplicates.length == 0) {
			record("  label check ok: every expected label visited exactly once, no extras");
			return;
		}
		labelCheckFailed = true;
		for (label in missing)
			record("  MISSING: " + label);
		for (label in extra)
			record("  EXTRA: " + label);
		for (label in duplicates)
			record("  DUPLICATE (" + visited.get(label) + "x): " + label);
	}

	// ------------------------------------------------------------------
	// Source typing: declared fields of the classifier package
	// ------------------------------------------------------------------

	static function sourceFieldCases():Void {
		final cls = classOf("classifier.Fixtures");
		record("");
		record("SECTION source typing: declared static fields of classifier.Fixtures");
		final statics = [for (f in cls.statics.get()) f];
		statics.sort((a, b) -> Reflect.compare(a.name, b.name));
		for (f in statics)
			observe("static field " + f.name, "source typing", f.type);
		record("");
		record("SECTION source typing: declared instance fields of classifier.Fixtures");
		final instanceFields = [for (f in cls.fields.get()) f];
		instanceFields.sort((a, b) -> Reflect.compare(a.name, b.name));
		for (f in instanceFields)
			observe("instance field " + f.name, "source typing", f.type);
	}

	static function expressionCases():Void {
		record("");
		record("SECTION source typing: typed expressions");
		final aliasLiteral = Context.typeExpr(macro ([1, 2] : classifier.RO<Int>));
		observe("expression alias annotated", "source typing", aliasLiteral.t);
		final plainLiteral = Context.typeExpr(macro ([1, 2] : Array<Int>));
		observe("expression array annotated", "source typing", plainLiteral.t);
	}

	// ------------------------------------------------------------------
	// Synthetic macro forms, labelled apart from source typing
	// ------------------------------------------------------------------

	static function syntheticCases():Void {
		record("");
		record("SECTION synthetic macro inputs");
		observe("synthetic null over read-only", "synthetic macro input", nullOf(readOnlyType()));
		observe("synthetic read-only over null element", "synthetic macro input",
			readOnlyOf(nullOf(Context.getType("Int"))));
	}

	// ------------------------------------------------------------------
	// Lazy forms: one retained by typing, one built in the macro
	// ------------------------------------------------------------------

	static function lazyCases():Void {
		record("");
		record("SECTION lazy forms");
		final retained = retainedLazyTypes();
		if (retained.length == 0)
			record("  typing retained no lazy form in the scanned declarations");
		for (item in retained)
			observe(item.label, "source typing (retained lazy)", item.form);
		final constructed = TLazy(() -> readOnlyType());
		observe("macro constructed lazy", "synthetic macro input", constructed);
	}

	static function retainedLazyTypes():Array<{label:String, form:Type}> {
		final found:Array<{label:String, form:Type}> = [];
		final recursive = classOf("classifier.Recursive");
		if (recursive.constructor != null && hasLazy(recursive.constructor.get().type))
			found.push({label: "constructor type of classifier.Recursive", form: recursive.constructor.get().type});
		for (moduleName in ["classifier.Fixtures", "classifier.RO", "std.ReadOnlyArray", "altpack.ReadOnlyArray",
			"altpackalias.ReadOnlyArray"]) {
			for (moduleType in Context.getModule(moduleName))
				collectLazy(moduleType, moduleName, found);
		}
		return found;
	}

	static function collectLazy(moduleType:Type, moduleName:String, found:Array<{label:String, form:Type}>):Void {
		switch (moduleType) {
			case TInst(c, _):
				for (field in c.get().fields.get())
					if (hasLazy(field.type))
						found.push({label: "field " + moduleName + "." + field.name, form: field.type});
				if (c.get().constructor != null && hasLazy(c.get().constructor.get().type))
					found.push({label: "constructor of " + moduleName, form: c.get().constructor.get().type});
			case TEnum(en, _):
				for (construct in en.get().constructs)
					if (hasLazy(construct.type))
						found.push({label: "construct " + moduleName + "." + construct.name, form: construct.type});
			case TAbstract(ab, _):
				if (hasLazy(ab.get().type))
					found.push({label: "underlying type of " + moduleName, form: ab.get().type});
			case TType(d, _):
				if (hasLazy(d.get().type))
					found.push({label: "underlying type of " + moduleName, form: d.get().type});
			case _:
		}
	}

	static function hasLazy(t:Type):Bool {
		var found = false;
		function walk(x:Type):Void {
			switch (x) {
				case TLazy(_): found = true;
				case _:
			}
			switch (x) {
				case TInst(_, params) | TAbstract(_, params) | TType(_, params) | TEnum(_, params):
					for (p in params)
						walk(p);
				case TFun(args, ret):
					for (a in args)
						walk(a.t);
					walk(ret);
				case TLazy(f):
					walk(f());
				case _:
			}
		}
		walk(t);
		return found;
	}

	// ------------------------------------------------------------------
	// Real shared caller of the comparator classification
	// ------------------------------------------------------------------

	static function comparatorCases():Void {
		record("");
		record("SECTION ComparatorPlan.entries over classifier.Fixtures (real shared caller)");
		final cls = classOf("classifier.Fixtures");
		for (outer in [false, true]) {
			for (inner in [false, true]) {
				record("  outerStrict=" + outer + " innerStrict=" + inner);
				for (entry in ComparatorPlan.entries(cls, outer, inner)) {
					note("comparator outer=" + outer + " inner=" + inner + " " + entry.field.name);
					record("    " + entry.field.name + " = " + kindName(entry.kind));
				}
			}
		}
	}

	static function kindName(kind:ComparatorFieldKind):String {
		return switch (kind) {
			case NullableScalar(inner): "NullableScalar(" + Std.string(inner) + ")";
			case NullableArray(element): "NullableArray(" + Std.string(element) + ")";
			case ReadOnlyArrayField(element): "ReadOnlyArrayField(" + Std.string(element) + ")";
			case PlainField: "PlainField";
		};
	}

	// ------------------------------------------------------------------
	// One case record
	// ------------------------------------------------------------------

	static function observe(label:String, origin:String, t:Type):Void {
		caseIndex++;
		note(label);
		record("");
		record("CASE " + caseIndex + " " + label);
		record("  origin                         = " + origin);
		record("  raw form                       = " + Std.string(t));
		record("  raw identity                   = " + identity(t));
		record("  follow                         = " + followRecord(t));
		record("  outer nullable (raw)           = " + attempt(() -> Std.string(outerNullable(t))));
		record("  shared arrayElementType        = " + attempt(() -> Std.string(StaticFieldHelper.arrayElementType(t))));
		record("  element nullable               = " + attempt(() -> elementNullable(StaticFieldHelper.arrayElementType(t))));
		record("  StaticFieldHelper.isReadOnlyArrayType = "
			+ attempt(() -> Std.string(StaticFieldHelper.isReadOnlyArrayType(t))));
		record("  StaticFieldHelper.isArrayType         = "
			+ attempt(() -> Std.string(StaticFieldHelper.isArrayType(t))));
		record("  SwiftArrayBoundary.sourceStorage(raw)   = "
			+ attempt(() -> Std.string(SwiftArrayBoundary.sourceStorage(t, false, false))));
		record("  SwiftArrayBoundary.sourceStorage(empty) = "
			+ attempt(() -> Std.string(SwiftArrayBoundary.sourceStorage(t, true, false))));
		record("  SwiftArrayBoundary.sourceStorage(null)  = "
			+ attempt(() -> Std.string(SwiftArrayBoundary.sourceStorage(t, false, true))));
		record("  SwiftArrayBoundary.isOptionalArrayType = "
			+ attempt(() -> Std.string(SwiftArrayBoundary.isOptionalArrayType(t))));
		record("  SwiftArrayBoundary.isBoundary(source, mutable destination) = "
			+ attempt(() -> Std.string(SwiftArrayBoundary.isBoundary(t, mutableDestination()))));
		record("  SwiftType.rawArrayElement       = "
			+ attempt(() -> Std.string(SwiftType.rawArrayElement(t))));
		record("  PolicyQueries.stdStringCategory = "
			+ attempt(() -> Std.string(PolicyQueries.stdStringCategory(t))));
	}

	/** Runs one helper call and reports its exception so the matrix continues. */
	static function attempt(run:Void -> String):String {
		try {
			return run();
		} catch (problem:Any) {
			return "raised: " + Std.string(problem);
		}
	}

	static function followRecord(t:Type):String {
		try {
			final followed = Context.follow(t);
			return Std.string(followed) + " | " + identity(followed);
		} catch (problem:Any) {
			return "Context.follow rejected this form: " + Std.string(problem);
		}
	}

	static function identity(t:Type):String {
		return switch (t) {
			case TInst(c, params): "TInst name=" + c.get().name + " pack=" + c.get().pack.join(".")
				+ " module=" + c.get().module + " params=" + params.length;
			case TAbstract(a, params): "TAbstract name=" + a.get().name + " pack=" + a.get().pack.join(".")
				+ " module=" + a.get().module + " params=" + params.length;
			case TType(d, params): "TType name=" + d.get().name + " pack=" + d.get().pack.join(".")
				+ " module=" + d.get().module + " params=" + params.length;
			case TEnum(en, _): "TEnum name=" + en.get().name + " module=" + en.get().module;
			case TLazy(_): "TLazy";
			case TMono(_): "TMono";
			case TDynamic(_): "TDynamic";
			case TAnonymous(_): "TAnonymous";
			case TFun(_, _): "TFun";
		};
	}

	static function outerNullable(t:Type):Bool {
		return switch (t) {
			case TAbstract(a, _) if (a.get().name == "Null"): true;
			case _: false;
		};
	}

	static function elementNullable(element:Null<Type>):String {
		if (element == null)
			return "no element reported";
		return Std.string(PolicyQueries.isNullableType(element));
	}

	// ------------------------------------------------------------------
	// Destinations and small constructors
	// ------------------------------------------------------------------

	static function mutableDestination():Type {
		return switch (Context.getType("Array")) {
			case TInst(c, _): TInst(c, [Context.getType("Int")]);
			case other: throw "Array is not a class type: " + Std.string(other);
		};
	}

	static function readOnlyType():Type {
		return readOnlyOf(Context.getType("Int"));
	}

	static function readOnlyOf(element:Type):Type {
		return switch (Context.getType("std.ReadOnlyArray")) {
			case TAbstract(a, _): TAbstract(a, [element]);
			case other: throw "std.ReadOnlyArray is not an abstract: " + Std.string(other);
		};
	}

	static function nullOf(inner:Type):Type {
		return switch (Context.getType("Null")) {
			case TAbstract(a, _): TAbstract(a, [inner]);
			case other: throw "Null is not an abstract: " + Std.string(other);
		};
	}

	static function classOf(path:String):ClassType {
		return switch (Context.getType(path)) {
			case TInst(c, _): c.get();
			case other: throw path + " is not a class type: " + Std.string(other);
		};
	}
#end
}
