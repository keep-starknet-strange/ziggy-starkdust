pub const CairoVMError = error{
    MemoryOutOfBounds,
    InvalidMemoryAddress,
    InstructionFetchingFailed,
    InstructionEncodingError,
    TypeMismatchNotFelt,
    RunnerError,
};
