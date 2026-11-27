package driver;

class Project {
    public final path:String;
    public final root:String;
    public final outRoot:String;
    public final resultsDir:String;
    public final baseline:String;
    public final sourceRoots:Array<String>;
    public final sourceSets:Array<SourceSet>;
    public final rootsFile:String;
    public final haxeArgs:Array<String>;
    public final bundles:Array<BundleSpec>;

    public function new(path:String, root:String, outRoot:String, resultsDir:String, baseline:String,
        sourceRoots:Array<String>, sourceSets:Array<SourceSet>, rootsFile:String,
        haxeArgs:Array<String>, bundles:Array<BundleSpec>) {
        this.path = path;
        this.root = root;
        this.outRoot = outRoot;
        this.resultsDir = resultsDir;
        this.baseline = baseline;
        this.sourceRoots = sourceRoots;
        this.sourceSets = sourceSets;
        this.rootsFile = rootsFile;
        this.haxeArgs = haxeArgs;
        this.bundles = bundles;
    }
}
