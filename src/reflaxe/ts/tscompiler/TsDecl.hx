package tscompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Type;
import reflaxe.data.ClassFuncData;
import reflaxe.data.ClassVarData;
import reflaxe.data.EnumOptionData;

/**
	Declaration lowering: classes, variant enums, and record typedefs
	(features/14). One TsDecl instance owns the per-module emission
	context (imports, types, expression state) so every declaration in
	the same Haxe module lands in one TypeScript file with one import
	block.
**/
class TsDecl {
	final imports: TsImports;
	final types: TsType;
	final expr: TsExpr;

	public function new(selfModule: String) {
		this.imports = new TsImports(selfModule);
		this.types = new TsType(imports);
		this.expr = new TsExpr(imports, types);
	}

	public function renderImports(): String {
		return imports.render();
	}

	public function renderTestImports(testOutputDir: String, mainOutputDir: String, testRunner: String): String {
		return imports.renderTestImports(testOutputDir, mainOutputDir, testRunner);
	}

	/** Whether this module references any runtime-package symbol. */
	public function usesRuntime(): Bool {
		return imports.usesRuntime();
	}

	public function topLevelStatements(e: TypedExpr): String {
		return expr.topLevelStatements(e);
	}

	public function rawExpression(e: TypedExpr): String {
		return expr.rawExpression(e);
	}

	// ------------------------------------------------------------------
	// Classes
	// ------------------------------------------------------------------

	public function classDecl(cls: ClassType, varFields: Array<ClassVarData>, funcFields: Array<ClassFuncData>): String {
		if(cls.superClass != null) {
			final parent = cls.superClass.t.get();
			final parentPath = parent.pack.length == 0 ? parent.name : parent.pack.join(".") + "." + parent.name;
			if(parentPath == "haxe.Exception") {
				// haxe.Exception lowers to the platform Error class; the
				// name property is stamped by the constructor emitter.
			} else {
				Context.error("super class has no TypeScript lowering in the subset: " + parentPath, cls.pos);
			}
		}

		final lines: Array<String> = [];
		lines.push('export class ${cls.name}' + (isException(cls) ? " extends Error" : "") + " {");

		for(v in varFields) {
			for(l in varDecl(v)) lines.push(l);
		}

		var sep = varFields.length > 0 && funcFields.length > 0;
		for(f in funcFields) {
			if(sep) {
				lines.push("");
			}
			sep = true;
			for(l in funcDecl(cls, f)) lines.push(l);
		}

		lines.push("}");
		return lines.join("\n");
	}

	public function testFuncDecl(cls: ClassType, f: ClassFuncData, testRunner: String): String {
		final id = cls.module + "." + f.field.name;
		var desc: Null<String> = null;
		for(entry in f.field.meta.extract(":test")) {
			if(entry.params != null && entry.params.length > 0) {
				switch(entry.params[0].expr) {
					case EConst(CString(s)): desc = s;
					case _:
				}
			}
		}
		final runnerName = desc != null ? id + ": " + desc : id;
		imports.runtime("Test");
		final body = expr.functionBody(f);
		final indented = [for(b in body) "    " + b].join("\n");
		if(testRunner == "deno") {
			return 'Deno.test("${escapeString(runnerName)}", () =>\n  Test.run("${id}", "${escapeString(runnerName)}", () => {\n$indented\n  }));';
		} else {
			return 'test("${escapeString(runnerName)}", () =>\n  Test.run("${id}", "${escapeString(runnerName)}", () => {\n$indented\n  }));';
		}
	}

	static function escapeString(s: String): String {
		var out = new StringBuf();
		for(i in 0...s.length) {
			var c = s.charAt(i);
			if(c == '"') out.add('\\"');
			else if(c == '\\') out.add('\\\\');
			else if(c == '\n') out.add('\\n');
			else if(c == '\r') out.add('\\r');
			else if(c == '\t') out.add('\\t');
			else out.add(c);
		}
		return out.toString();
	}

