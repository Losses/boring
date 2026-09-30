package xsxm;

/** Payload enum of E1, deliberately declared in a DIFFERENT module than the
    exception class that carries it.  Both payload enums therefore get their
    own `payloadEnumNames` key, while `exceptionPayloads` (keyed by the
    exception CLASS module) still collides between E1 and E2. */
enum F1Fault {
	One(t:String);
}
