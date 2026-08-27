#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import sys.io.File;

/**
 * Macro entry for compile-time data tables per docs/specs/features/20-compile-time-data-tables.md.
 * Reads sorted range data files and expands them into a constant Array<Int> field.
 */
class DataTables {
	macro public static function rangesField(path:String, fieldName:String):Array<Field> {
		final fields = Context.getBuildFields();
		final pos = Context.currentPos();

		if (!sys.FileSystem.exists(path)) {
			Context.fatalError('Data file not found: $path', pos);
		}

		final content = try {
			File.getContent(path);
		} catch (e:Dynamic) {
			Context.fatalError('Failed to read data file $path: $e', pos);
		}

		final rawLines = content.split("\n");
		var layout:Null<Int> = null; // 2 for pair, 3 for triple
		var prevEnd:Null<Int> = null;
		final values:Array<Int> = [];
		var dataLineCount = 0;

		for (i in 0...rawLines.length) {
			final lineNum = i + 1;
			var line = rawLines[i];

			// Strip comments starting with '#'
			final commentIdx = line.indexOf("#");
			if (commentIdx >= 0) {
				line = line.substr(0, commentIdx);
			}
			line = StringTools.trim(line);
			if (line.length == 0) {
				continue;
			}

			// Split by whitespace
			final parts = line.split(" ").filter(p -> p.length > 0);
			if (parts.length == 0) {
				continue;
			}

			if (layout == null) {
				if (parts.length != 2 && parts.length != 3) {
					Context.fatalError('$path:$lineNum: first data line must have 2 (pair) or 3 (triple) fields, got ${parts.length}', pos);
				}
				layout = parts.length;
			} else if (parts.length != layout) {
				Context.fatalError('$path:$lineNum: line has ${parts.length} fields, expected $layout for this file layout', pos);
			}

			dataLineCount++;

			final parsedValues:Array<Int> = [];
			for (part in parts) {
				final val = parseHexInt(part, path, lineNum, pos);
				parsedValues.push(val);
			}

			final start = parsedValues[0];
			final end = parsedValues[1];

			if (start > end) {
				Context.fatalError('$path:$lineNum: record START ($start) exceeds END ($end)', pos);
			}

			if (prevEnd != null && start <= prevEnd) {
				Context.fatalError('$path:$lineNum: record START ($start) must be strictly greater than previous END ($prevEnd)', pos);
			}

			prevEnd = end;

			for (val in parsedValues) {
				values.push(val);
			}
		}

		if (dataLineCount == 0) {
			Context.fatalError('$path: data file is empty', pos);
		}

		final exprs:Array<Expr> = [for (v in values) { expr: EConst(CInt(Std.string(v))), pos: pos }];
		final arrayExpr:Expr = { expr: EArrayDecl(exprs), pos: pos };

		fields.push({
			name: fieldName,
			doc: null,
			meta: [],
			access: [APublic, AStatic, AFinal],
			kind: FVar(macro : Array<Int>, arrayExpr),
			pos: pos
		});

		return fields;
	}

	static function parseHexInt(token:String, file:String, lineNum:Int, pos:Position):Int {
		var s = StringTools.trim(token);
		var isNegative = false;
		if (StringTools.startsWith(s, "-")) {
			isNegative = true;
			s = s.substr(1);
		}
		if (StringTools.startsWith(s, "0x") || StringTools.startsWith(s, "0X")) {
			s = s.substr(2);
		}
		if (s.length == 0) {
			Context.fatalError('$file:$lineNum: invalid integer value "$token"', pos);
		}

		for (i in 0...s.length) {
			final c = s.charCodeAt(i);
			final isHex = (c >= "0".code && c <= "9".code)
				|| (c >= "a".code && c <= "f".code)
				|| (c >= "A".code && c <= "F".code);
			if (!isHex) {
				Context.fatalError('$file:$lineNum: invalid hexadecimal character in "$token"', pos);
			}
		}

		// Parse hex value
		var val:Float = 0;
		for (i in 0...s.length) {
			final c = s.charCodeAt(i);
			var digit = 0;
			if (c >= "0".code && c <= "9".code) digit = c - "0".code;
			else if (c >= "a".code && c <= "f".code) digit = c - "a".code + 10;
			else if (c >= "A".code && c <= "F".code) digit = c - "A".code + 10;
			val = val * 16 + digit;
		}

		if (isNegative) {
			val = -val;
		}

		// Validate 32-bit signed Int range: [-2147483648, 2147483647]
		if (val < -2147483648.0 || val > 2147483647.0) {
			Context.fatalError('$file:$lineNum: value "$token" is outside signed 32-bit Int range', pos);
		}

		return Std.int(val);
	}
}
#end
