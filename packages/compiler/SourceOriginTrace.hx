#if (macro || reflaxe_runtime)
package;

import haxe.ds.ObjectMap;
import haxe.macro.Context;
import haxe.macro.Type;
import haxe.macro.TypedExprTools;
import SourceOriginFragment.SourceOrigin;
import SourceOriginFragment.SourceOriginSpan;

private class SourceOriginNode {
	public final origin:SourceOrigin;
	public final ambiguous:Bool;
	public final callTarget:Null<TypedExpr>;
	public final callArgs:Array<TypedExpr>;
	public var emitted:Int = 0;
	public var lineIndex:Int = -1;

	public function new(origin:SourceOrigin, ambiguous:Bool, callTarget:Null<TypedExpr>, callArgs:Array<TypedExpr>) {
		this.origin = origin;
		this.ambiguous = ambiguous;
		this.callTarget = callTarget;
		this.callArgs = callArgs;
	}
}

/** Captures identity before target rewrites and accepts only the same call node. */
class SourceOriginTrace {
	final nodes:ObjectMap<TypedExpr, SourceOriginNode> = new ObjectMap();
	var nextId:Int = 0;

	function new() {}

	public static function beforeRewrites(root:TypedExpr, module:String, className:String, field:String):SourceOriginTrace {
		final trace = new SourceOriginTrace();
		trace.visit(root, module, className, field);
		return trace;
	}

	function visit(node:TypedExpr, module:String, className:String, field:String):Void {
		final prior = nodes.get(node);
		if (prior != null) {
			nodes.set(node, new SourceOriginNode(prior.origin, true, prior.callTarget, prior.callArgs));
			TypedExprTools.iter(node, child -> visit(child, module, className, field));
			return;
		}
		final info = Context.getPosInfos(node.pos);
		final occurrenceId = module + "." + className + "." + field + "#" + StringTools.lpad(Std.string(nextId), "0", 6);
		nextId++;
		var target:Null<TypedExpr> = null;
		var args:Array<TypedExpr> = [];
		switch (node.expr) {
			case TCall(callee, callArgs):
				target = callee;
				args = callArgs.copy();
			default:
		}
		final origin:SourceOrigin = {
			occurrenceId: occurrenceId,
			sourceFile: info.file,
			sourceStart: info.min,
			sourceEnd: info.max
		};
		nodes.set(node, new SourceOriginNode(origin, false, target, args));
		TypedExprTools.iter(node, child -> visit(child, module, className, field));
	}

	/** Called only by the direct expression-statement renderer. */
	public function noteDirectCall(node:TypedExpr, lineIndex:Int, emittedLine:String):Void {
		if (emittedLine.indexOf("\n") >= 0)
			return;
		final entry = nodes.get(node);
		if (entry == null || entry.ambiguous || entry.callTarget == null)
			return;
		switch (node.expr) {
			case TCall(callee, args) if (callee == entry.callTarget && sameArguments(args, entry.callArgs)):
				entry.emitted++;
				entry.lineIndex = lineIndex;
			default:
		}
	}

	function sameArguments(left:Array<TypedExpr>, right:Array<TypedExpr>):Bool {
		if (left.length != right.length)
			return false;
		for (i in 0...left.length) {
			if (left[i] != right[i])
				return false;
		}
		return true;
	}

	public function fragment(lines:Array<String>):SourceOriginFragment {
		final spans:Array<SourceOriginSpan> = [];
		for (entry in nodes) {
			if (entry.ambiguous || entry.emitted != 1 || entry.lineIndex < 0 || entry.lineIndex >= lines.length)
				continue;
			var offset = 0;
			for (i in 0...entry.lineIndex) {
				offset += SourceOriginFragment.utf16Length(lines[i]) + 1;
			}
			final line = lines[entry.lineIndex];
			spans.push({
				start: offset,
				end: offset + SourceOriginFragment.utf16Length(line),
				origin: entry.origin,
				unmappedReason: null
			});
		}
		spans.sort((a, b) -> Reflect.compare(a.start, b.start));
		return new SourceOriginFragment(lines.join("\n"), spans);
	}
}
#end
