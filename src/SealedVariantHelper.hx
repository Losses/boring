#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Type;

/** Shared metadata rules for sealed variant interfaces (feature spec 32). */
class SealedVariantHelper {
	public static inline final INVALID_TARGET = "@:sealed applies to interfaces only";

	public static function validateClass(cls: ClassType): Void {
		if(cls.meta.has(":sealed") && !cls.isInterface) {
			Context.error(INVALID_TARGET, cls.pos);
		}
	}

	public static function validateEnum(en: EnumType): Void {
		if(en.meta.has(":sealed")) {
			Context.error(INVALID_TARGET, en.pos);
		}
	}

	public static function validateTypedef(def: DefType): Void {
		if(def.meta.has(":sealed")) {
			Context.error(INVALID_TARGET, def.pos);
		}
	}

	public static function isSealedInterface(cls: ClassType): Bool {
		return cls.isInterface && cls.meta.has(":sealed");
	}
}
#end
