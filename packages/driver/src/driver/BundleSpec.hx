package driver;

typedef BundleSpec = {
    id:String,
    target:String,
    precision:String,
    haxeArgs:Array<String>,
    rootsFile:String,
    sourceSet:String,
    build:StepOverride,
    run:StepOverride,
    packageName:String,
    packageVersion:String,
    packageLicense:String,
    hasTests:Bool,
    hasComparison:Bool,
    afterGen:Null<CommandStep>
};
