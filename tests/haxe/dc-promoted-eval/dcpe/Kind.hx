package dcpe;

/**
    The enum switched over by both probe classes. Three constructs, one with a
    payload, so the arm bindings of every target exercise the payload-capture
    path. No `default` arm: the switch must stay exhaustive, because the
    promotion under observation only happens for an exhaustive enum switch.
**/
enum Kind {
	A;
	B(value:Int);
	C;
}
