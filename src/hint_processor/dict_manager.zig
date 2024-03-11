const hint_utils = @import("hint_utils.zig");
const std = @import("std");
const CairoVM = @import("../vm/core.zig").CairoVM;
const HintReference = @import("hint_processor_def.zig").HintReference;
const HintProcessor = @import("hint_processor_def.zig").CairoVMHintProcessor;
const testing_utils = @import("testing_utils.zig");
const Felt252 = @import("../math/fields/starknet.zig").Felt252;
const hint_codes = @import("builtin_hint_codes.zig");
const Relocatable = @import("../vm/memory/relocatable.zig").Relocatable;
const MaybeRelocatable = @import("../vm/memory/relocatable.zig").MaybeRelocatable;
const ApTracking = @import("../vm/types/programjson.zig").ApTracking;
const HintData = @import("hint_processor_def.zig").HintData;
const ExecutionScopes = @import("../vm/types/execution_scopes.zig").ExecutionScopes;
const HintType = @import("../vm/types/execution_scopes.zig").HintType;

const helper = @import("../math/fields/helper.zig");
const MathError = @import("../vm/error.zig").MathError;
const HintError = @import("../vm/error.zig").HintError;
const CairoVMError = @import("../vm/error.zig").CairoVMError;

const RangeCheckBuiltinRunner = @import("../vm/builtins/builtin_runner/range_check.zig").RangeCheckBuiltinRunner;

///Manages dictionaries in a Cairo program.
///Uses the segment index to associate the corresponding python dict with the Cairo dict.
pub const DictManager = struct {
    const Self = @This();
    trackers: std.AutoHashMap(isize, DictTracker),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .trackers = std.AutoHashMap(isize, DictTracker).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        var it = self.trackers.valueIterator();

        while (it.next()) |v|
            v.deinit();

        self.trackers.deinit();
    }

    //Creates a new Cairo dictionary. The values of initial_dict can be integers, tuples or
    //lists. See MemorySegments.gen_arg().
    //For now, no initial dict will be processed (Assumes initial_dict = None)
    pub fn initDict(self: *Self, vm: *CairoVM, initial_dict: std.AutoHashMap(MaybeRelocatable, MaybeRelocatable)) !MaybeRelocatable {
        const base = try vm.addMemorySegment();

        if (self.trackers.contains(base.segment_index)) {
            return HintError.CantCreateDictionaryOnTakenSegment;
        }

        try self.trackers.put(base.segment_index, try DictTracker.initWithInitial(base, initial_dict));

        return MaybeRelocatable.fromRelocatable(base);
    }

    //Creates a new Cairo default dictionary
    pub fn initDefaultDict(self: *Self, allocator: std.mem.Allocator, vm: *CairoVM, default_value: MaybeRelocatable, initial_dict: ?std.AutoHashMap(MaybeRelocatable, MaybeRelocatable)) !MaybeRelocatable {
        const base = try vm.addMemorySegment();

        if (self.trackers.contains(base.segment_index)) {
            return HintError.CantCreateDictionaryOnTakenSegment;
        }

        try self.trackers.put(base.segment_index, try DictTracker.initDefaultDict(allocator, base, default_value, initial_dict));

        return MaybeRelocatable.fromRelocatable(base);
    }

    //Returns the tracker which's current_ptr matches with the given dict_ptr
    pub fn getTrackerRef(self: *Self, dict_ptr: Relocatable) !*DictTracker {
        const tracker = self.trackers.getPtr(dict_ptr.segment_index) orelse return HintError.NoDictTracker;

        if (!tracker.current_ptr.eq(dict_ptr)) return HintError.MismatchedDictPtr;

        return tracker;
    }

    //Returns the tracker which's current_ptr matches with the given dict_ptr
    pub fn getTracker(self: *const Self, dict_ptr: Relocatable) !DictTracker {
        const tracker = self.trackers.get(dict_ptr.segment_index) orelse return HintError.NoDictTracker;

        if (!tracker.current_ptr.eq(dict_ptr)) return HintError.MismatchedDictPtr;

        return tracker;
    }
};

