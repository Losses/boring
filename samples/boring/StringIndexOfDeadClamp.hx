package boring;

/**
 * R1 regression sample (StringIndexOfDeadClamp): the start-offset clamp
 * of the indexOf lowering exists for a negative runtime offset; a
 * constant non-negative start never takes it, so the dead guard must
 * not render.
 **/
class StringIndexOfDeadClamp {
	public static function find(text:String):Int {
		return text.indexOf("x", 2);
	}
}
