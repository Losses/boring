package tests;

import boring.InterfaceGetterProperty;
import boring.InterfaceGetterProperty.InterfaceGetterPropertyImpl;
import boring.InterfaceGetterProperty.InterfaceGetterPropertyUse;
import std.Test;

class InterfaceGetterPropertyTests {
    @:test("reads a getter-only property through the interface type")
    public static function testInterfaceGetterProperty():Void {
        final iface:InterfaceGetterProperty = new InterfaceGetterPropertyImpl("hello");
        final actual:String = iface.name;
        Test.equals("hello", actual);
        Test.equals("hello", InterfaceGetterPropertyUse.nameOf(iface));
    }
}
