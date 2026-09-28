package admission;

#if macro
import haxe.macro.Context;
import haxe.macro.Type;
import SourceComparisonAnalysis;
import SourceComparisonAnalysis.SourceAdmissionResult;
import SourceComparisonAnalysis.SourceComparisonRequest;
import SourceComparisonAnalysis.SourceDeclarationIdentity;
import SourceComparisonAnalysis.SourceFieldTerm;
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
		// The legal recursive alias admits, and its formal stays undemanded even
		// when the actual handed to that slot is the binder itself.
		observe("grow-recursive-alias-admitted", () -> admitAt(aliasPath("admission.AdmissionCases.Grow"), [intType()], SortedKey));
		observe("grow-binder-actual-ignored", () -> admitAt(aliasPath("admission.AdmissionCases.Grow"), ownAliasBinders("admission.AdmissionCases.Grow"), SortedKey));
		observe("grow-recursive-alias-term", () -> terms(aliasPath("admission.AdmissionCases.Grow")));
		// One demanded slot plus a growing recursive edge stays a finite graph.
		observe("expand-demand-combined-concrete", () -> admit("admission.AdmissionCases.ExpandDemand", [intType()], SortedKey));
		observe("expand-demand-combined-unsupplied", () -> admit("admission.AdmissionCases.ExpandDemand", ownBinders("admission.AdmissionCases.ExpandDemand"), SortedKey));
		observe("expand-demand-combined-rejected", () -> admit("admission.AdmissionCases.ExpandDemand", [reference()], SortedKey));
		observe("nested-demand-term", () -> terms(classPath("admission.AdmissionCases.NestedDemand")));
		// Demand solved over the alias declaration. `AliasChain` rejects because
		// its recursive edge binds a demanded slot to a mutable array at the
		// second unfolding; `AliasLoop` admits because the same edge binds it
		// to a comparable record application.
		observe("alias-chain-recursive-mutable-rejected", () -> admitAt(aliasPath("admission.AdmissionCases.AliasChain"), [intType(), intType()], SortedKey));
		observe("alias-loop-demanded-slot-admitted", () -> admitAt(aliasPath("admission.AdmissionCases.AliasLoop"), [intType()], SortedKey));
		observe("alias-loop-demanded-slot-rejected", () -> admitAt(aliasPath("admission.AdmissionCases.AliasLoop"), [reference()], SortedKey));
		observe("alias-demand-through-body-admitted", () -> admitAt(aliasPath("admission.AdmissionCases.AliasDemand"), [intType()], SortedKey));
		observe("alias-demand-binders-unsupplied", () -> admitAt(aliasPath("admission.AdmissionCases.AliasDemand"), ownAliasBinders("admission.AdmissionCases.AliasDemand"), SortedKey));
		observe("alias-demand-through-body-rejected", () -> admitAt(aliasPath("admission.AdmissionCases.AliasDemand"), [reference()], SortedKey));
		// 80 distinct alias heads, no cap, reaching the mutable array.
		observe("alias-hop-chain-80-visited", () -> admitAt(aliasPath("admission.AdmissionCases.Hop01"), [intType()], SortedKey));
		// A method binder that shares the class binder's spelling is an ordinary
		// source type, never a slot of the owning class.
		observe("method-binder-actual-not-a-slot", () -> admit("admission.AdmissionCases.GenericValue", [methodBinderType()], SortedKey));
		observe("same-name-class-acyclic-admitted", () -> admit("admission.names.first.Point", [intType()], SortedKey));
		observe("same-name-alias-admitted", () -> admitAt(aliasPath("admission.aliasnames.first.Growish"), [intType()], SortedKey));
		observe("same-name-alias-rejected", () -> admitAt(aliasPath("admission.aliasnames.second.Growish"), [intType()], SortedKey));
	}

	static function admit(path:String, arguments:Array<Type>, request:SourceComparisonRequest):String {
		final root = classRef(path);
		return render(SourceComparisonAnalysis.admit(root, arguments, request), RecordDeclaration(root), false);
	}

	static function admitAt(path:SourceDeclarationIdentity, arguments:Array<Type>, request:SourceComparisonRequest):String {
		return render(SourceComparisonAnalysis.admitDeclaration(path, arguments, request), path, true);
	}

	static function terms(path:SourceDeclarationIdentity):String {
		return [for (entry in SourceComparisonAnalysis.declarationTerms(path)) (entry.field == null ? "body" : entry.field) + "=" + termText(entry.term, path)]
			.join("|");
	}

	static function methodBinderSlots():String {
		final owner = classRef("admission.AdmissionCases.MethodBinderOwner");
		final type = owner.get();
		var method:Null<ClassField> = null;
		for (field in type.fields.get())
			if (field.name == "same") method = field;
		if (method == null || method.params.length != 1)
			throw new haxe.Exception("same method type parameter was not exposed");
		final classSlot = SourceComparisonAnalysis.ownParameterSlot(type.params[0].t, RecordDeclaration(owner));
		final methodSlot = SourceComparisonAnalysis.ownParameterSlot(method.params[0].t, RecordDeclaration(owner));
		return "owner=" + (classSlot == null ? "none" : Std.string(classSlot)) + " method="
			+ (methodSlot == null ? "none" : Std.string(methodSlot));
	}

	/** The type parameter of one method binder in another declaration, spelled
	    `T` exactly like the class binder it is handed to. */
	static function methodBinderType():Type {
		final owner = classRef("admission.AdmissionCases.MethodBinderOwner").get();
		for (field in owner.fields.get())
			if (field.name == "same")
				return field.params[0].t;
		throw new haxe.Exception("same method type parameter was not exposed");
	}

	/** One canonical result line. `brief` replaces the nested chain with its
	    length and reports the visited declarations, so a walk that crosses 79
	    edges stays one authored line. */
	static function render(result:SourceAdmissionResult, root:SourceDeclarationIdentity, brief:Bool):String {
		return switch (result) {
			case SourceAdmissionAdmitted(summary):
				"admitted required=[" + joins(summary.requiredSlots) + "] unsupplied=[" + joins(summary.unsuppliedSlots) + "] visited="
					+ summary.visitedDeclarations;
			case SourceAdmissionRejected(reason, site, visited):
				"rejected " + reasonText(reason) + " type=" + describe(site.type, root) + " at=" + place(site, root) + " chain="
					+ (brief ? edgeCount(site) : chainText(site, root)) + (brief ? " visited=" + visited : "");
			case SourceAdmissionIncomplete(reason, site, visited):
				"incomplete " + Std.string(reason) + " type=" + describe(site.type, root) + " at=" + place(site, root) + " chain="
					+ (brief ? edgeCount(site) : chainText(site, root)) + (brief ? " visited=" + visited : "");
		}
	}

	static function reasonText(reason:SourceRejectionReason):String {
		return switch (reason) {
			case UnsupportedStoredFieldType(_): "stored-field";
			case UnsupportedDemandedArgumentType(_): "demanded-argument";
			case ParameterWithoutEqualityEvidence(slot): "parameter-without-evidence slot=" + slot;
		}
	}

	static function place(site:SourceObligationSite, root:SourceDeclarationIdentity):String {
		final atRequest = sameIdentityName(site.declaration, root) && site.field == null;
		return atRequest ? "request" : identityName(site.declaration) + (site.field == null ? "" : "." + site.field);
	}

	static function chainText(site:SourceObligationSite, root:SourceDeclarationIdentity):String {
		final parts = [for (edge in site.chain) identityName(edge.declaration) + (edge.field == null ? "" : "." + edge.field)];
		return "[" + parts.join(",") + "]" + (site.cycleBoundary ? "cycle" : "");
	}

	static function edgeCount(site:SourceObligationSite):String {
		return "[" + site.chain.length + " edges]" + (site.cycleBoundary ? "cycle" : "");
	}

	/** The written source term of one declaration, rendered from the term the
	    analyzer keeps. A record application prints `Name[args]`, an alias
	    application `alias Name[args]`, so the recursive edge and the faces it
	    carries stay readable in one authored line. */
	static function termText(term:SourceFieldTerm, root:SourceDeclarationIdentity):String {
		return switch (term) {
			case TermInt(_): "Int";
			case TermString(_): "String";
			case TermFloat(_): "Float";
			case TermBool(_): "Bool";
			case TermEnum(declaration, _, _): "Enum(" + declaration.name + ")";
			case TermBinder(owner, slot, _): identityName(owner) + "." + slot;
			case TermApplication(declaration, arguments, _): identityName(declaration) + "[" + argumentText(arguments, root) + "]";
			case TermAlias(declaration, arguments, _): "alias " + identityName(declaration) + "[" + argumentText(arguments, root) + "]";
			case TermNull(inner, _): "Null(" + termText(inner, root) + ")";
			case TermReadOnlyArray(inner, _): "std.ReadOnlyArray(" + termText(inner, root) + ")";
			case TermUnsupported(type): "unsupported:" + describe(type, root);
			case TermUnresolved(reason, _): "unresolved:" + Std.string(reason);
		}
	}

	static function argumentText(arguments:Array<SourceFieldTerm>, root:SourceDeclarationIdentity):String {
		return [for (argument in arguments) termText(argument, root)].join(",");
	}

	static function describe(type:Null<Type>, root:SourceDeclarationIdentity):String {
		if (type == null) return "none";
		final slot = SourceComparisonAnalysis.ownParameterSlot(type, root);
		if (slot != null) return SourceComparisonAnalysis.declarationParameters(root)[slot].name;
		// An alias occurrence is printed as written. Resolving it here would
		// re-enter the shared resolution walk with one more layer per round.
		return switch (type) {
			case TType(reference, arguments): identityName(AliasDeclaration(reference)) + "<" + argumentTypes(arguments, root) + ">";
			case _: aliasFreeDescribe(type, root);
		}
	}

	static function aliasFreeDescribe(type:Type, root:SourceDeclarationIdentity):String {
		final facts = SourceContainerAnalysis.analyze(type);
		return switch (facts.face) {
			case MutableArray(element): "Array<" + describe(element, root) + ">";
			case ReadOnlyArrayFace(element): "std.ReadOnlyArray<" + describe(element, root) + ">";
			case UnresolvedSource(reason): "unresolved:" + Std.string(reason);
			case OtherSourceType: terminal(facts.resolvedType, root);
		}
	}

	static function argumentTypes(arguments:Array<Type>, root:SourceDeclarationIdentity):String {
		return [for (argument in arguments) describe(argument, root)].join(",");
	}

	static function terminal(type:Type, root:SourceDeclarationIdentity):String {
		return switch (type) {
			case TInst(reference, arguments): named(reference.get().name, arguments, root);
			case TAbstract(reference, arguments): named(reference.get().name, arguments, root);
			case TEnum(reference, arguments): named(reference.get().name, arguments, root);
			case TAnonymous(_): "{anonymous}";
			case _: Std.string(type);
		}
	}

	static function named(name:String, arguments:Array<Type>, root:SourceDeclarationIdentity):String {
		return arguments.length == 0 ? name : name + "<" + [for (argument in arguments) describe(argument, root)].join(",") + ">";
	}

	static function identityName(identity:SourceDeclarationIdentity):String {
		return switch (identity) {
			case RecordDeclaration(reference): reference.get().name;
			case AliasDeclaration(reference): reference.get().name;
		}
	}

	static function sameIdentityName(left:SourceDeclarationIdentity, right:SourceDeclarationIdentity):Bool {
		if (identityName(left) != identityName(right)) return false;
		return switch ([left, right]) {
			case [RecordDeclaration(l), RecordDeclaration(r)]: l.get().module == r.get().module;
			case [AliasDeclaration(l), AliasDeclaration(r)]: l.get().module == r.get().module;
			case _: false;
		}
	}

	static function joins(slots:Array<Int>):String {
		return [for (slot in slots) Std.string(slot)].join(",");
	}

	static function classRef(path:String):Ref<ClassType> {
		return switch (Context.getType(path)) {
			case TInst(reference, _): reference;
			case _: throw new haxe.Exception(path + " did not resolve as a class");
		}
	}

	static function classPath(path:String):SourceDeclarationIdentity {
		return RecordDeclaration(classRef(path));
	}

	static function aliasPath(path:String):SourceDeclarationIdentity {
		return switch (Context.getType(path)) {
			case TType(reference, _): AliasDeclaration(reference);
			case _: throw new haxe.Exception(path + " did not resolve as an alias");
		}
	}

	static function ownBinders(path:String):Array<Type> {
		return [for (parameter in classRef(path).get().params) parameter.t];
	}

	static function ownAliasBinders(path:String):Array<Type> {
		return SourceComparisonAnalysis.declarationParameters(aliasPath(path)).map(parameter -> parameter.t);
	}

	static function boxed(argument:Type):Type {
		return switch (Context.getType("admission.AdmissionCases.Box")) {
			case TInst(box, _): TInst(box, [argument]);
			case _: throw new haxe.Exception("Box did not resolve as a class");
		}
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
