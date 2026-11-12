#[cfg(feature = "f32")]
pub type TiqianFloat = f32;
#[cfg(not(feature = "f32"))]
pub type TiqianFloat = f64;
#[cfg(feature = "f32")]
pub type TiqianBits = u32;
#[cfg(not(feature = "f32"))]
pub type TiqianBits = u64;
#[cfg(feature = "f32")]
pub const TIQIAN_NAN_BITS: u32 = 0x7fc00000;
#[cfg(not(feature = "f32"))]
pub const TIQIAN_NAN_BITS: u64 = 0x7ff8000000000000;
pub const TIQIAN_ZERO_BITS: TiqianBits = 0;

pub mod registry;
pub mod std;
pub mod runtime;

pub use registry::*;
pub use std::*;
