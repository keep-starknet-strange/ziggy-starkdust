const std = @import("std");
const Felt252 = @import("starknet").fields.Felt252;
const RelocatedTraceEntry = @import("trace_context.zig").RelocatedTraceEntry;
const RelocatedFelt252 = @import("trace_context.zig").RelocatedFelt252;
const HintProcessor = @import("../hint_processor/hint_processor_def.zig").CairoVMHintProcessor;

const Config = @import("config.zig").Config;
const cairo_run = @import("cairo_run.zig");
const cairo_runner = @import("runners/cairo_runner.zig");

const errors = @import("error.zig");

pub const PublicInput = struct {
    const Self = @This();

    layout: []const u8,
    rc_min: isize,
    rc_max: isize,
    n_steps: usize,

    // we use struct here only for json serialization/deserialization abstraction
    memory_segments: struct {
        value: std.StringHashMap(MemorySegmentAddresses),

        pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !@This() {
            if (.object_begin != try source.next()) return error.UnexpectedToken;
            var result = std.StringHashMap(MemorySegmentAddresses).init(allocator);
            errdefer result.deinit();

            while (true) {
                const name_token: ?std.json.Token = try source.nextAllocMax(allocator, .alloc_if_needed, options.max_value_len.?);
                const field_name = switch (name_token.?) {
                    inline .string, .allocated_string => |slice| slice,
                    .object_end => { // No more fields.
                        break;
                    },
                    else => {
                        return error.UnexpectedToken;
                    },
                };

                try result.put(field_name, try std.json.innerParse(MemorySegmentAddresses, allocator, source, options));
            }

            return .{ .value = result };
        }

        pub fn jsonStringify(self: @This(), out: anytype) !void {
            try out.beginObject();
            var it = self.value.iterator();
            while (it.next()) |x| {
                try out.objectField(x.key_ptr.*);
                try out.write(x.value_ptr.*);
            }
            try out.endObject();
        }
    },

    public_memory: struct {
        value: std.ArrayList(PublicMemoryEntry),

        pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !@This() {
            if (.array_begin != try source.next()) return error.UnexpectedToken;
            var result = std.ArrayList(PublicMemoryEntry).init(allocator);
            errdefer result.deinit();

            while (true) {
                switch (try source.peekNextTokenType()) {
                    inline .object_begin => try result.append(try std.json.innerParse(PublicMemoryEntry, allocator, source, options)),
                    inline .array_end => {
                        _ = try source.next();
                        return .{ .value = result };
                    },
                    else => return error.UnexpectedToken,
                }
            }

            return .{ .value = result };
        }

        pub fn jsonStringify(self: @This(), out: anytype) !void {
            try out.beginArray();
            for (self.value.items) |x| try out.write(x);
            try out.endArray();
        }
    },

    // serializing PublicInput to json
    pub fn serialize(self: *Self, allocator: std.mem.Allocator) ![]const u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        errdefer buffer.deinit();

        try std.json.stringify(self, .{}, buffer.writer());

        return try buffer.toOwnedSlice();
    }

    pub fn deserialize(allocator: std.mem.Allocator, data: []const u8) !std.json.Parsed(Self) {
        const parsed = try std.json.parseFromSlice(
            Self,
            allocator,
            data,
            .{
                // Always allocate memory during parsing
                .allocate = .alloc_always,
            },
        );

        // Return the parsed `ProgramJson` instance
        return parsed;
    }

    pub fn deinit(self: *Self) void {
        self.memory_segments.value.deinit();
        self.public_memory.value.deinit();
    }

    // new - creating new PublicInput, all arguments caller is owner
    pub fn new(
        allocator: std.mem.Allocator,
        memory: []const RelocatedFelt252,
        layout: []const u8,
        public_memory_addresses: []const std.meta.Tuple(&.{ usize, usize }),
        memory_segment_addresses: std.StringHashMap(std.meta.Tuple(&.{ usize, usize })),
        trace: []const RelocatedTraceEntry,
        rc_limits: std.meta.Tuple(&.{ isize, isize }),
    ) !Self {
        const memory_entry = (struct {
            fn func(mem: []const RelocatedFelt252, addresses: std.meta.Tuple(&.{ usize, usize })) !PublicMemoryEntry {
                const address, const page = addresses;
                return .{
                    .address = address,
                    .page = page,
                    .value = .{ .value = if (mem.len <= address) return errors.PublicInputError.MemoryNotFound else mem[address] },
                };
            }
        }).func;

        var public_memory = try std.ArrayList(PublicMemoryEntry).initCapacity(allocator, public_memory_addresses.len);
        errdefer public_memory.deinit();

        for (public_memory_addresses) |maddr| public_memory.appendAssumeCapacity(try memory_entry(memory, maddr));

        const rc_min, const rc_max = rc_limits;

        if (trace.len < 2) return errors.PublicInputError.EmptyTrace;

        const trace_first = trace[0];
        const trace_last = trace[trace.len - 1];

        return .{
            .layout = layout,
            .rc_min = rc_min,
            .rc_max = rc_max,
            .n_steps = trace.len,
            .memory_segments = .{ .value = blk: {
                var msa = std.StringHashMap(MemorySegmentAddresses).init(allocator);
                errdefer msa.deinit();

                var it = memory_segment_addresses.iterator();
                while (it.next()) |x| {
                    const begin_addr, const stop_ptr = x.value_ptr.*;

                    try msa.put(x.key_ptr.*, .{
                        .begin_addr = begin_addr,
                        .stop_ptr = stop_ptr,
                    });
                }

                try msa.put("program", .{ .begin_addr = trace_first.pc, .stop_ptr = trace_last.pc });

                try msa.put("execution", .{ .begin_addr = trace_first.ap, .stop_ptr = trace_last.ap });

                break :blk msa;
            } },
            .public_memory = .{ .value = public_memory },
        };
    }
};

