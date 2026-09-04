// expect: V15 EnumDefaultArm
import boring.Console;

enum Color {
    Red;
    Green;
    Blue;
}

class Case {
    static function pick():Color {
        return Green;
    }

    static function main():Void {
        final color = pick();
        final code = switch (color) {
            case Red: 1;
            case Green: 2;
            default: 3;
        };
        Console.log(Std.string(code));
    }
}
