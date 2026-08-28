package reflaxe.unicode;

/**
    Renders the generated grapheme break table into each target's runtime
    syntax. The table itself is generated data (GraphemeBreakData); this
    class only formats it, so regenerating the data never touches code.
**/
class GraphemeTableRender {
	public static function ts(table: Array<Int>): String {
		return "export const GRAPHEME_TABLE = new Int32Array([\n" + wrap(table, "    ") + "\n]);\n";
	}

	public static function rust(table: Array<Int>): String {
		return "static GRAPHEME_TABLE: [u32; " + table.length + "] = [\n" + wrap(table, "    ") + "\n];\n";
	}

	public static function kotlin(table: Array<Int>): String {
		return "private val GRAPHEME_TABLE: IntArray = intArrayOf(\n" + wrap(table, "    ") + "\n)\n";
	}

	static function wrap(table: Array<Int>, indent: String): String {
		final lines: Array<String> = [];
		var current: Array<String> = [];
		for(i in 0...table.length) {
			if(current.length == 15) {
				lines.push(indent + current.join(", "));
				current = [];
			}
			current.push(Std.string(table[i]));
		}
		if(current.length > 0) {
			lines.push(indent + current.join(", "));
		}
		return lines.join(",\n");
	}
}
