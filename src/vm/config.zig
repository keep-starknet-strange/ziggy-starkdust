// *****************************************************************************
// *                      CUSTOM TYPES DEFINITIONS                              *
// *****************************************************************************

/// Config used to initiate CairoVM
pub const Config = struct {
    proof_mode: bool,
    enable_trace: bool,

    pub fn default() Config {
        return Config{ .proof_mode = false, .enable_trace = false };
    }
};
