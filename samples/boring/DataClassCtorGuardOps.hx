/** Regression sample for data-class constructor field reads. */

package boring;

@:dataClass
class DataClassCtorGuardOps {
    public final magnitude:Float;

    public function new(magnitude:Float) {
        this.magnitude = magnitude;
        if (!Math.isFinite(this.magnitude) || this.magnitude < 0.0) {
            throw new ValueException(NegativeStart);
        }
    }
}