///Tracks the python dict associated with a Cairo dict.
pub const DictTracker = struct {
    const Self = @This();

    //Dictionary.
    data: Dictionary,
    //Pointer to the first unused position in the dict segment.
    current_ptr: Relocatable,

    pub fn initEmpty(allocator: std.mem.Allocator, base: Relocatable) Self {
        return .{
            .data = .{ .SimpleDictionary = std.AutoHashMap(MaybeRelocatable, MaybeRelocatable).init(allocator) },
            .current_ptr = base,
        };
    }

    pub fn initDefaultDict(
        allocator: std.mem.Allocator,
        base: Relocatable,
        default_value: MaybeRelocatable,
        initial_dict: ?std.AutoHashMap(MaybeRelocatable, MaybeRelocatable),
    ) !Self {
        return .{
            .data = .{
                .DefaultDictionary = .{
                    .dict = initial_dict orelse std.AutoHashMap(MaybeRelocatable, MaybeRelocatable).init(allocator),
                    .default_value = default_value,
                },
            },
            .current_ptr = base,
        };
    }

    pub fn initWithInitial(base: Relocatable, initial_dict: std.AutoHashMap(MaybeRelocatable, MaybeRelocatable)) !Self {
        return .{
            .data = .{
                .SimpleDictionary = initial_dict,
            },
            .current_ptr = base,
        };
    }

    //Returns a copy of the contained dictionary, losing the dictionary type in the process
    pub fn getDictionaryCopy(self: Self) !std.AutoHashMap(MaybeRelocatable, MaybeRelocatable) {
        return switch (self) {
            .SimpleDictionary => |dict| dict.clone(),
            .DefaultDictionary => |v| v.dict.clone(),
        };
    }

    pub fn getValue(self: *const Self, key: MaybeRelocatable) !MaybeRelocatable {
        self.data
            .get(key) orelse HintError.NoValueForKey;
    }

    pub fn insertValue(self: *Self, key: MaybeRelocatable, val: MaybeRelocatable) !void {
        try self.data.insert(key, val);
    }

    pub fn deinit(self: *Self) void {
        self.data.deinit();
    }
};

pub const Dictionary = union(enum) {
    const Self = @This();

    SimpleDictionary: std.AutoHashMap(MaybeRelocatable, MaybeRelocatable),
    DefaultDictionary: struct {
        dict: std.AutoHashMap(MaybeRelocatable, MaybeRelocatable),
        default_value: MaybeRelocatable,
    },

    pub fn deinit(self: *Self) void {
        switch (self.*) {
            .SimpleDictionary => |*v| v.deinit(),
            .DefaultDictionary => |*v| v.dict.deinit(),
        }
    }

    pub fn get(self: *Self, key: MaybeRelocatable) !?MaybeRelocatable {
        return switch (self.*) {
            .SimpleDictionary => |*dict| dict.get(key),
            .DefaultDictionary => |*v| (try v.dict.getOrPutValue(key, v.default_value)).value_ptr.*,
        };
    }

    pub fn insert(self: *Self, key: MaybeRelocatable, value: MaybeRelocatable) !void {
        var dict = switch (self.*) {
            .SimpleDictionary => |*dict| dict,
            .DefaultDictionary => |*v| &v.dict,
        };

        try dict.put(key, value);
    }
};

test "DictManager: create" {
    var dict_manager = DictManager.init(std.testing.allocator);
    defer dict_manager.deinit();

    try std.testing.expectEqual(0, dict_manager.trackers.count());
}

test "DictManager: create DictTracker empty" {
    var dict_tracker = DictTracker.initEmpty(std.testing.allocator, Relocatable.init(1, 0));
    defer dict_tracker.deinit();

    try std.testing.expectEqual(0, dict_tracker.data.SimpleDictionary.count());
    try std.testing.expectEqual(Relocatable.init(1, 0), dict_tracker.current_ptr);
}

