package boring;

class AbstractStaticDefault {
    public final value:ProbeUnit;

    public function new(?v:ProbeUnit) {
        this.value = v == null ? ProbeUnit.ZERO : v;
    }
}
