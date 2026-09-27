package driver;

typedef Bundle = {
    id:String,
    target:String,
    precision:String,
    haxeArgs:Array<String>,
    rootsFile:String,
    build:StepOverride,
    run:StepOverride,
    packageName:String,
    packageVersion:String,
    packageLicense:String,
    hasTests:Bool,
    hasComparison:Bool,
    afterGen:Null<CommandStep>
};
