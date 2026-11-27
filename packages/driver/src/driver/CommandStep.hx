package driver;

class CommandStep {
    public final command:String;
    public final args:Array<String>;
    public final env:Array<EnvVar>;

    public function new(command:String, args:Array<String>, env:Array<EnvVar>) {
        this.command = command;
        this.args = args;
        this.env = env;
    }
}
