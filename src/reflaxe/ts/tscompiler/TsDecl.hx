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
		if(cls.isInterface) {
			final typeAliases: Array<String> = [];
			final members: Array<String> = [];
			for(f in funcFields) {
				final capName = f.field.name.charAt(0).toUpperCase() + f.field.name.substr(1);
				final aliasName = '${cls.name}${capName}Fn';
				final args = [for(a in f.args) '${a.name}: ${types.of(a.type)}'].join(", ");
				final ret = types.of(f.ret);
				typeAliases.push('export type $aliasName = ($args) => $ret;');
				members.push('  readonly ${f.field.name}: $aliasName;');
			}
			final lines: Array<String> = [];
			if(typeAliases.length > 0) {
				for(t in typeAliases) lines.push(t);
				lines.push("");
			}
			lines.push('export interface ${cls.name} {');
			for(m in members) lines.push(m);
			lines.push("}");
			return lines.join("\n");
		}

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

		final tableLines: Array<String> = [];
		for(v in varFields) {
			if(v.isStatic && DataTableHelper.isDataTableField(v.field)) {
				final elems = DataTableHelper.getDataTableElements(v.field.expr());
				if(elems != null) {
					tableLines.push(renderDataTable(v.field.name, elems));
				}
			}
		}

		final lines: Array<String> = [];
		final ifaceStr = cls.interfaces.length > 0 ? " implements " + [for(i in cls.interfaces) i.t.get().name].join(", ") : "";
		lines.push('export class ${cls.name}' + (isException(cls) ? " extends Error" : "") + ifaceStr + " {");

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
		final prefix = tableLines.length > 0 ? tableLines.join("\n\n") + "\n\n" : "";
		return prefix + lines.join("\n");
	}

	function renderDataTable(name: String, elems: Array<Int>): String {
		final formatted = [for(x in elems) (x >= 0 && x <= 9) ? Std.string(x) : "0x" + StringTools.hex(x).toLowerCase()];
		final chunks: Array<String> = [];
		var i = 0;
		while(i < formatted.length) {
			final end = Std.int(Math.min(i + 8, formatted.length));
			chunks.push("  " + formatted.slice(i, end).join(", "));
			i = end;
		}
		return 'const $name = new Int32Array([\n' + chunks.join(",\n") + "\n]);";
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
		final body = expr.functionBody(cls, f);
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
		if(v.isStatic && DataTableHelper.isDataTableField(field)) {
			return [];
		}
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
		final body = decodeBoundaryBody(cls, f);
		final vis = f.field.isPublic ? "public" : "private";
		final stat = f.isStatic ? "static " : "";
		final head = '  $vis ${stat}${f.field.name}($args): $ret {';
		return [head].concat(body).concat(["  }"]);
	}

	/**
		features/18: a function returning ReadOnlyArray is a decode
		boundary; its fill stores and return value are frozen.
	**/
	function decodeBoundaryBody(cls: ClassType, f: ClassFuncData): Array<String> {
		final boundary = switch(f.ret) {
			case TAbstract(a, _):
				final abs = a.get();
				abs.pack.join(".") == "std" && abs.name == "ReadOnlyArray";
			case _: false;
		}
		expr.setDecodeBoundary(boundary);
		final body = expr.functionBody(cls, f);
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
				final interfaceStr = [
					'export interface ${def.name} {',
					fieldLines.join("\n"),
					"}"
				].join("\n");

				if(isStructKeyCandidate(fields)) {
					final cmpLines = [
						'export function compare${def.name}(a: ${def.name}, b: ${def.name}): number {',
						'  if (a === b) return 0;'
					];
					for(f in fields) {
						switch(Context.follow(f.type)) {
							case TAbstract(a, _) if(a.get().name == "Int"):
								cmpLines.push('  if (a.${f.name} !== b.${f.name}) return a.${f.name} - b.${f.name};');
							case TAbstract(a, _) if(a.get().name == "Bool"):
								cmpLines.push('  if (a.${f.name} !== b.${f.name}) return a.${f.name} ? 1 : -1;');
							case TInst(c, _) if(c.get().name == "String"):
								cmpLines.push('  if (a.${f.name} !== b.${f.name}) return a.${f.name} < b.${f.name} ? -1 : 1;');
							case _:
								switch(f.type) {
									case TType(innerDef, _):
										final innerName = innerDef.get().name;
										imports.value(innerDef.get().module, "compare" + innerName);
										cmpLines.push('  const cmp_${f.name} = compare${innerName}(a.${f.name}, b.${f.name});');
										cmpLines.push('  if (cmp_${f.name} !== 0) return cmp_${f.name};');
									case _:
								}
						}
					}
					cmpLines.push('  return 0;');
					cmpLines.push('}');
					return interfaceStr + "\n\n" + cmpLines.join("\n");
				}

				return interfaceStr;
			case _:
				Context.error("typedef alias has no lowering; name the structure instead", def.pos);
				return null;
		}
	}

	function isStructKeyCandidate(fields: Array<ClassField>): Bool {
		for(f in fields) {
			if(!isFieldKeyCandidate(f.type)) return false;
		}
		return true;
	}

	function isFieldKeyCandidate(t: Type): Bool {
		return switch(t) {
			case TAbstract(a, _):
				final n = a.get().name;
				n == "Int" || n == "Bool";
			case TInst(c, _):
				c.get().name == "String";
			case TType(d, _):
				switch(d.get().type) {
					case TAnonymous(anon):
						isStructKeyCandidate(anon.get().fields);
					case _: false;
				}
			case TLazy(fn):
				isFieldKeyCandidate(fn());
			case _: false;
		};
	}
}
#end
