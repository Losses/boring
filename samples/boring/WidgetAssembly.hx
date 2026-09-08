package boring;

import boring.WidgetKind.WidgetBuilder;
import boring.WidgetCart.WidgetLens;

class WidgetAssembly {
    public static function build(?b:WidgetBuilder):WidgetBuilder {
        return b == null ? new WidgetBuilder() : b;
    }

    public static function lens(?l:WidgetLens):WidgetLens {
        return l == null ? new WidgetLens() : l;
    }
}
