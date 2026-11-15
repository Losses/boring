package driver;

enum DriverFault {
    InvalidConfig(message:String);
    Unsupported(message:String);
}
