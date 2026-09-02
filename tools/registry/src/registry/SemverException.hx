package registry;

/** The only exception the semver parser throws, in its own module so
the exceptionPayloads scan of the Kotlin backend sees this module as
the exception's home (co-locating it with other classes would rewrite
their single-argument constructors into exception variants). */
class SemverException extends haxe.Exception {
	public final error:SemverFault;

	public function new(fault:SemverFault) {
		this.error = fault;
		super(SemverException.describe(fault));
	}

	public static function describe(fault:SemverFault):String {
		return switch (fault) {
			case InvalidCore(version): "invalid version core: "+version;
			case InvalidExtension(version): "invalid prerelease or build metadata: "+version;
		};
	}
}
