pub const vm = struct {
    pub usingnamespace @import("vm/core.zig");
    pub usingnamespace @import("vm/cairo_run.zig");
    pub usingnamespace @import("vm/core_test.zig");
    pub usingnamespace @import("vm/config.zig");
    pub usingnamespace @import("vm/error.zig");
    pub usingnamespace @import("vm/instructions.zig");
    pub usingnamespace @import("vm/run_context.zig");
    pub usingnamespace @import("vm/trace_context.zig");
    pub usingnamespace @import("vm/types/program.zig");
    pub usingnamespace @import("vm/types/programjson.zig");
    pub usingnamespace @import("vm/types/pedersen_instance_def.zig");
    pub usingnamespace @import("vm/types/poseidon_instance_def.zig");
    pub usingnamespace @import("vm/memory/memory.zig");
    pub usingnamespace @import("vm/memory/relocatable.zig");
    pub usingnamespace @import("vm/memory/segments.zig");
    pub usingnamespace @import("vm/runners/cairo_runner.zig");
    pub usingnamespace @import("vm/types/builtins_instance_def.zig");
    pub usingnamespace @import("vm/types/diluted_pool_instance_def.zig");
    pub usingnamespace @import("vm/types/cpu_instance_def.zig");
    pub usingnamespace @import("vm/types/layout.zig");
    pub usingnamespace @import("vm/decoding/decoder.zig");
};

pub const math = struct {
    pub usingnamespace @import("math/fields/helper.zig");
    pub usingnamespace @import("math/fields/fields.zig");
    pub usingnamespace @import("math/fields/stark_felt_252_gen_fp.zig");
    pub usingnamespace @import("math/fields/starknet.zig");
    pub usingnamespace @import("math/crypto/poseidon/poseidon.zig");
    pub usingnamespace @import("math/crypto/pedersen/pedersen.zig");
};

pub const utils = struct {
    pub usingnamespace @import("utils/log.zig");
    pub usingnamespace @import("utils/time.zig");
};

pub const build_options = @import("build_options.zig");

pub const hint_processor = struct {
    pub usingnamespace @import("hint_processor/hint_processor_def.zig");
    pub usingnamespace @import("hint_processor/memcpy_hint_utils.zig");
    pub usingnamespace @import("hint_processor/hint_utils.zig");
    pub usingnamespace @import("hint_processor/math_hints.zig");
    pub usingnamespace @import("hint_processor/keccak_utils.zig");
    pub usingnamespace @import("hint_processor/poseidon_utils.zig");
    pub usingnamespace @import("hint_processor/felt_bit_length.zig");
    pub usingnamespace @import("hint_processor/segments.zig");
    pub usingnamespace @import("hint_processor/uint256_utils.zig");
    pub usingnamespace @import("hint_processor/memset_utils.zig");
};

pub const parser = struct {
    pub usingnamespace @import("parser/deserialize_utils.zig");
};
