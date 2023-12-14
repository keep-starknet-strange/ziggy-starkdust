const std = @import("std");

const Relocatable = @import("../../memory/relocatable.zig").Relocatable;
const MaybeRelocatable = @import("../../memory/relocatable.zig").MaybeRelocatable;
const Memory = @import("../../memory/memory.zig").Memory;
const MemorySegmentManager = @import("../../memory/segments.zig").MemorySegmentManager;
const Error = @import("../../error.zig");
const Felt252 = @import("../../../math/fields/starknet.zig").Felt252;
const CoreVM = @import("../../../vm/core.zig");

const AutoHashMap = std.AutoHashMap;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const MemoryError = Error.MemoryError;
const RunnerError = Error.RunnerError;
const CairoVMError = Error.CairoVMError;
const MathError = Error.MathError;
const CairoVM = CoreVM.CairoVM;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
const expectEqualSlices = std.testing.expectEqualSlices;

/// Represents errors specific to the OutputBuiltinRunner operations.
///
/// This error enumeration defines specific error cases encountered during OutputBuiltinRunner operations.
pub const OutputBuiltinRunnerError = error{
    /// Error indicating that the provided page ID is already assigned.
    PageIdAlreadyAssigned,
    /// Error indicating that the starting address for a page is not within the OutputBuiltinRunner's output segment.
    PageStartNotInOutputSegment,
};

/// Represents a page in the public memory within the OutputBuiltinRunner's memory configuration.
///
/// This struct defines a PublicMemoryPage, which encapsulates information about a specific page
/// within the OutputBuiltinRunner's memory, specifying the start address and size of the page.
pub const PublicMemoryPage = struct {
    /// The starting address of the page in the OutputBuiltinRunner's memory.
    ///
    /// It signifies the beginning address of the specific page within the memory.
    start: usize,

    /// The size of the page in the OutputBuiltinRunner's memory, denoted by the number of addresses.
    ///
    /// It indicates the quantity of addresses allocated for the particular page within the memory.
    size: usize,
};

