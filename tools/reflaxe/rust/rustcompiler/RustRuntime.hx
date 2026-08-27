package rustcompiler;

#if (macro || reflaxe_runtime)
/**
	Headerless runtime shim sources for the standard library, emitted on
	demand under the configured runtime package.
**/
class RustRuntime {
	public static final BYTES_BUFFER_SOURCE = '
pub struct BytesBuffer {
    bytes: Vec<u8>,
}

impl BytesBuffer {
    pub fn new() -> Self {
        Self { bytes: Vec::new() }
    }

    pub fn add_byte(&mut self, byte: u8) {
        self.bytes.push(byte);
    }

    pub fn get_bytes(&self) -> Vec<u8> {
        self.bytes.clone()
    }
}
';

	public static final FP_HELPER_SOURCE = '
pub struct FPHelper;

pub struct Int64Halves {
    pub high: u32,
    pub low: u32,
}

impl FPHelper {
    pub fn i64_to_double(low: u32, high: u32) -> f64 {
        let h = high.to_be_bytes();
        let l = low.to_be_bytes();
        let bits = u64::from_be_bytes([h[0], h[1], h[2], h[3], l[0], l[1], l[2], l[3]]);
        f64::from_bits(bits)
    }

    pub fn double_to_i64(v: f64) -> Int64Halves {
        let bytes = v.to_bits().to_be_bytes();
        let high = u32::from_be_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]);
        let low = u32::from_be_bytes([bytes[4], bytes[5], bytes[6], bytes[7]]);
        Int64Halves { high, low }
    }
}
';

	public static final CONSOLE_SOURCE = '
pub struct Console;

impl Console {
    pub fn log(message: &str) {
        println!("{message}");
    }
}
';

	public static final PROCESS_SOURCE = '
pub struct Process;

impl Process {
    pub fn exit(code: i32) -> ! {
        std::process::exit(code);
    }
}
';
}
#end
