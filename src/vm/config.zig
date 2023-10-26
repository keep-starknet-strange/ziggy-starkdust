// *****************************************************************************
// *                      CUSTOM TYPES DEFINITIONS                              *
// *****************************************************************************

/// Config used to initiate CairoVM
pub const Config = struct {
    /// Generate a proof for execution of the program
    proof_mode: bool = false,
    /// When enabled trace is generated
    enable_trace: bool = false,
};