/// Output built-in runner
pub const OutputBuiltinRunner = struct {
    const Self = @This();

    /// Base
    base: usize,
    /// Stop pointer
    stop_ptr: ?usize,
    /// Included boolean flag
    included: bool,
    /// A mapping from page IDs to their respective PublicMemoryPage configurations.
    ///
    /// This map stores associations between page IDs and their corresponding PublicMemoryPage configurations.
    pages: AutoHashMap(usize, PublicMemoryPage),

    /// Initializes a new instance of the OutputBuiltinRunner.
    ///
    /// This function creates and returns a new OutputBuiltinRunner instance
    /// with default configuration, setting the base address to 0, stop pointer to null,
    /// and marks the runner as included by default.
    ///
    /// # Returns
    ///
    /// A new instance of OutputBuiltinRunner with default settings.
    pub fn initDefault(allocator: Allocator) Self {
        return .{
            .base = 0,
            .stop_ptr = null,
            .included = true,
            .pages = AutoHashMap(usize, PublicMemoryPage).init(allocator),
        };
    }

    /// Create a new OutputBuiltinRunner instance.
    ///
    /// This function initializes a new `OutputBuiltinRunner` instance with the provided `included` value.
    ///
    /// # Arguments
    ///
    /// - `included`: A boolean flag indicating whether this runner is included.
    ///
    /// # Returns
    ///
    /// A new `OutputBuiltinRunner` instance.
    pub fn from(included: bool, allocator: Allocator) Self {
        return .{
            .base = 0,
            .stop_ptr = null,
            .included = included,
            .pages = AutoHashMap(usize, PublicMemoryPage).init(allocator),
        };
    }

    /// Initializes segments for the OutputBuiltinRunner instance using the provided MemorySegmentManager.
    ///
    /// This function sets the base address for the OutputBuiltinRunner instance by adding a segment through the MemorySegmentManager.
    ///
    /// # Arguments
    ///
    /// - `self`: A pointer to the OutputBuiltinRunner instance.
    /// - `segments`: A pointer to the MemorySegmentManager managing memory segments.
    ///
    /// # Returns
    ///
    /// An error if the addition of the segment fails, otherwise sets the base address successfully.
    pub fn initSegments(self: *Self, segments: *MemorySegmentManager) !void {
        self.base = @intCast((try segments.addSegment()).segment_index);
        self.stop_ptr = null;
    }

    /// Generates an initial stack for the OutputBuiltinRunner instance.
    ///
    /// This function initializes an ArrayList of MaybeRelocatable elements representing the initial stack.
    ///
    /// # Arguments
    ///
    /// - `self`: A pointer to the OutputBuiltinRunner instance.
    /// - `allocator`: The allocator to initialize the ArrayList.
    ///
    /// # Returns
    ///
    /// An ArrayList of MaybeRelocatable elements representing the initial stack.
    /// If the instance is marked as included, a single element initialized with the base address is returned.
    pub fn initialStack(self: *Self, allocator: Allocator) !ArrayList(MaybeRelocatable) {
        var result = ArrayList(MaybeRelocatable).init(allocator);
        if (self.included) {
            try result.append(MaybeRelocatable.fromSegment(
                @intCast(self.base),
                0,
            ));
            return result;
        }
        return result;
    }

    /// Retrieves the number of used memory cells for the OutputBuiltinRunner instance.
    ///
    /// This function queries the MemorySegmentManager to obtain the count of used cells
    /// based on the base address of the OutputBuiltinRunner.
    ///
    /// # Arguments
    ///
    /// - `self`: A pointer to the OutputBuiltinRunner instance.
    /// - `segments`: A pointer to the MemorySegmentManager managing memory segments.
    ///
    /// # Returns
    ///
    /// The count of used memory cells associated with the OutputBuiltinRunner's base address.
    /// If the information is unavailable, it returns MemoryError.MissingSegmentUsedSizes.
    pub fn getUsedCells(self: *Self, segments: *MemorySegmentManager) !u32 {
        return segments.getSegmentUsedSize(
            @intCast(self.base),
        ) orelse MemoryError.MissingSegmentUsedSizes;
    }

    /// Retrieves the count of used instances for the OutputBuiltinRunner instance.
    ///
    /// This function acts as an alias for `getUsedCells`, obtaining the number of used instances
    /// based on the OutputBuiltinRunner's base address through the MemorySegmentManager.
    ///
    /// Output builtin has one cell per instance.
    ///
    /// # Arguments
    ///
    /// - `self`: A pointer to the OutputBuiltinRunner instance.
    /// - `segments`: A pointer to the MemorySegmentManager managing memory segments.
    ///
    /// # Returns
    ///
    /// The count of used instances associated with the OutputBuiltinRunner's base address.
    /// If the information is unavailable, it returns MemoryError.MissingSegmentUsedSizes.
    pub fn getUsedInstances(self: *Self, segments: *MemorySegmentManager) !u32 {
        return try self.getUsedCells(segments);
    }

    /// Retrieves the count of used cells and their allocated size for the OutputBuiltinRunner.
    ///
    /// This function obtains the count of used cells from the MemorySegmentManager
    /// and returns a Tuple containing the size of used cells and their allocated size (both identical).
    ///
    /// # Arguments
    ///
    /// - `self`: A pointer to the OutputBuiltinRunner instance.
    /// - `segments`: A pointer to the MemorySegmentManager managing memory segments.
    ///
    /// # Returns
    ///
    /// A Tuple containing the count of used cells and their allocated size, both with the same value.
    pub fn getUsedCellsAndAllocatedSize(
        self: *Self,
        segments: *MemorySegmentManager,
    ) !std.meta.Tuple(&.{ u32, u32 }) {
        const size = try self.getUsedCells(segments);
        return .{ size, size };
    }

    /// Finalizes the stack configuration for the OutputBuiltinRunner instance.
    ///
    /// This function determines the final stop pointer for the stack and sets the stop pointer value
    /// for the OutputBuiltinRunner, handling conditions based on inclusion status and pointer validity.
    ///
    /// # Arguments
    ///
    /// - `self`: A pointer to the OutputBuiltinRunner instance.
    /// - `segments`: A pointer to the MemorySegmentManager managing memory segments.
    /// - `pointer`: The Relocatable pointer indicating the stack configuration.
    ///
    /// # Returns
    ///
    /// The finalized stop pointer address or the updated pointer based on the inclusion status.
    /// It returns specific RunnerError types if invalid or missing pointers are encountered.
    pub fn finalStack(
        self: *Self,
        segments: *MemorySegmentManager,
        pointer: Relocatable,
    ) !Relocatable {
        if (self.included) {
            const stop_pointer_addr = pointer.subUint(
                @intCast(1),
            ) catch return RunnerError.NoStopPointer;
            const stop_pointer = try (segments.memory.get(stop_pointer_addr) orelse return RunnerError.NoStopPointer).tryIntoRelocatable();
            if (@as(
                isize,
                @intCast(self.base),
            ) != stop_pointer.segment_index) {
                return RunnerError.InvalidStopPointerIndex;
            }
            const stop_ptr = stop_pointer.offset;

            if (stop_ptr != self.getUsedCells(segments) catch return RunnerError.Memory) {
                return RunnerError.InvalidStopPointer;
            }
            self.stop_ptr = stop_ptr;
            return stop_pointer_addr;
        }

        self.stop_ptr = 0;
        return pointer;
    }

    /// Retrieves the memory segment addresses associated with the OutputBuiltinRunner instance.
    ///
    /// This function returns a Tuple containing the base and stop pointer addresses
    /// related to the OutputBuiltinRunner's memory segments configuration.
    ///
    /// # Arguments
    ///
    /// - `self`: A pointer to the OutputBuiltinRunner instance.
    ///
    /// # Returns
    ///
    /// A Tuple containing the base and stop pointer addresses, indicating the memory segment configuration.
    pub fn getMemorySegmentAddresses(self: *Self) std.meta.Tuple(&.{ usize, ?usize }) {
        return .{ self.base, self.stop_ptr };
    }

    /// Retrieves the count of allocated memory units for the OutputBuiltinRunner instance within the CairoVM.
    ///
    /// This function currently returns 0 because the output builtin uses only public memory units.
    ///
    /// # Arguments
    ///
    /// - `self`: A pointer to the OutputBuiltinRunner instance.
    /// - `vm`: The CairoVM instance associated with the runner.
    ///
    /// # Returns
    ///
    /// The count of allocated memory units, which is currently 0.
    pub fn getAllocatedMemoryUnits(self: *Self, vm: CairoVM) !usize {
        _ = self;
        _ = vm;
        return 0;
    }

    /// Marks a range of addresses as a page within the OutputBuiltinRunner's memory.
    ///
    /// This function assigns a page ID to a range of addresses, starting from page_start,
    /// representing a page with the given page ID. It should be used in Cairo hints.
    ///
    /// # Arguments
    ///
    /// - `self`: A pointer to the OutputBuiltinRunner instance.
    /// - `page_id`: The identifier for the new page.
    /// - `page_start`: The starting address representing the beginning of the page.
    /// - `page_size`: The size of the page in number of addresses.
    ///
    /// # Returns
    ///
    /// An error if the page ID is already assigned or if the starting address is not within
    /// the OutputBuiltinRunner's output segment.
    pub fn addPage(
        self: *Self,
        page_id: usize,
        page_start: MaybeRelocatable,
        page_size: usize,
    ) !void {
        if (self.pages.get(page_id) != null) return OutputBuiltinRunnerError.PageIdAlreadyAssigned;
        if (!page_start.isRelocatable() or page_start.relocatable.segment_index != self.base) {
            return OutputBuiltinRunnerError.PageStartNotInOutputSegment;
        }
        // Builtin base offset is always 0, hence no need to do `page_start - self.base`
        try self.pages.put(
            page_id,
            .{ .start = page_start.relocatable.offset, .size = page_size },
        );
    }

    /// Sets the base address and updates the pages in the OutputBuiltinRunner instance.
    ///
    /// This function updates the base address of the OutputBuiltinRunner and refreshes its associated pages
    /// with the provided hashmap containing page configurations.
    ///
    /// This can be used before calling another program which manages its own memory pages and attributes.
    ///
    /// # Arguments
    ///
    /// - `self`: A pointer to the OutputBuiltinRunner instance.
    /// - `base`: The new base address to be set.
    /// - `pages`: A hashmap containing page configurations (usize keys to PublicMemoryPage values).
    ///
    /// # Returns
    ///
    /// An error if encountered during page updates or setting the base address.
    pub fn setState(
        self: *Self,
        base: usize,
        pages: AutoHashMap(usize, PublicMemoryPage),
    ) !void {
        self.clearStateWithBase(base);
        var it = pages.iterator();
        while (it.next()) |entry| {
            try self.pages.put(entry.key_ptr.*, entry.value_ptr.*);
        }
    }

    /// Updates the base address and clears all pages in the OutputBuiltinRunner instance.
    ///
    /// This function resets the base address of the OutputBuiltinRunner to the provided value
    /// and clears all existing page configurations, effectively resetting the runner's state.
    ///
    /// # Arguments
    ///
    /// - `self`: A pointer to the OutputBuiltinRunner instance.
    /// - `base`: The new base address to be set.
    pub fn clearStateWithBase(self: *Self, base: usize) void {
        self.base = base;
        self.pages.clearAndFree();
    }

    pub fn deduceMemoryCell(
        self: *const Self,
        address: Relocatable,
        memory: *Memory,
    ) ?MaybeRelocatable {
        _ = memory;
        _ = address;
        _ = self;
        return null;
    }

    /// Deinitializes the OutputBuiltinRunner's resources.
    ///
    /// This function releases resources held by the OutputBuiltinRunner,
    /// specifically deinitializing the 'pages' map, freeing associated memory.
    ///
    /// # Arguments
    ///
    /// - `self`: A pointer to the OutputBuiltinRunner instance.
    pub fn deinit(self: *Self) void {
        self.pages.deinit();
    }
};

