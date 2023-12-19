// *****************************************************************************
// *                      CUSTOM TYPES DEFINITIONS                              *
// *****************************************************************************

/// Config used to initiate CairoVM
pub const Config = struct {
    /// Generate a proof for execution of the program
    proof_mode: bool = false,
    /// When enabled trace is generated
    enable_trace: bool = false,
    /// The location of the program to be evaluated
    filename: []const u8 = undefined,
    /// The layout of the memory
    layout: []const u8 = undefined,
    /// Write trace to binary file
    output_trace: ?[]const u8 = undefined,
    /// Write memory to binary file
    output_memory: ?[]const u8 = undefined,
};
