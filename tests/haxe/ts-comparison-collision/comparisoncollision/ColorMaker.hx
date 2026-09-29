package comparisoncollision;

/**
    Field-less class. Two static methods declare return types of the two
    same-named Color enums from different modules, so the method
    signatures alone import one short name twice and the generated file
    must bind both under module identity aliases. The signature collision
    has to resolve before any body text is emitted, because the return
    types are the first references the emitters render.
**/
class ColorMaker {
    public static function firstColor():comparisoncollision.first.Color
        return comparisoncollision.first.Color.Crimson(1);

    public static function secondColor():comparisoncollision.second.Color
        return comparisoncollision.second.Color.Navy(2);
}