test "OutputBuiltinRunner: initSegments should set builtin base to segment index" {
    var output_builtin = OutputBuiltinRunner.initDefault(std.testing.allocator);
    defer output_builtin.deinit();
    const memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();
    _ = try memory_segment_manager.addSegment();
    try output_builtin.initSegments(memory_segment_manager);
    try expectEqual(
        @as(usize, 1),
        output_builtin.base,
    );
}

test "OutputBuiltinRunner: initialStack should return an empty array list if included is false" {
    var output_builtin = OutputBuiltinRunner.from(false, std.testing.allocator);
    defer output_builtin.deinit();
    var expected = ArrayList(MaybeRelocatable).init(std.testing.allocator);
    defer expected.deinit();
    var actual = try output_builtin.initialStack(std.testing.allocator);
    defer actual.deinit();
    try expectEqual(
        expected,
        actual,
    );
}

test "OutputBuiltinRunner: initialStack should return an a proper array list if included is true" {
    var output_builtin = OutputBuiltinRunner.initDefault(std.testing.allocator);
    defer output_builtin.deinit();
    output_builtin.base = 10;
    var expected = ArrayList(MaybeRelocatable).init(std.testing.allocator);
    try expected.append(.{ .relocatable = .{
        .segment_index = 10,
        .offset = 0,
    } });
    defer expected.deinit();
    var actual = try output_builtin.initialStack(std.testing.allocator);
    defer actual.deinit();
    try expectEqualSlices(
        MaybeRelocatable,
        expected.items,
        actual.items,
    );
}

