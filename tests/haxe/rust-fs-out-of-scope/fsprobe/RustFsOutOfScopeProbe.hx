package fsprobe;

import std.Fs;
import std.FsError;
import std.FsException;

/**
    Probe for the out-of-scope FsError domain diagnostic (P6.4).

    read() calls std.Fs.readText uncaught, so its error slot resolves
    through ErrorDomainRegistry. When samples/std is outside Intercept
    scope the std.FsError payload enum has no declaration site and
    generation must fail with "std.FsError domain is not emitted in this
    compilation scope".

    touch() references std.FsException (and through it the std.FsError
    payload enum) purely to pull both into the in-scope compilation.
    The parameter type FsException adds the exception subclass to mtypes so
    preScan registers its payload enum as a declaration site.  The field
    read error.error lowers to the payload value itself
    (RustExpr.catchPayloadAccess), so touch needs no static method call on
    the exception class (a static call would lower to ClassName::method
    while the class struct is intentionally not emitted).
**/
class RustFsOutOfScopeProbe {
    public static function read(path:String):String {
        return Fs.readText(path);
    }

    public static function touch(error:FsException):FsError {
        return error.error;
    }
}
