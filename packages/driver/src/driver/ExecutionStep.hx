package driver;

typedef ExecutionStep = {
    name:String,
    command:String,
    args:Array<String>,
    cwd:String,
    env:Array<EnvVar>
};