test "OutputBuiltinRunner: getUsedCells should return memory error if segment used size is null" {
    var output_builtin = OutputBuiltinRunner.initDefault(std.testing.allocator);
    defer output_builtin.deinit();
    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();
    try expectError(
        MemoryError.MissingSegmentUsedSizes,
        output_builtin.getUsedCells(memory_segment_manager),
    );
}

test "OutputBuiltinRunner: getUsedCells should return the number of used cells" {
    var output_builtin = OutputBuiltinRunner.initDefault(std.testing.allocator);
    defer output_builtin.deinit();
    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();
    try memory_segment_manager.segment_used_sizes.put(0, 10);
    try expectEqual(
        @as(
            u32,
            @intCast(10),
        ),
        try output_builtin.getUsedCells(memory_segment_manager),
    );
}

test "OutputBuiltinRunner: getUsedInstances should return memory error if segment used size is null" {
    var output_builtin = OutputBuiltinRunner.initDefault(std.testing.allocator);
    defer output_builtin.deinit();
    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();
    try expectError(
        MemoryError.MissingSegmentUsedSizes,
        output_builtin.getUsedInstances(memory_segment_manager),
    );
}

test "OutputBuiltinRunner: getUsedInstances should return the number of used instances" {
    var output_builtin = OutputBuiltinRunner.initDefault(std.testing.allocator);
    defer output_builtin.deinit();
    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();
    try memory_segment_manager.segment_used_sizes.put(0, 345);
    try expectEqual(
        @as(u32, @intCast(345)),
        try output_builtin.getUsedInstances(memory_segment_manager),
    );
}

