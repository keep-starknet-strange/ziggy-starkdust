/// Whether tracing should be disabled globally. This prevents the
/// user from enabling tracing via the command line but it might
/// improve performance slightly.
pub const trace_disable = false;
/// The initial capacity of the buffer responsible for gathering execution trace
/// data.
pub const trace_initial_capacity: usize = 4096;
