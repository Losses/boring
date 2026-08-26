// expect: V05 DynamicValue
class Case {
	static function main():Void {
		final holder:Dynamic = { name: "a" };
		holder.name;
	}
}
