package registry;

/** The type of the process environment object. No field of it is read
directly: an absent environment entry appears as `undefined` on the
JavaScript side, which no typed extern can carry across boring's
null-only optionality, so the whole object crosses as JSON text. */
extern class EnvBlock {}

@:native("JSON") extern class JsonGlobal {
	static function stringify(v:EnvBlock):String;
}

@:native("process") extern class EnvProcess {
	@:native("env") static var env:EnvBlock;
}

/** Environment lookup (spec 26: environment variable lookup through
typed externs). The JSON text of the environment object is parsed with
the tool's own Json module, so an absent entry becomes null inside pure
Haxe. */
class Environment {
	public static function githubToken():Null<String> {
		final text = JsonGlobal.stringify(EnvProcess.env);
		return tokenValue(registry.Json.read(text));
	}

	static function tokenValue(v:registry.Json.JsonValue):Null<String> {
		return switch(v) {
			case JObject(fields): tokenOf(fields);
			case JArray(values): null;
			case JString(value): null;
			case JNumber(value): null;
			case JBool(value): null;
			case JNull: null;
		};
	}

	static function tokenOf(fields:Array<registry.Json.JsonField>):Null<String> {
		for(i in 0...fields.length) {
			if(fields[i].name == "GITHUB_TOKEN") {
				return tokenText(fields[i].value);
			}
		}
		return null;
	}

	static function tokenText(v:registry.Json.JsonValue):Null<String> {
		return switch(v) {
			case JObject(objectFields): null;
			case JArray(values): null;
			case JString(value): value;
			case JNumber(value): null;
			case JBool(value): null;
			case JNull: null;
		};
	}
}
