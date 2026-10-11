package driver;

/** A step failure the caller may catch instead of terminating. */
class BundleStepFailure {
    public var bundleId(default, null):String;
    public var action(default, null):String;
    public var stepName(default, null):String;
    public var command(default, null):String;
    public var args(default, null):Array<String>;
    public var output(default, null):String;
    public var code(default, null):Int;

    public function new(bundleId:String, action:String, stepName:String, command:String, args:Array<String>, output:String, code:Int) {
        this.bundleId = bundleId;
        this.action = action;
        this.stepName = stepName;
        this.command = command;
        this.args = args;
        this.output = output;
        this.code = code;
    }
}
