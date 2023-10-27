pub const CairoVMError = error{
    AddRelocToRelocForbidden,
    MemoryOutOfBounds,
    MulRelocForbidden,
    InvalidMemoryAddress,
    InstructionFetchingFailed,
    InstructionEncodingError,
    ParseResLogicError,
    TypeMismatchNotFelt,
};