pub const PublicMemoryEntry = struct {
    address: usize,
    value: struct {
        /// using struct only for json parse abstraction
        value: RelocatedFelt252,

        pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !@This() {
            _ = allocator; // autofix
            _ = options; // autofix
            switch (try source.next()) {
                inline .string => |data| {
                    const val = try std.fmt.parseInt(u256, data, 0);

                    return .{ .value = RelocatedFelt252.init(Felt252.fromInt(u256, val)) };
                },
                inline .null => return .{
                    .value = RelocatedFelt252.NONE,
                },
                else => return error.UnexpectedToken,
            }
        }

        pub fn jsonStringify(self: @This(), out: anytype) !void {
            if (self.value.getValue()) |v| try out.print("\"0x{x}\"", .{v.toU256()}) else try out.write(null);
        }
    },
    page: usize,
};

pub const MemorySegmentAddresses = struct {
    begin_addr: usize,
    stop_ptr: usize,
};

test "AirInputPublic" {
    const serialize_and_deserialize_air_input_public = (struct {
        fn func(program_content: []const u8) !void {
            const cfg = cairo_run.CairoRunConfig{
                .proof_mode = true,
                .relocate_mem = true,
                .trace_enabled = true,
                .layout = "all_cairo",
            };

            var processor: HintProcessor = .{};

            var runner = try cairo_run.cairoRun(std.testing.allocator, program_content, cfg, &processor);

            defer std.testing.allocator.destroy(runner.vm);
            defer runner.deinit(std.testing.allocator);
            defer runner.vm.segments.memory.deinitData(std.testing.allocator);

            var public_input = try runner.getAirPublicInput();
            defer public_input.deinit();

            const public_input_json = try public_input.serialize(std.testing.allocator);
            defer std.testing.allocator.free(public_input_json);

            var deserialized_public_input = try PublicInput.deserialize(std.testing.allocator, public_input_json);

            defer deserialized_public_input.deinit();
            defer deserialized_public_input.value.deinit();

            try std.testing.expectEqualSlices(u8, public_input.layout, deserialized_public_input.value.layout);
            try std.testing.expectEqual(public_input.rc_max, deserialized_public_input.value.rc_max);
            try std.testing.expectEqual(public_input.rc_min, deserialized_public_input.value.rc_min);
            try std.testing.expectEqual(public_input.n_steps, deserialized_public_input.value.n_steps);

            try std.testing.expectEqualSlices(PublicMemoryEntry, public_input.public_memory.value.items, deserialized_public_input.value.public_memory.value.items);

            try std.testing.expectEqual(public_input.memory_segments.value.count(), deserialized_public_input.value.memory_segments.value.count());

            var it = public_input.memory_segments.value.iterator();
            while (it.next()) |kv| {
                try std.testing.expect(deserialized_public_input.value.memory_segments.value.get(kv.key_ptr.*) != null);
                try std.testing.expectEqual(kv.value_ptr.*, deserialized_public_input.value.memory_segments.value.get(kv.key_ptr.*).?);
            }
        }
    }).func;

    const file = try std.fs.cwd().openFile("cairo_programs/proof_programs/fibonacci.json", .{ .mode = .read_only });

    const stat = try file.stat();

    const data = try file.readToEndAlloc(std.testing.allocator, stat.size);
    defer std.testing.allocator.free(data);

    try serialize_and_deserialize_air_input_public(data);
}
