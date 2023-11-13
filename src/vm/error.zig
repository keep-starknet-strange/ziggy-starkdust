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
    NoDst,
    FailedToComputeOp1,
};

pub const MemoryError = error{
    MissingSegmentUsedSizes,
    AddressNotInTemporarySegment,
    NonZeroOffset,
    DuplicatedRelocation,
};

pub const RunnerError = error{
    NoStopPointer,
    InvalidStopPointerIndex,
    InvalidStopPointer,
    BuiltinExpectedInteger,
};