test "OutputBuiltinRunner: finalStack should return relocatable pointer if not included" {
    var output_builtin = OutputBuiltinRunner.from(false, std.testing.allocator);
    defer output_builtin.deinit();
    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();

    try expectEqual(
        Relocatable.init(
            2,
            2,
        ),
        try output_builtin.finalStack(
            memory_segment_manager,
            Relocatable.init(2, 2),
        ),
    );
}

test "OutputBuiltinRunner: finalStack should return NoStopPointer error if pointer offset is 0" {
    var output_builtin = OutputBuiltinRunner.initDefault(std.testing.allocator);
    defer output_builtin.deinit();
    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();
    try expectError(
        RunnerError.NoStopPointer,
        output_builtin.finalStack(
            memory_segment_manager,
            Relocatable.init(2, 0),
        ),
    );
}

test "OutputBuiltinRunner: finalStack should return NoStopPointer error if no data in memory at the given stop pointer address" {
    var output_builtin = OutputBuiltinRunner.initDefault(std.testing.allocator);
    defer output_builtin.deinit();
    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();
    try expectError(
        RunnerError.NoStopPointer,
        output_builtin.finalStack(
            memory_segment_manager,
            Relocatable.init(2, 2),
        ),
    );
}

test "OutputBuiltinRunner: finalStack should return TypeMismatchNotRelocatable error if data in memory at the given stop pointer address is not Relocatable" {
    var output_builtin = OutputBuiltinRunner.initDefault(std.testing.allocator);
    defer output_builtin.deinit();
    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();

    _ = try memory_segment_manager.addSegment();
    _ = try memory_segment_manager.addSegment();
    _ = try memory_segment_manager.addSegment();
    try memory_segment_manager.memory.set(
        std.testing.allocator,
        try Relocatable.init(
            2,
            2,
        ).subUint(@intCast(1)),
        .{ .felt = Felt252.fromInteger(10) },
    );
    defer memory_segment_manager.memory.deinitData(std.testing.allocator);

    try expectError(
        CairoVMError.TypeMismatchNotRelocatable,
        output_builtin.finalStack(
            memory_segment_manager,
            Relocatable.init(2, 2),
        ),
    );
}

test "OutputBuiltinRunner: finalStack should return InvalidStopPointerIndex error if segment index of stop pointer is not KeccakBuiltinRunner base" {
    var output_builtin = OutputBuiltinRunner.initDefault(std.testing.allocator);
    defer output_builtin.deinit();
    output_builtin.base = 22;
    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();

    _ = try memory_segment_manager.addSegment();
    _ = try memory_segment_manager.addSegment();
    _ = try memory_segment_manager.addSegment();
    try memory_segment_manager.memory.set(
        std.testing.allocator,
        try Relocatable.init(
            2,
            2,
        ).subUint(@intCast(1)),
        .{ .relocatable = Relocatable.init(
            10,
            2,
        ) },
    );
    defer memory_segment_manager.memory.deinitData(std.testing.allocator);

    try expectError(
        RunnerError.InvalidStopPointerIndex,
        output_builtin.finalStack(
            memory_segment_manager,
            Relocatable.init(2, 2),
        ),
    );
}

test "OutputBuiltinRunner: finalStack should return InvalidStopPointer error if stop pointer offset is not cells used" {
    var output_builtin = OutputBuiltinRunner.initDefault(std.testing.allocator);
    defer output_builtin.deinit();
    output_builtin.base = 22;
    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();
    _ = try memory_segment_manager.addSegment();
    _ = try memory_segment_manager.addSegment();
    _ = try memory_segment_manager.addSegment();
    try memory_segment_manager.memory.set(
        std.testing.allocator,
        try Relocatable.init(
            2,
            2,
        ).subUint(@intCast(1)),
        .{ .relocatable = Relocatable.init(
            22,
            2,
        ) },
    );
    defer memory_segment_manager.memory.deinitData(std.testing.allocator);

    try memory_segment_manager.segment_used_sizes.put(22, 345);
    try expectError(
        RunnerError.InvalidStopPointer,
        output_builtin.finalStack(
            memory_segment_manager,
            Relocatable.init(2, 2),
        ),
    );
}

