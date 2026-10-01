package admission;

#if macro
import haxe.macro.Context;
import haxe.macro.Type;
import SourceComparisonAnalysis;
import SourceComparisonAnalysis.SourceAdmissionEdge;
import SourceComparisonAnalysis.SourceAdmissionResult;
import SourceComparisonAnalysis.SourceComparisonRequest;
import SourceComparisonAnalysis.SourceObligationSite;
import SourceComparisonAnalysis.SourceRejectionReason;
import SourceContainerAnalysis;
#end

/** Runs the finite source admission entry over the authored declarations and
    prints one canonical line per discriminator. The lines are compared with
    admission-expected.tsv. */
class AdmissionProbe {
	public static function main():Void {}

#if macro
	public static function run():Void {
		observe("unused-parameter-actual-ignored", () -> admit("admission.AdmissionCases.Unused", [reference()], SortedKey));
		observe("unused-parameter-actual-equality", () -> admit("admission.AdmissionCases.Unused", [reference()], OptionalEqualityCapability));
		observe("swap-requires-both-slots", () -> admit("admission.AdmissionCases.Swap", ownBinders("admission.AdmissionCases.Swap"), SortedKey));
		observe("swap-second-actual-rejected", () -> admit("admission.AdmissionCases.Swap", [intType(), reference()], SortedKey));
		observe("swap-first-actual-rejected", () -> admit("admission.AdmissionCases.Swap", [reference(), intType()], SortedKey));
		observe("chain-demanded-array-rejected", () -> admit("admission.AdmissionCases.Chain", [intType()], SortedKey));
		observe("nested-demand-concrete", () -> admit("admission.AdmissionCases.NestedDemand", [intType()], SortedKey));
		observe("nested-demand-unsupplied", () -> admit("admission.AdmissionCases.NestedDemand", ownBinders("admission.AdmissionCases.NestedDemand"), SortedKey));
		observe("same-name-method-binder-owner", methodBinderSlots);
		observe("expand-recursive-readonly-admitted", () -> admit("admission.AdmissionCases.Expand", [intType()], SortedKey));
		observe("mutual-recursion-rejected", () -> admit("admission.AdmissionCases.MutA", [intType()], SortedKey));
		observe("mutual-recursion-reversed-order", () -> admit("admission.AdmissionCases.MutA2", [intType()], SortedKey));
		observe("mutual-recursion-repeat-entry", () -> admit("admission.AdmissionCases.MutA", [intType()], SortedKey));
		observe("flat-chain-beyond-prior-limit", () -> admit("admission.AdmissionCases.Step0", [], SortedKey));
		observe("reserved-spelling-not-a-binder", () -> admit("admission.AdmissionCases.PrefixTrap", ownBinders("admission.AdmissionCases.PrefixTrap"), SortedKey));
		observe("reserved-spelling-collision", () -> admit("admission.AdmissionCases.Trap", ownBinders("admission.AdmissionCases.Trap"), SortedKey));
		observe("same-spelling-demand-transfer", () -> admit("admission.AdmissionCases.CrossOwner", [boxed(intType())], SortedKey));
		observe("same-spelling-nested-rejected", () -> admit("admission.AdmissionCases.CrossOwner", [boxed(reference())], SortedKey));
		observe("float-key-rejected", () -> admit("admission.AdmissionCases.FloatKey", [], SortedKey));
		observe("float-equality-admitted", () -> admit("admission.AdmissionCases.FloatKey", [], OptionalEqualityCapability));
		observe("generic-sorted-unsupplied", () -> admit("admission.AdmissionCases.GenericValue", ownBinders("admission.AdmissionCases.GenericValue"), SortedKey));
		observe("generic-equality-parameter-rejected", () -> admit("admission.AdmissionCases.GenericValue", ownBinders("admission.AdmissionCases.GenericValue"), OptionalEqualityCapability));
		observe("generic-equality-concrete-admitted", () -> admit("admission.AdmissionCases.GenericValue", [intType()], OptionalEqualityCapability));
	}

	static function admit(path:String, arguments:Array<Type>, request:SourceComparisonRequest):String {
		return format(SourceComparisonAnalysis.admit(declaration(path), arguments, request), declaration(path));
	}

