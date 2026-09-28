package comparisonplan;

#if macro
import haxe.macro.Context;
import haxe.macro.Type;
import SourceComparisonAnalysis;
import SourceComparisonAnalysis.SourceComparisonRequest;
import SourceComparisonAnalysis.SourceComparisonShape;
import SourceComparisonAnalysis.SourceComparisonPlanResult;
import PolicyQueries;
import swiftcompiler.SwiftComparisonPlan;
#end

class ComparisonPlanProbe {
	public static function main():Void {}

#if macro
	public static function run():Void {
		final intType = Context.getType("Int");
		final boxType = Context.getType("comparisonplan.PlanCases.Box");
		final boxRef = switch (boxType) {
			case TInst(ref, _): ref;
			case _: Context.error("Box did not resolve as a class", Context.currentPos()); null;
		};
		final nestedBox:Type = TInst(boxRef, [TInst(boxRef, [intType])]);
		observe("field-order", () -> {
			final node = getRecord("comparisonplan.PlanCases.FieldOrder", []);
			join([for (field in node.fields) field.field.name]);
		});
		observe("parameter-schema-operations", () -> ["ComparedParameter", "IgnoredParameter", "NestedParameter", "NullableParameter", "SequenceParameter"]
			.map(name -> {
				final declaration = getClass("comparisonplan.PlanCases." + name);
				final schema = SourceComparisonAnalysis.analyzeRecordSchema(declaration);
				final operations = switch (SwiftComparisonPlan.selectSchema(declaration, SortedKey)) {
					case SwiftComparisonPlanReady(plan): "ready:" + join([for (index in plan.requiredArguments) Std.string(index)]);
					case SwiftComparisonPlanFailed(path, reason, _): "failed:" + path + ":" + reason;
					case SwiftComparisonPlanUnresolved(path, reason): "unresolved:" + path + ":" + reason;
				};
				name + "=" + operations + "[" + join([for (field in schema.fields) field.field.name + ":" + schemaShape(field.shape)]) + "]";
			}).join("|"));
		observe("nested-binder-owner-and-operation", () -> {
			final outer = getClass("comparisonplan.PlanCases.NestedParameter");
			final foreign = getClass("comparisonplan.PlanCases.ComparedParameter");
			final schema = SourceComparisonAnalysis.analyzeRecordSchema(outer);
			final argument = switch (schema.fields[0].shape) {
				case RecordUseShape(_, arguments) if (arguments.length == 1): arguments[0];
				case _: throw new haxe.Exception("nested field has no single record argument");
			};
			final ownerSlot = SourceComparisonAnalysis.ownParameterSlot(argument, RecordDeclaration(outer));
			final foreignSlot = SourceComparisonAnalysis.ownParameterSlot(argument, RecordDeclaration(foreign));
			final foreignParameter = foreign.get().params[0].t;
			final foreignOwnSlot = SourceComparisonAnalysis.ownParameterSlot(foreignParameter, RecordDeclaration(foreign));
			final foreignAsOuterSlot = SourceComparisonAnalysis.ownParameterSlot(foreignParameter, RecordDeclaration(outer));
			final foreignAsSchemaArgument = SourceComparisonAnalysis.schemaParameterIndex(foreignParameter, schema.arguments);
			final sameName = outer.get().params[0].name == foreign.get().params[0].name;
			final selected = switch (SwiftComparisonPlan.selectSchema(outer, SortedKey)) {
				case SwiftComparisonPlanReady(plan):
					switch (plan.fields[0].operation) {
						case SwiftRecordOrder(nested, arguments) if (arguments.length == 1):
							final nestedSlot = switch (nested.fields[0].operation) {
								case SwiftParameterOrder(index): Std.string(index);
								case _: "wrong-nested-operation";
							};
							"record-parameter:" + nestedSlot + ":parent-slot:"
								+ SourceComparisonAnalysis.schemaParameterIndex(arguments[0], plan.source.source.arguments);
						case _: "wrong-operation";
					};
				case _: "no-plan";
			};
			"same-name=" + sameName + ":owner=" + ownerSlot + ":foreign=" + foreignSlot + ":foreign-own=" + foreignOwnSlot
				+ ":foreign-as-outer=" + foreignAsOuterSlot + ":foreign-as-schema-argument=" + foreignAsSchemaArgument
				+ ":selected=" + selected;
		});
		observe("finite-box-nesting", () -> {
			final node = SourceComparisonAnalysis.analyzeRecord(boxRef, [nestedBox]);
			final inner = switch (node.fields[0].shape) {
				case RecordShape(nested): nested;
				case _: null;
			};
			inner == null ? "missing nested record" : Std.string(node.state) + ">" + Std.string(inner.state) + ">" +
				Std.string(inner.fields[0].shape);
		});
		observe("finite-argument-permutation", () -> {
			final swap = getClass("comparisonplan.PlanCases.Swap");
			final node = SourceComparisonAnalysis.analyzeRecord(swap, [intType, Context.getType("String")]);
			planResult(node);
		});
		observe("finite-growth-stabilizes", () -> {
			final finite = getClass("comparisonplan.PlanCases.FiniteGrowth");
			final node = SourceComparisonAnalysis.analyzeRecord(finite, [intType, intType]);
			planResult(node);
		});
		observe("flat-25-record-chain", () -> {
			final node = getRecord("comparisonplan.FlatCases.Flat24", []);
			planResult(node);
		});
		observe("changing-argument-expansion", () -> {
			final expand = getClass("comparisonplan.PlanCases.Expand");
			// Inject a low budget to prove incomplete analysis propagates as a
			// distinct result; production analysis has no arbitrary source cap.
			final node = SourceComparisonAnalysis.analyzeRecord(expand, [intType], 24);
			switch (SourceComparisonAnalysis.comparisonPlan(node, SortedKey)) {
				case ComparisonPlanUnresolved(_, reason): "analysis-incomplete:" + (reason.indexOf("requested analysis work limit") >= 0);
				case ComparisonPlanReady(_): "unexpected-ready";
				case ComparisonPlanFailed(_, reason, _): "wrongly-source-failed:" + reason;
			}
		});
		observe("computed-field-excluded", () -> {
			final node = getRecord("comparisonplan.PlanCases.FieldOrder", []);
			join([for (field in node.fields) field.field.name]);
		});
		observe("same-short-name-identities", () -> {
			final left = getClass("comparisonplan.left.Same");
			final right = getClass("comparisonplan.right.Same");
			Std.string(left != right) + ">" + left.get().name + ">" + right.get().name;
		});
		observe("float-key-and-capability", () -> capability("FloatKey"));
		observe("bool-key-and-capability", () -> capability("BoolKey"));
		observe("alias-int-shape", () -> shape("comparisonplan.CountAlias"));
		observe("alias-sequence-shape", () -> {
			final alias = switch (Context.getType("comparisonplan.SequenceAlias")) {
				case TType(ref, _): TType(ref, [intType]);
				case other: other;
			};
			shapeOf(alias);
		});
	}

