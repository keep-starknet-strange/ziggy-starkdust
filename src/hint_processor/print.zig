const std = @import("std");
const Allocator = std.mem.Allocator;
const CairoVM = @import("../vm/core.zig").CairoVM;
const HintReference = @import("hint_processor_def.zig").HintReference;
const ApTracking = @import("../vm/types/programjson.zig").ApTracking;
const hint_utils = @import("hint_utils.zig");
const Felt252 = @import("../math/fields/starknet.zig").Felt252;
const HintError = @import("../vm/error.zig").HintError;
const MaybeRelocatable = @import("../vm/memory/relocatable.zig").MaybeRelocatable;

pub fn printFelt(vm: *CairoVM, ids_data: std.StringHashMap(HintReference), ap_tracking: ApTracking) !void {
    const val = try hint_utils.getIntegerFromVarName("x", vm, ids_data, ap_tracking);
    std.debug.print("{}\n", .{val});
}

pub fn printName(vm: *CairoVM, ids_data: std.StringHashMap(HintReference), ap_tracking: ApTracking) !void {
    const name = try hint_utils.getIntegerFromVarName("name", vm, ids_data, ap_tracking);
    std.debug.print("{}\n", .{name});
}

// pub fn print_array(
//     vm: &VirtualMachine,
//     ids_data: &HashMap<String, HintReference>,
//     ap_tracking: &ApTracking,
// ) -> Result<(), HintError> {
//     print_name(vm, ids_data, ap_tracking)?;

//     let mut acc = Vec::new();
//     let arr = get_ptr_from_var_name("arr", vm, ids_data, ap_tracking)?;
//     let arr_len = get_integer_from_var_name("arr_len", vm, ids_data, ap_tracking)?;
//     let arr_len = arr_len.to_usize().ok_or_else(|| {
//         HintError::CustomHint(String::from("arr_len must be a positive integer").into_boxed_str())
//     })?;
//     for i in 0..arr_len {
//         let val = vm.get_integer((arr + i)?)?;
//         acc.push(val);
//     }
//     println!("{:?}", acc);
//     Ok(())
// }
pub fn printArray(allocator: Allocator, vm: *CairoVM, ids_data: std.StringHashMap(HintReference), ap_tracking: ApTracking) !void {
    try printName(vm, ids_data, ap_tracking);
    const arr = try hint_utils.getPtrFromVarName("arr", vm, ids_data, ap_tracking);
    const temp = try hint_utils.getIntegerFromVarName("arr_len", vm, ids_data, ap_tracking);
    const arr_len = try temp.intoUsize();
    var acc = try allocator.alloc(Felt252, arr_len);
    defer allocator.free(acc);
    for (0..arr_len) |i| {
        const val = try vm.getFelt(try arr.addUint(@as(u64, i)));
        acc[i] = val;
    }
    std.debug.print("arr: {any}\n", .{acc});
}
