package boring;

class Ts2448Ops {
    public static function nestedLocal():Int {
        final value = 1;
        {
            final value = value + 1;
            return value;
        }
    }
}
