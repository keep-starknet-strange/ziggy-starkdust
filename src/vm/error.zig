pub const CairoVMError = error{
    AddRelocToRelocForbidden,
    MemoryOutOfBounds,
    MulRelocForbidden,
    InvalidMemoryAddress,
    InstructionFetchingFailed,
    InstructionEncodingError,
    ParseResLogicError,
    TypeMismatchNotFelt,
    RunnerError,
    TypeMismatchNotRelocatable,
    ValueTooLarge,
    FailedToComputeOperands,
};

pub const MemoryError = error{
    MissingSegmentUsedSizes,
};

pub const RunnerError = error{
    NoStopPointer,
    InvalidStopPointerIndex,
    InvalidStopPointer,
    BuiltinExpectedInteger,
};
