package boring;

/**
    A sub-type abstract over a String whose static constructor is not
    inline. The Kotlin target routes the `FontId.of` call to the synthetic
    `FontId_Impl_` companion, which must be emitted even though no inline
    member forces it into the module (features/49: Impl_ emission for
    sub-type abstracts).
**/
abstract FontId(String) from String to String {
    public static function of(face:String):FontId {
        return "font:" + face;
    }
}
