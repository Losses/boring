package admission.aliasnames.second;

/** The other alias named `Growish`. Its body binds the demanded `Box` slot to
    a mutable array, so it rejects. One short name therefore carries two
    different answers, and the answer follows the declaration identity. */
typedef Growish<T> = Null<admission.AdmissionCases.Box<Array<T>>>;