	function isException(cls: ClassType): Bool {
		if(cls.superClass == null) {
			return false;
		}
		final parent = cls.superClass.t.get();
		return parent.pack.join(".") == "haxe" && parent.name == "Exception";
	}

	function varDecl(v: ClassVarData): Array<String> {
		final field = v.field;
		if(field.meta.has(":value")) {
			if(v.isStatic) {
				// Inline constants fold into their use sites as TConst.
				return [];
			}
			Context.error("instance field default has no lowering; assign it in the constructor", field.pos);
		}
		if(v.isStatic) {
			Context.error("mutable static field has no lowering in the subset", field.pos);
		}
		final vis = field.isPublic ? "public" : "private";
		final ro = field.isFinal ? "readonly " : "";
		return ['  $vis ${ro}${field.name}: ${types.of(field.type)};'];
	}

	function funcDecl(cls: ClassType, f: ClassFuncData): Array<String> {
		final args = [for(a in f.args) '${a.name}: ${types.of(a.type)}'].join(", ");
		// Haxe types constructors as FMethod(MethNormal) with field name
		// "new"; the name is the constructor marker.
		if(f.field.name == "new") {
			for(a in f.args) {
				expr.reserveName(a.name);
			}
			final body = expr.constructorBody(cls.name, f, isException(cls));
			return ['  constructor($args) {'].concat(body).concat(["  }"]);
		}
		for(a in f.args) {
			expr.reserveName(a.name);
		}
		final ret = types.of(f.ret);
		final body = decodeBoundaryBody(f);
		final vis = f.field.isPublic ? "public" : "private";
		final stat = f.isStatic ? "static " : "";
		final head = '  $vis ${stat}${f.field.name}($args): $ret {';
		return [head].concat(body).concat(["  }"]);
	}

	/**
		features/18: a function returning ReadOnlyArray is a decode
		boundary; its fill stores and return value are frozen.
	**/
	function decodeBoundaryBody(f: ClassFuncData): Array<String> {
		final boundary = switch(f.ret) {
			case TAbstract(a, _):
				final abs = a.get();
				abs.pack.join(".") == "std" && abs.name == "ReadOnlyArray";
			case _: false;
		}
		expr.setDecodeBoundary(boundary);
		final body = expr.functionBody(f);
		expr.setDecodeBoundary(false);
		return body;
	}

	// ------------------------------------------------------------------
	// Variant enums (stdlib/03)
	// ------------------------------------------------------------------

	public function enumDecl(en: EnumType, options: Array<EnumOptionData>): String {
		final sorted = options.copy();
		sorted.sort((a, b) -> Reflect.compare(a.field.index, b.field.index));
		// Each variant is a named interface (the no-inline-types rule bans
		// object literals inside unions); the enum is the union of names.
		final blocks: Array<String> = [];
		final names: Array<String> = [];
		for(o in sorted) {
			names.push(o.name);
			final members = ['  readonly kind: "${o.name}"'];
			for(arg in o.args) {
				members.push('  readonly ${arg.name}: ${types.of(arg.type)}');
			}
			blocks.push('export interface ${o.name} {\n' + members.join("\n") + "\n}");
		}
		blocks.push('export type ${en.name} =\n  | ' + names.join("\n  | ") + ";");
		return blocks.join("\n\n");
	}

	// ------------------------------------------------------------------
	// Record typedefs (features/14, features/18)
	// ------------------------------------------------------------------

	public function typedefDecl(def: DefType): String {
		switch(def.type) {
			case TAnonymous(anonRef):
				final fields = anonRef.get().fields.copy();
				fields.sort((a, b) -> Reflect.compare(Context.getPosInfos(a.pos).min, Context.getPosInfos(b.pos).min));
				final fieldLines = [for(field in fields) '  readonly ${field.name}: ${types.of(field.type)};'];
				return [
					'export interface ${def.name} {',
					fieldLines.join("\n"),
					"}"
				].join("\n");
			case _:
				Context.error("typedef alias has no lowering; name the structure instead", def.pos);
				return null;
		}
	}
}
#end
