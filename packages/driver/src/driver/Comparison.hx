package driver;

/**
    A declared target-only module: the test ids of `module` may legitimately
    appear in the results of the bundles listed in `bundles` while the
    baseline does not carry them. The entry is derived from the `@only-in`
    marker in the bundle's roots file, never from a per-id list.
**/
typedef ExtraEntry = { module:String, reason:String, bundles:Array<String> };

typedef Comparison = { lines:Array<String>, errors:Array<String>, allIds:Array<String>, declaredExtras:Array<String> };
