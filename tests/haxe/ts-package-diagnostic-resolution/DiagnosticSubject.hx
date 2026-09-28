package;

import DiagnosticPeer;

class DiagnosticSubject {
	public static function emit(value:String):Void {}

	public static function run():Void {
		emit("same");
		emit("same");
	}

	public static function main():Void {
		run();
		DiagnosticPeer.touch();
	}
}
