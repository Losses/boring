package flow.stable;

/**
    Runtime dependency of the emitted test host: the host shim formats floats
    through FPHelper, so the group declares one use and the generation emits
    the module the shim names. This module takes no part in the flow cases; it
    keeps the emitted tree complete, because a group whose input names no
    FPHelper use leaves the host shim with an unresolved runtime reference.
**/
class HostBits {
    public static function unitFloatIsOne():Bool {
        return haxe.io.FPHelper.i32ToFloat(1065353216) == 1.0;
    }
}
