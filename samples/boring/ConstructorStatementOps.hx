/** Constructor statement parity probes for feature spec 39. */

package boring;

using std.Functional;

class ConstructorStatementOps {
    public var filled:Array<Int>;
    public var mapped:Array<Int>;

    public function new(count:Int, values:Array<Int>) {
        this.filled = [for (_ in 0...count + 1) 0];
        final mapped = values.map(function(value:Int):Int {
            final incremented = value + 1;
            return incremented;
        });
        this.mapped = mapped;
    }
}