test "DictManager: create DictTracker default" {
    var dict_tracker = try DictTracker.initDefaultDict(std.testing.allocator, Relocatable.init(1, 0), MaybeRelocatable.fromInt(u8, 5), null);
    defer dict_tracker.deinit();

    try std.testing.expectEqual(MaybeRelocatable.fromInt(u8, 5), dict_tracker.data.DefaultDictionary.default_value);
    try std.testing.expectEqual(0, dict_tracker.data.DefaultDictionary.dict.count());
    try std.testing.expectEqual(Relocatable.init(1, 0), dict_tracker.current_ptr);
}

test "DictManager: initDictEmpty" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    var dict_manager = DictManager.init(std.testing.allocator);
    defer dict_manager.deinit();

    const initial_dict = std.AutoHashMap(MaybeRelocatable, MaybeRelocatable).init(std.testing.allocator);
    const base = try dict_manager.initDict(&vm, initial_dict);

    try std.testing.expectEqual(base, MaybeRelocatable.fromRelocatable(Relocatable.init(0, 0)));

    try std.testing.expect(dict_manager.trackers.contains(0));
    try std.testing.expectEqual(Relocatable.init(0, 0), dict_manager.trackers.get(0).?.current_ptr);
    try std.testing.expectEqual(0, dict_manager.trackers.get(0).?.data.SimpleDictionary.count());
    try std.testing.expectEqual(vm.segments.numSegments(), 1);
}

test "DictManager: initDictDefault" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    var dict_manager = DictManager.init(std.testing.allocator);
    defer dict_manager.deinit();

    const base = try dict_manager.initDefaultDict(std.testing.allocator, &vm, MaybeRelocatable.fromInt(u8, 5), null);

    try std.testing.expectEqual(base, MaybeRelocatable.fromRelocatable(Relocatable.init(0, 0)));

    try std.testing.expect(dict_manager.trackers.contains(0));
    try std.testing.expectEqual(Relocatable.init(0, 0), dict_manager.trackers.get(0).?.current_ptr);
    try std.testing.expectEqual(0, dict_manager.trackers.get(0).?.data.DefaultDictionary.dict.count());
    try std.testing.expectEqual(MaybeRelocatable.fromInt(u8, 5), dict_manager.trackers.get(0).?.data.DefaultDictionary.default_value);
    try std.testing.expectEqual(vm.segments.numSegments(), 1);
}

test "DictManager: initDict with initial_dict" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    var dict_manager = DictManager.init(std.testing.allocator);
    defer dict_manager.deinit();

    var initial_dict = std.AutoHashMap(MaybeRelocatable, MaybeRelocatable).init(std.testing.allocator);
    try initial_dict.put(MaybeRelocatable.fromInt(u8, 5), MaybeRelocatable.fromInt(u8, 5));

    const base = try dict_manager.initDict(&vm, initial_dict);

    try std.testing.expectEqual(base, MaybeRelocatable.fromRelocatable(Relocatable.init(0, 0)));

    try std.testing.expect(dict_manager.trackers.contains(0));
    try std.testing.expectEqual(Relocatable.init(0, 0), dict_manager.trackers.get(0).?.current_ptr);
    try std.testing.expectEqual(1, dict_manager.trackers.get(0).?.data.SimpleDictionary.count());

    try std.testing.expectEqual(
        MaybeRelocatable.fromInt(u8, 5),
        dict_manager.trackers.get(0).?.data.SimpleDictionary.get(MaybeRelocatable.fromInt(u8, 5)),
    );
    try std.testing.expectEqual(vm.segments.numSegments(), 1);
}

