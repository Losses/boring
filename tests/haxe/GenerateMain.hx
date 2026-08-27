// Entry for the generation step of the stage one haxe runner. The runner
// main under out/haxe/TestMain.hx is produced by TestCollector before the
// compile resolves -main TestMain, because classpath listings are cached
// before macro callbacks run and a first run on a fresh tree would fail.
class GenerateMain {
	static function main():Void {}
}
