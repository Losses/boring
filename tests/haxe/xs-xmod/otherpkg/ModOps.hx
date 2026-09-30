package otherpkg;

class ModOps {
	public static function fail(tag:String):Int {
		throw new ModEx(ModFault.ModOne(tag));
	}
}