test "DictManager: initDefaultDict with initial_dict" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    var dict_manager = DictManager.init(std.testing.allocator);
    defer dict_manager.deinit();

    var initial_dict = std.AutoHashMap(MaybeRelocatable, MaybeRelocatable).init(std.testing.allocator);
    try initial_dict.put(MaybeRelocatable.fromInt(u8, 5), MaybeRelocatable.fromInt(u8, 5));

    const base = try dict_manager.initDefaultDict(std.testing.allocator, &vm, MaybeRelocatable.fromInt(u8, 7), initial_dict);

    try std.testing.expectEqual(base, MaybeRelocatable.fromRelocatable(Relocatable.init(0, 0)));

    try std.testing.expect(dict_manager.trackers.contains(0));
    try std.testing.expectEqual(Relocatable.init(0, 0), dict_manager.trackers.get(0).?.current_ptr);
    try std.testing.expectEqual(1, dict_manager.trackers.get(0).?.data.DefaultDictionary.dict.count());
    try std.testing.expectEqual(MaybeRelocatable.fromInt(u8, 7), dict_manager.trackers.get(0).?.data.DefaultDictionary.default_value);

    try std.testing.expectEqual(
        MaybeRelocatable.fromInt(u8, 5),
        dict_manager.trackers.get(0).?.data.DefaultDictionary.dict.get(MaybeRelocatable.fromInt(u8, 5)),
    );
    try std.testing.expectEqual(vm.segments.numSegments(), 1);
}

test "DictManager: dict_manager_new_dict_empty_same_segment" {
    var dict_manager = DictManager.init(std.testing.allocator);
    defer dict_manager.deinit();
    try dict_manager
        .trackers
        .put(0, DictTracker.initEmpty(std.testing.allocator, Relocatable.init(0, 0)));

    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    try std.testing.expectError(HintError.CantCreateDictionaryOnTakenSegment, dict_manager.initDict(&vm, std.AutoHashMap(MaybeRelocatable, MaybeRelocatable).init(std.testing.allocator)));
}

test "DictManager: dict_manager_new_default_dict_empty_same_segment" {
    var dict_manager = DictManager.init(std.testing.allocator);
    defer dict_manager.deinit();
    try dict_manager
        .trackers
        .put(0, try DictTracker.initDefaultDict(std.testing.allocator, Relocatable.init(0, 0), MaybeRelocatable.fromInt(u8, 6), null));

    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    try std.testing.expectError(HintError.CantCreateDictionaryOnTakenSegment, dict_manager.initDict(&vm, std.AutoHashMap(MaybeRelocatable, MaybeRelocatable).init(std.testing.allocator)));
}

test "DictManager: dictionary_get_insert_simple" {
    var dictionary: Dictionary = .{ .SimpleDictionary = std.AutoHashMap(MaybeRelocatable, MaybeRelocatable).init(std.testing.allocator) };
    defer dictionary.deinit();
    try dictionary.insert(MaybeRelocatable.fromInt(u8, 1), MaybeRelocatable.fromInt(u8, 2));

    try std.testing.expectEqual(MaybeRelocatable.fromInt(u8, 2), dictionary.get(MaybeRelocatable.fromInt(u8, 1)));
    try std.testing.expectEqual(null, dictionary.get(MaybeRelocatable.fromInt(u8, 2)));
}

test "DictManager: dictionary_get_insert_default" {
    var dictionary: Dictionary = .{ .DefaultDictionary = .{ .dict = std.AutoHashMap(MaybeRelocatable, MaybeRelocatable).init(std.testing.allocator), .default_value = MaybeRelocatable.fromInt(u8, 7) } };

    defer dictionary.deinit();
    try dictionary.insert(MaybeRelocatable.fromInt(u8, 1), MaybeRelocatable.fromInt(u8, 2));

    try std.testing.expectEqual(MaybeRelocatable.fromInt(u8, 2), dictionary.get(MaybeRelocatable.fromInt(u8, 1)));
    try std.testing.expectEqual(MaybeRelocatable.fromInt(u8, 7), dictionary.get(MaybeRelocatable.fromInt(u8, 2)));
}
