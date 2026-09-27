package driver;

typedef Project = {
    path:String,
    root:String,
    outRoot:String,
    resultsDir:String,
    baseline:String,
    sourceRoots:Array<String>,
    rootsFile:String,
    haxeArgs:Array<String>,
    bundles:Array<Bundle>
};
