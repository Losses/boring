package boring;

/**
 * A printed class record with scalar fields and a nested record field
 * (docs/specs/features/31-record-tostring-member.md).
 */
@:dataClass
class PrintedRecord {
	public final count:Int;
	public final ratio:Float;
	public final inner:PrintedRecord.PrintedInner;
	public final note:Null<PrintedRecord.PrintedInner>;

	public function new(count:Int, ratio:Float, inner:PrintedRecord.PrintedInner, note:Null<PrintedRecord.PrintedInner>) {
		this.count = count;
		this.ratio = ratio;
		this.inner = inner;
		this.note = note;
	}
}

@:dataClass
class PrintedInner {
	public final name:String;

	public function new(name:String) {
		this.name = name;
	}
}