test "OutputBuiltinRunner: finalStack should return stop pointer address and update stop_ptr" {
    var output_builtin = OutputBuiltinRunner.initDefault(std.testing.allocator);
    defer output_builtin.deinit();
    output_builtin.base = 22;
    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();

    _ = try memory_segment_manager.addSegment();
    _ = try memory_segment_manager.addSegment();
    _ = try memory_segment_manager.addSegment();
    try memory_segment_manager.memory.set(
        std.testing.allocator,
        try Relocatable.init(
            2,
            2,
        ).subUint(@intCast(1)),
        .{ .relocatable = Relocatable.init(
            22,
            345,
        ) },
    );
    defer memory_segment_manager.memory.deinitData(std.testing.allocator);

    try memory_segment_manager.segment_used_sizes.put(22, 345);
    try expectEqual(
        Relocatable.init(2, 1),
        try output_builtin.finalStack(
            memory_segment_manager,
            Relocatable.init(2, 2),
        ),
    );
    try expectEqual(
        @as(?usize, @intCast(345)),
        output_builtin.stop_ptr.?,
    );
}

test "OutputBuiltinRunner: getMemorySegmentAddresses should return base and stop pointer" {
    var output_builtin = OutputBuiltinRunner.initDefault(std.testing.allocator);
    defer output_builtin.deinit();
    output_builtin.base = 22;
    try expectEqual(
        @as(
            std.meta.Tuple(&.{ usize, ?usize }),
            .{ 22, null },
        ),
        output_builtin.getMemorySegmentAddresses(),
    );
}

test "OutputBuiltinRunner: getAllocatedMemoryUnits should return 0" {
    var output_builtin = OutputBuiltinRunner.initDefault(std.testing.allocator);
    defer output_builtin.deinit();
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();
    try expectEqual(
        @as(usize, 0),
        try output_builtin.getAllocatedMemoryUnits(vm),
    );
}

test "OutputBuiltinRunner: addPage should an error if the page already exists" {
    var output_builtin = OutputBuiltinRunner.initDefault(std.testing.allocator);
    defer output_builtin.deinit();
    try output_builtin.pages.put(10, .{ .start = 2, .size = 4 });

    try expectError(
        OutputBuiltinRunnerError.PageIdAlreadyAssigned,
        output_builtin.addPage(
            10,
            MaybeRelocatable.fromU256(4),
            5,
        ),
    );
}

test "OutputBuiltinRunner: addPage should an error if page_start is Felt252" {
    var output_builtin = OutputBuiltinRunner.initDefault(std.testing.allocator);
    defer output_builtin.deinit();

    try expectError(
        OutputBuiltinRunnerError.PageStartNotInOutputSegment,
        output_builtin.addPage(
            10,
            MaybeRelocatable.fromU256(4),
            5,
        ),
    );
}

test "OutputBuiltinRunner: addPage should an error if page_start segment index is not OutputBuiltinRunner base" {
    var output_builtin = OutputBuiltinRunner.initDefault(std.testing.allocator);
    defer output_builtin.deinit();

    try expectError(
        OutputBuiltinRunnerError.PageStartNotInOutputSegment,
        output_builtin.addPage(
            10,
            MaybeRelocatable.fromSegment(1, 0),
            5,
        ),
    );
}

test "OutputBuiltinRunner: addPage should add a page" {
    // Creates a new OutputBuiltinRunner instance and initializes it with a base address of 10.
    var output_builtin = OutputBuiltinRunner.initDefault(std.testing.allocator);
    defer output_builtin.deinit();
    // Sets the base address to 10.
    output_builtin.base = 10;

    // Tries to add a new page with ID 10, starting from address 112, and with a size of 5.
    try output_builtin.addPage(
        10,
        MaybeRelocatable.fromSegment(10, 112),
        5,
    );

    // Tests if the number of pages in the runner's hashmap is equal to 1.
    try expectEqual(@as(usize, 1), output_builtin.pages.count());
    // Tests if the page with ID 10 has the expected configuration: start address = 112, size = 5.
    try expectEqual(
        PublicMemoryPage{ .start = 112, .size = 5 },
        output_builtin.pages.get(10).?, // Fetches the page configuration associated with ID 10.
    );
}

