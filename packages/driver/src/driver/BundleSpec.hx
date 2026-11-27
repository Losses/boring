package driver;

class BundleSpec {
    public final id:String;
    public final target:String;
    public final precision:String;
    public final haxeArgs:Array<String>;
    public final rootsFile:String;
    public final sourceSet:String;
    public final build:StepOverride;
    public final run:StepOverride;
    public final packageName:String;
    public final packageVersion:String;
    public final packageLicense:String;
    public final packageNpmName:String;
    public final packageCargoName:String;
    public final packagePubName:String;
    public final packageMavenName:String;
    public final packageSwiftUrl:String;
    public final packageSwiftPath:String;
    public final packageMavenGroup:String;
    public final dependencyMode:String;
    public final dependencyPaths:Array<DependencyPath>;
    public final hasTests:Bool;
    public final hasComparison:Bool;
    public final afterGen:Null<CommandStep>;
    public final mavenPublication:Null<CommandStep>;
    public final kmpPublication:Bool;
    public final dependsOn:Array<String>;

    public function new(id:String, target:String, precision:String, haxeArgs:Array<String>, rootsFile:String,
        sourceSet:String, build:StepOverride, run:StepOverride, packageName:String, packageVersion:String,
        packageLicense:String, packageNpmName:String, packageCargoName:String, packagePubName:String,
        packageMavenName:String, packageSwiftUrl:String, packageSwiftPath:String, packageMavenGroup:String,
        dependencyMode:String, dependencyPaths:Array<DependencyPath>, hasTests:Bool, hasComparison:Bool,
        afterGen:Null<CommandStep>, mavenPublication:Null<CommandStep>, kmpPublication:Bool, dependsOn:Array<String>) {
        this.id = id;
        this.target = target;
        this.precision = precision;
        this.haxeArgs = haxeArgs;
        this.rootsFile = rootsFile;
        this.sourceSet = sourceSet;
        this.build = build;
        this.run = run;
        this.packageName = packageName;
        this.packageVersion = packageVersion;
        this.packageLicense = packageLicense;
        this.packageNpmName = packageNpmName;
        this.packageCargoName = packageCargoName;
        this.packagePubName = packagePubName;
        this.packageMavenName = packageMavenName;
        this.packageSwiftUrl = packageSwiftUrl;
        this.packageSwiftPath = packageSwiftPath;
        this.packageMavenGroup = packageMavenGroup;
        this.dependencyMode = dependencyMode;
        this.dependencyPaths = dependencyPaths;
        this.hasTests = hasTests;
        this.hasComparison = hasComparison;
        this.afterGen = afterGen;
        this.mavenPublication = mavenPublication;
        this.kmpPublication = kmpPublication;
        this.dependsOn = dependsOn;
    }
}
