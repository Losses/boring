package tprobe;

import std.FsError;
import std.FsException;

/**
    Ordinary helper (P6.4 touch pattern).  The parameter type FsException
    adds the exception subclass to mtypes so preScan registers its FsError
    payload enum as a declaration site.  Without an explicit FsException type
    reference, an in-scope compilation has no declaration site for the payload
    enum and the fallible readText() call faults as out-of-scope.
**/
class FsErrorTouch {
    public static function touch(error:FsException):FsError {
        return error.error;
    }
}