test "OutputBuiltinRunner: setState should set a new base and page hash map" {
    // Creates a new OutputBuiltinRunner instance and initializes it with a base address of 10.
    var output_builtin = OutputBuiltinRunner.initDefault(std.testing.allocator);
    // Deinitializes the runner when the function scope ends.
    defer output_builtin.deinit();
    // Sets the base address to 10.
    output_builtin.base = 10;

    // Sets up the initial pages in the runner's hashmap with various IDs and configurations.
    try output_builtin.pages.put(
        8,
        .{ .start = 23, .size = 2 },
    );
    try output_builtin.pages.put(
        8,
        .{ .start = 22, .size = 12 },
    );
    try output_builtin.pages.put(
        2,
        .{ .start = 10, .size = 2 },
    );

    // Prepares a new set of pages to update the runner's state.
    // Defines a new base address.
    const new_base: usize = 36;
    // Initializes a new hashmap.
    var new_pages = AutoHashMap(usize, PublicMemoryPage).init(std.testing.allocator);
    // Deinitializes the new hashmap when the function scope ends.
    defer new_pages.deinit();

    // Populates the new hashmap with pages having different IDs and configurations.
    try new_pages.put(
        83,
        .{ .start = 3, .size = 122 },
    );
    try new_pages.put(
        9,
        .{ .start = 1, .size = 242 },
    );
    try new_pages.put(
        99,
        .{ .start = 12, .size = 22 },
    );
    try new_pages.put(
        2434,
        .{ .start = 126365, .size = 34354 },
    );

    // Updates the state of the output_builtin runner with the new base address and pages.
    try output_builtin.setState(new_base, new_pages);

    // Tests if the base address is updated to the new_base (36).
    try expectEqual(@as(usize, 36), output_builtin.base);

    // Tests if the number of pages in the runner's hashmap is equal to 4 after the state update.
    try expectEqual(@as(usize, 4), output_builtin.pages.count());

    // Tests if each page in the hashmap has the expected configurations after the state update.
    try expectEqual(
        PublicMemoryPage{ .start = 3, .size = 122 },
        output_builtin.pages.get(83).?,
    );
    try expectEqual(
        PublicMemoryPage{ .start = 1, .size = 242 },
        output_builtin.pages.get(9).?,
    );
    try expectEqual(
        PublicMemoryPage{ .start = 12, .size = 22 },
        output_builtin.pages.get(99).?,
    );
    try expectEqual(
        PublicMemoryPage{ .start = 126365, .size = 34354 },
        output_builtin.pages.get(2434).?,
    );
}

test "OutputBuiltinRunner: clearStateWithBase should set a new base and clear pages" {
    // Creates a new OutputBuiltinRunner instance and initializes it with a base address of 10.
    var output_builtin = OutputBuiltinRunner.initDefault(std.testing.allocator);
    // Deinitializes the runner when the function scope ends.
    defer output_builtin.deinit();
    // Sets the base address to 10.
    output_builtin.base = 10;

    // Sets up the initial pages in the runner's hashmap with various IDs and configurations.
    try output_builtin.pages.put(
        8,
        .{ .start = 23, .size = 2 },
    );
    try output_builtin.pages.put(
        8,
        .{ .start = 22, .size = 12 },
    );
    try output_builtin.pages.put(
        2,
        .{ .start = 10, .size = 2 },
    );

    // Clears the state of the OutputBuiltinRunner instance by setting a new base address of 34.
    output_builtin.clearStateWithBase(34);

    // Verifies whether the base address of the OutputBuiltinRunner was updated to 34.
    try expectEqual(@as(usize, 34), output_builtin.base);

    // Verifies if the count of pages in the OutputBuiltinRunner's hashmap is 0 after the state clearing.
    try expectEqual(@as(usize, 0), output_builtin.pages.count());
}
