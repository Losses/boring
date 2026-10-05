#if macro
import haxe.macro.Context;
import haxe.macro.Expr.Field;
import haxe.macro.Type;
import SourceComparisonAnalysis;

/** Runs via @:build while revp9.Trigger compiles (compiled-class host,
    same as param-identity probe 3). Checks: (A) nested Pair record dedup
    for Boxed<T>, (B) node states under maxRecordNodes=2, (C) concrete
    Int control. Prints DEDUP / LIMITED / CONTROL lines parsed by run.sh. */
class DedupProbe {
	static var once = false;

	macro public static function run():Array<Field> {
		final fields = Context.getBuildFields();
	final localRef = Context.getLocalClass();
		if (localRef == null)
			return fields;
		final local = localRef.get();
		if (local.name != "Trigger" || local.pack.length != 1 || local.pack[0] != "revp9")
			return fields;
		if (once)
			return fields;
		once = true;

		final boxedRef = SourceComparisonAnalysis.declarationReference(clsOf("revp9.Boxed"));
		final tB = boxedRef.get().params[0].t;

		// A. default budget: nested Pair nodes for child / pair should be ONE node.
		final node = SourceComparisonAnalysis.analyzeRecord(boxedRef, [tB]);
		var childNode:Null<SourceRecordNode> = null;
		var pairNode:Null<SourceRecordNode> = null;
		for (f in node.fields) {
			final nested = nestedNode(f.shape);
			if (f.field.name == "child")
				childNode = nested;
			if (f.field.name == "pair")
				pairNode = nested;
		}
		final dedup = childNode != null && childNode == pairNode;
		Sys.println('DEDUP ok:$dedup');
		if (childNode != null)
			Sys.println('DEDUP child state:${childNode.state} fields:${childNode.fields.length}');
		if (pairNode != null)
			Sys.println('DEDUP pair state:${pairNode.state} fields:${pairNode.fields.length}');

		// B. maxRecordNodes=2: with correct dedup the logical graph is
		// Boxed + Pair = 2 nodes, so both nested nodes must stay Complete.
		final limited = SourceComparisonAnalysis.analyzeRecord(boxedRef, [tB], 2);
		var allComplete = true;
		var sawNested = false;
		for (f in limited.fields) {
			final nested = nestedNode(f.shape);
			if (nested == null)
				continue;
			sawNested = true;
			Sys.println('LIMITED field ${f.field.name} state:${nested.state}');
			if (!isComplete(nested.state))
				allComplete = false;
		}
		Sys.println('LIMITED allNestedComplete:$allComplete sawNested:$sawNested');

		// C. concrete Int control: dedup must hold with or without the fix.
		final concrete = SourceComparisonAnalysis.analyzeRecord(boxedRef, [Context.getType("Int")]);
		var cChild:Null<SourceRecordNode> = null;
		var cPair:Null<SourceRecordNode> = null;
		for (f in concrete.fields) {
			final nested = nestedNode(f.shape);
			if (f.field.name == "child")
				cChild = nested;
			if (f.field.name == "pair")
				cPair = nested;
		}
		Sys.println('CONTROL concrete dedup:${cChild != null && cPair == cChild}');
		return fields;
	}

	static function isComplete(state:SourceRecordState):Bool {
		return switch (state) {
			case Complete: true;
			case _: false;
		}
	}

	static function nestedNode(shape:SourceComparisonShape):Null<SourceRecordNode> {
		return switch (shape) {
			case NullableShape(inner): nestedNode(inner);
			case RecordShape(n): n;
			case RecordUseShape(n, _): n;
			case _: null;
		}
	}

	static function clsOf(path:String):ClassType {
		return switch (Context.getType(path)) {
			case TInst(reference, _): reference.get();
			case other: throw "unexpected " + path;
		}
	}
}
#end