	static function methodBinderSlots():String {
		final owner = declaration("admission.AdmissionCases.MethodBinderOwner");
		final type = owner.get();
		var method:Null<ClassField> = null;
		for (field in type.fields.get())
			if (field.name == "same") method = field;
		if (method == null || method.params.length != 1)
			throw new haxe.Exception("same method type parameter was not exposed");
		final classSlot = SourceComparisonAnalysis.ownParameterSlot(type.params[0].t, owner);
		final methodSlot = SourceComparisonAnalysis.ownParameterSlot(method.params[0].t, owner);
		return "owner=" + (classSlot == null ? "none" : Std.string(classSlot)) + " method="
			+ (methodSlot == null ? "none" : Std.string(methodSlot));
	}

	static function format(result:SourceAdmissionResult, root:Ref<ClassType>):String {
		return switch (result) {
			case SourceAdmissionAdmitted(summary):
				"admitted required=[" + joins(summary.requiredSlots) + "] unsupplied=[" + joins(summary.unsuppliedSlots) + "] visited="
					+ summary.visitedDeclarations;
			case SourceAdmissionRejected(reason, site):
				"rejected " + reasonText(reason) + " type=" + describe(site.type, site.declaration) + " at=" + place(site, root) + " chain="
					+ chainText(site, root);
			case SourceAdmissionIncomplete(reason, site):
				"incomplete " + Std.string(reason) + " type=" + describe(site.type, site.declaration) + " at=" + place(site, root) + " chain="
					+ chainText(site, root);
		}
	}

	static function reasonText(reason:SourceRejectionReason):String {
		return switch (reason) {
			case UnsupportedStoredFieldType(_): "stored-field";
			case UnsupportedDemandedArgumentType(_): "demanded-argument";
			case ParameterWithoutEqualityEvidence(slot): "parameter-without-evidence slot=" + slot;
		}
	}

	static function place(site:SourceObligationSite, root:Ref<ClassType>):String {
		final name = site.declaration.get().name;
		final atRequest = name == root.get().name && site.field == null;
		return atRequest ? "request" : name + (site.field == null ? "" : "." + site.field);
	}

	static function chainText(site:SourceObligationSite, root:Ref<ClassType>):String {
		final parts = [for (edge in site.chain) edge.declaration.get().name + "." + edge.field];
		return "[" + parts.join(",") + "]" + (site.cycleBoundary ? "cycle" : "");
	}

	static function describe(type:Null<Type>, root:Ref<ClassType>):String {
		if (type == null) return "none";
		final slot = SourceComparisonAnalysis.ownParameterSlot(type, root);
		if (slot != null) return root.get().params[slot].name;
		final facts = SourceContainerAnalysis.analyze(type);
		return switch (facts.face) {
			case MutableArray(element): "Array<" + describe(element, root) + ">";
			case ReadOnlyArrayFace(element): "std.ReadOnlyArray<" + describe(element, root) + ">";
			case UnresolvedSource(reason): "unresolved:" + Std.string(reason);
			case OtherSourceType: terminal(facts.resolvedType, root);
		}
	}

	static function terminal(type:Type, root:Ref<ClassType>):String {
		return switch (type) {
			case TInst(reference, arguments): named(reference.get().name, arguments, root);
			case TAbstract(reference, arguments): named(reference.get().name, arguments, root);
			case TEnum(reference, arguments): named(reference.get().name, arguments, root);
			case TAnonymous(_): "{anonymous}";
			case _: Std.string(type);
		}
	}

	static function named(name:String, arguments:Array<Type>, root:Ref<ClassType>):String {
		return arguments.length == 0 ? name : name + "<" + [for (argument in arguments) describe(argument, root)].join(",") + ">";
	}

	static function joins(slots:Array<Int>):String {
		return [for (slot in slots) Std.string(slot)].join(",");
	}

	static function declaration(path:String):Ref<ClassType> {
		return switch (Context.getType(path)) {
			case TInst(reference, _): reference;
			case _: throw new haxe.Exception(path + " did not resolve as a class");
		}
	}

	static function ownBinders(path:String):Array<Type> {
		return [for (parameter in declaration(path).get().params) parameter.t];
	}

	static function boxed(argument:Type):Type {
		return TInst(declaration("admission.AdmissionCases.Box"), [argument]);
	}

	static function reference():Type {
		return Context.getType("admission.AdmissionCases.Reference");
	}

	static function intType():Type {
		return Context.getType("Int");
	}

	static function observe(name:String, result:Void->String):Void {
		try {
			Sys.println(name + "\t" + result());
		} catch (failure:haxe.Exception) {
			Sys.println(name + "\tprobe-error:" + failure.message);
		}
	}
#end
}
