package plain;

/**
	Boundary fixture (task t-mun5d99p-op76): an ordinary module with no
	exception types and no runtime references. Used to check whether the
	Runtime.swift emission change drags extra files into plain trees.
**/
class Plain {
	public static function add(a:Int, b:Int):Int {
		return a + b;
	}
}
