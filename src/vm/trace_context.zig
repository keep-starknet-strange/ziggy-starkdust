const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Relocatable = @import("./memory/relocatable.zig").Relocatable;

/// The inner state of the `TraceContext`.
///
/// It's either something, or nothing. But no tag is kept around to remember which one it is. This
/// "memory" comes from dynamic dispatch.
const State = union {
    enabled: TraceEnabled,
    disabled: TraceDisabled,

    /// A function that records a new entry in the tracing context.
    const TraceInstructionFn = fn (state: *State, entry: TraceContext.Entry) Allocator.Error!void;
    /// A function that frees the resources owned by the tracing context.
    const DeinitFn = fn (state: *State) void;
};

/// Contains the state required to trace the execution of the Cairo VM.
///
/// This includes a big array with `TraceEntry` instances.
pub const TraceContext = struct {
    /// An entry recorded representing the state of the VM at a given point in time.
    pub const Entry = struct {
        pc: *Relocatable,
        ap: *Relocatable,
        fp: *Relocatable,
    };

    /// The current state of the tracing context.
    state: State,

    //
    // DYNAMIC DISPATCH FUNCTIONS
    //
    // The following functions "remember" whether `state` is in an intialized or deinitialized
    // state and properly act accordingly.
    //

    /// A function to call when a new entry is recorded.
    traceInstructionFn: *const State.TraceInstructionFn,
    /// A functio to call
    deinitFn: *const State.DeinitFn,

    /// Initializes a new instance of `TraceContext`.
    ///
    /// # Arguments
    ///
    /// - `allocator`: the allocator to use for allocating the resources used by the tracing
    ///   context.
    ///
    /// - `enable`: Whether tracing should be enabled in the first place. When `false`, the
    ///   API exposed by `TraceContext` becomes essentially a no-op.
    ///
    /// # Errors
    ///
    /// Fails in case of memory allocation errors.
    pub fn init(allocator: Allocator, enable: bool) !TraceContext {
        var state: State = undefined;
        var traceInstructionFn: *const State.TraceInstructionFn = undefined;
        var deinitFn: *const State.DeinitFn = undefined;

        if (enable) {
            state = State{ .enabled = try TraceEnabled.init(allocator) };
            traceInstructionFn = TraceEnabled.traceInstruction;
            deinitFn = TraceEnabled.deinit;
        } else {
            state = State{ .disabled = TraceDisabled{} };
            traceInstructionFn = TraceDisabled.traceInstruction;
            deinitFn = TraceDisabled.deinit;
        }

        return TraceContext{
            .state = state,
            .traceInstructionFn = traceInstructionFn,
            .deinitFn = deinitFn,
        };
    }

    /// Frees the resources owned by this instance of `TraceContext`.
    pub fn deinit(self: *TraceContext) void {
        self.deinitFn(&self.state);
    }

    /// Records a new entry in the tracing context.
    pub fn traceInstruction(self: *TraceContext, entry: TraceContext.Entry) !void {
        try self.traceInstructionFn(&self.state, entry);
    }

    /// Returns whether tracing is enabled.
    pub fn isEnabled(self: *const TraceContext) bool {
        return self.traceInstructionFn == TraceEnabled.traceInstruction;
    }
};

/// The state of the tracing system when it's enabled.
const TraceEnabled = struct {
    /// The entries that have been recorded so far.
    entries: ArrayList(TraceContext.Entry),

    fn init(allocator: Allocator) !TraceEnabled {
        return TraceEnabled{
            .entries = ArrayList(TraceContext.Entry).init(allocator),
        };
    }

    fn deinit(self: *State) void {
        const this = &self.enabled;
        this.entries.deinit();
    }

    fn traceInstruction(self: *State, entry: TraceContext.Entry) !void {
        const this = &self.enabled;
        try this.entries.append(entry);
    }
};

/// The state of the tracing system when it's disabled.
const TraceDisabled = struct {
    fn deinit(self: *State) void {
        const this = &self.disabled;
        _ = this;
    }

    fn traceInstruction(self: *State, entry: TraceContext.Entry) !void {
        const this = &self.disabled;
        _ = entry;
        _ = this;
    }
};
