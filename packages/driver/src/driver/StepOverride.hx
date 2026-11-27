package driver;

class StepOverride {
    public final args:Array<String>;
    public final env:Array<EnvVar>;
    public final cargoArgs:Null<Array<String>>;

    public function new(args:Array<String>, env:Array<EnvVar>, ?cargoArgs:Null<Array<String>>) {
        this.args = args;
        this.env = env;
        this.cargoArgs = cargoArgs;
    }
}
