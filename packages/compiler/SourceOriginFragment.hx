#if (macro || reflaxe_runtime)
package;

typedef SourceOccurrenceId = String;

typedef SourceOrigin = {
	final occurrenceId:SourceOccurrenceId;
	final sourceFile:String;
	final sourceStart:Int;
	final sourceEnd:Int;
}

typedef SourceOriginSpan = {
	final start:Int;
	final end:Int;
	final origin:Null<SourceOrigin>;
	final unmappedReason:Null<String>;
}

/** Text and relative origin ranges composed without inspecting rendered text. */
class SourceOriginFragment {
	public final text:String;
	final spanEntries:Array<SourceOriginSpan>;
	public var spans(get, never):Array<SourceOriginSpan>;

	public function new(text:String, spans:Array<SourceOriginSpan> = null) {
		this.text = text;
		this.spanEntries = spans == null ? [] : spans.copy();
	}

	function get_spans():Array<SourceOriginSpan> {
		return spanEntries.copy();
	}

	public static function plain(text:String):SourceOriginFragment {
		return new SourceOriginFragment(text);
	}

	public static function utf16Length(text:String):Int {
		var length = 0;
		for (codePoint in new haxe.iterators.StringIteratorUnicode(text))
			length += codePoint > 0xFFFF ? 2 : 1;
		return length;
	}

	public static function unmapped(text:String, reason:String):SourceOriginFragment {
		return text.length == 0 ? plain(text) : new SourceOriginFragment(text, [{
			start: 0,
			end: utf16Length(text),
			origin: null,
			unmappedReason: reason
		}]);
	}

	public static function join(fragments:Array<SourceOriginFragment>, separator:String):SourceOriginFragment {
		final textParts:Array<String> = [];
		final spans:Array<SourceOriginSpan> = [];
		var offset = 0;
		for (i in 0...fragments.length) {
			if (i > 0) {
				textParts.push(separator);
				offset += utf16Length(separator);
			}
			final fragment = fragments[i];
			textParts.push(fragment.text);
			for (span in fragment.spans) {
				spans.push({
					start: offset + span.start,
					end: offset + span.end,
					origin: span.origin,
					unmappedReason: span.unmappedReason
				});
			}
			offset += utf16Length(fragment.text);
		}
		return new SourceOriginFragment(textParts.join(""), spans);
	}

	public function prefixed(prefix:SourceOriginFragment):SourceOriginFragment {
		return join([prefix, this], "");
	}

	public function suffixed(suffix:SourceOriginFragment):SourceOriginFragment {
		return join([this, suffix], "");
	}
}
#end
