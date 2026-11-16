package pub;

import pub.ExtensionHolders.ExtensionHoldersExtra;

/** Reads both holder classes' marked functions as plain static calls. */
class ExtensionHoldersConsumer {
    public static function describe(mode:HolderMode):String {
        return ExtensionHoldersExtra.modePrefix(mode, "p:") + "/" + ExtensionHolders.modeSuffix(mode, "!");
    }
}