	static function capability(path:String):String {
		final node = getRecord("comparisonplan.PlanCases." + path, []);
		final optional = planResult(node, OptionalEqualityCapability);
		final sorted = planResult(node, SortedKey);
		return optional + "|sorted=" + sorted + "|admitted=" + PolicyQueries.canEmitDataClassComparator(node.declaration);
	}

	static function planResult(node:SourceRecordNode, request:SourceComparisonRequest = SortedKey):String {
		return switch (SourceComparisonAnalysis.comparisonPlan(node, request)) {
			case ComparisonPlanReady(plan): "ready:" + plan.complete;
			case ComparisonPlanFailed(path, reason, sourceType): "analysis-failed:" + path + ":" + reason + ":" + (sourceType == null ? "no-type" : Std.string(sourceType));
			case ComparisonPlanUnresolved(path, reason): "analysis-incomplete:" + path + ":" + reason;
		};
	}

	static function shape(path:String):String return shapeOf(Context.getType(path));

	static function schemaShape(shape:SourceComparisonShape):String {
		return switch (shape) {
			case RecordUseShape(record, arguments):
				"RecordUse(" + record.declaration.name + ",args=" + arguments.length + ")";
			case _: Std.string(shape);
		};
	}

	static function shapeOf(type:Type):String {
		return switch (SourceComparisonAnalysis.analyzeShape(type)) {
			case IntShape: "Int";
			case SequenceShape(_): "Sequence";
			case NullableShape(_): "Nullable";
			case _: Std.string(SourceComparisonAnalysis.analyzeShape(type));
		};
	}

	static function getRecord(path:String, args:Array<Type>):SourceRecordNode {
		return SourceComparisonAnalysis.analyzeRecord(getClass(path), args);
	}

	static function getClass(path:String):Ref<ClassType> {
		return switch (Context.getType(path)) {
			case TInst(ref, _): ref;
			case _: Context.error(path + " did not resolve as a class", Context.currentPos()); null;
		};
	}

	static function join(values:Array<String>):String return values.join(",");

	static function observe(name:String, result:Void->String):Void {
		try {
			Sys.println(name + "\t" + result());
		} catch (failure:haxe.Exception) {
			Sys.println(name + "\tprobe-error:" + failure.message);
		}
	}
#end
}
