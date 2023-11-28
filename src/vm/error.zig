/// Represents different error conditions that occur in the Cairo VM.
pub const CairoVMError = error{
    /// Adding two relocatables is forbidden.
    AddRelocToRelocForbidden,
    /// Memory access is out of bounds.
    MemoryOutOfBounds,
    /// Multiplying with a relocatable is forbidden.
    MulRelocForbidden,
    /// TODO, Invalid memory address encountered.
    InvalidMemoryAddress,
    /// Failed to fetch instruction from VM during the instruction cycle.
    InstructionFetchingFailed,
    /// Error in converting the encoded instruction to a u64.
    InstructionEncodingError,
    /// TODO, this error type is never used. ResLogic constants parsing related?
    ParseResLogicError,
    /// Occurs when values of different types are subtracted.
    TypeMismatchNotFelt,
    /// Error encountered with a built-in runner.
    RunnerError,
    /// Occurs when the expected value is not a Relocatable,
    /// or when subtracting two relocatables with different segment indices.
    TypeMismatchNotRelocatable,
    /// Occurs when both built-in deductions and fallback deductions for the operands fail.
    FailedToComputeOperands,
    /// No destination register can be deduced for the given opcode.
    NoDst,
    /// Occurs when both built-in deductions and fallback deductions fail to deduce Op1.
    FailedToComputeOp1,
    /// Occurs when both built-in deductions and fallback deductions fail to deduce Op0.
    FailedToComputeOp0,
};

/// Represent different error conditions that are memory-related.
pub const MemoryError = error{
    /// The amount of used cells associated with the Range Check runner is not available.
    MissingSegmentUsedSizes,
    /// The address is not in the temporary segment.
    AddressNotInTemporarySegment,
    /// Non-zero offset when it's not expected.
    NonZeroOffset,
    /// Duplicated relocation entry found.
    DuplicatedRelocation,
    /// Segment not allocated
    UnallocatedSegment,
    /// Temporary segment found while relocating (flattening) segment
    TemporarySegmentInRelocation,
    /// Inconsistent Relocation
    Relocation,
    /// Gap in memory range
    GetRangeMemoryGap,
    /// Math error
    Math,
};

/// Reepresents different error conditions that occur in the built-in runners.
pub const RunnerError = error{
    /// Errors associated with computing the address of a stop pointer of RangeCheckBuiltinRunner
    /// Raised when underflow occurs (i.e., subtracting 1 from 0),
    /// or when it fails to get a value for the computed address.
    NoStopPointer,
    /// Invalid stop pointer index occured in calculation of the final stack.
    InvalidStopPointerIndex,
    /// Invalid stop pointer occured in calculation of the final stack.
    InvalidStopPointer,
    /// Raised when the conversion into a type of integer (e.g. a Felt) fails.
    BuiltinExpectedInteger,
    /// Integer value exceeds a power of two.
    IntegerBiggerThanPowerOfTwo,
};

/// Represents different error conditions that occur during mathematical operations.
pub const MathError = error{
    /// Error when attempting to perform addition between Relocatable values.
    RelocatableAdd,
    /// Error when attempting to subtract a Relocatable from an integer value.
    SubRelocatableFromInt,
    /// Error when Relocatable offset is smaller than the integer value from which it is subtracted.
    RelocatableSubUsizeNegOffset,
    /// Value is too large to be coerced to a u64.
    ValueTooLarge,
};
