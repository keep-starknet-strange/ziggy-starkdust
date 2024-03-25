pub const FIND_ELEMENT =
    \\array_ptr = ids.array_ptr
    \\elm_size = ids.elm_size
    \\assert isinstance(elm_size, int) and elm_size > 0, \
    \\    f'Invalid value for elm_size. Got: {elm_size}.'
    \\key = ids.key
    \\
    \\if '__find_element_index' in globals():
    \\    ids.index = __find_element_index
    \\    found_key = memory[array_ptr + elm_size * __find_element_index]
    \\    assert found_key == key, \
    \\        f'Invalid index found in __find_element_index. index: {__find_element_index}, ' \
    \\        f'expected key {key}, found key: {found_key}.'
    \\    # Delete __find_element_index to make sure it's not used for the next calls.
    \\    del __find_element_index
    \\else:
    \\    n_elms = ids.n_elms
    \\    assert isinstance(n_elms, int) and n_elms >= 0, \
    \\        f'Invalid value for n_elms. Got: {n_elms}.'
    \\    if '__find_element_max_size' in globals():
    \\        assert n_elms <= __find_element_max_size, \
    \\            f'find_element() can only be used with n_elms<={__find_element_max_size}. ' \
    \\            f'Got: n_elms={n_elms}.'
    \\
    \\    for i in range(n_elms):
    \\        if memory[array_ptr + elm_size * i] == key:
    \\            ids.index = i
    \\            break
    \\    else:
    \\        raise ValueError(f'Key {key} was not found.')
;

pub const SEARCH_SORTED_LOWER =
    \\array_ptr = ids.array_ptr
    \\elm_size = ids.elm_size
    \\assert isinstance(elm_size, int) and elm_size > 0, \
    \\    f'Invalid value for elm_size. Got: {elm_size}.'
    \\
    \\n_elms = ids.n_elms
    \\assert isinstance(n_elms, int) and n_elms >= 0, \
    \\    f'Invalid value for n_elms. Got: {n_elms}.'
    \\if '__find_element_max_size' in globals():
    \\    assert n_elms <= __find_element_max_size, \
    \\        f'find_element() can only be used with n_elms<={__find_element_max_size}. ' \
    \\        f'Got: n_elms={n_elms}.'
    \\
    \\for i in range(n_elms):
    \\    if memory[array_ptr + elm_size * i] >= ids.key:
    \\        ids.index = i
    \\        break
    \\else:
    \\    ids.index = n_elms
;

pub const SET_ADD =
    \\assert ids.elm_size > 0
    \\assert ids.set_ptr <= ids.set_end_ptr
    \\elm_list = memory.get_range(ids.elm_ptr, ids.elm_size)
    \\for i in range(0, ids.set_end_ptr - ids.set_ptr, ids.elm_size):
    \\    if memory.get_range(ids.set_ptr + i, ids.elm_size) == elm_list:
    \\        ids.index = i // ids.elm_size
    \\        ids.is_elm_in_set = 1
    \\        break
    \\else:
    \\    ids.is_elm_in_set = 0
;

pub const TEMPORARY_ARRAY = "ids.temporary_array = segments.add_temp_segment()";

pub const RELOCATE_SEGMENT = "memory.add_relocation_rule(src_ptr=ids.src_ptr, dest_ptr=ids.dest_ptr)";

pub const GET_FELT_BIT_LENGTH =
    \\x = ids.x
    \\ids.bit_length = x.bit_length()
;

pub const POW = "ids.locs.bit = (ids.prev_locs.exp % PRIME) & 1";

pub const ASSERT_NN = "from starkware.cairo.common.math_utils import assert_integer\nassert_integer(ids.a)\nassert 0 <= ids.a % PRIME < range_check_builtin.bound, f'a = {ids.a} is out of range.'";
pub const VERIFY_ECDSA_SIGNATURE = "ecdsa_builtin.add_signature(ids.ecdsa_ptr.address_, (ids.signature_r, ids.signature_s))";
pub const IS_POSITIVE = "from starkware.cairo.common.math_utils import is_positive\nids.is_positive = 1 if is_positive(\n    value=ids.value, prime=PRIME, rc_bound=range_check_builtin.bound) else 0";
pub const ASSERT_NOT_ZERO = "from starkware.cairo.common.math_utils import assert_integer\nassert_integer(ids.value)\nassert ids.value % PRIME != 0, f'assert_not_zero failed: {ids.value} = 0.'";

pub const IS_QUAD_RESIDUE =
    \\from starkware.crypto.signature.signature import FIELD_PRIME
    \\from starkware.python.math_utils import div_mod, is_quad_residue, sqrt
    \\
    \\x = ids.x
    \\if is_quad_residue(x, FIELD_PRIME):
    \\    ids.y = sqrt(x, FIELD_PRIME)
    \\else:
    \\    ids.y = sqrt(div_mod(x, 3, FIELD_PRIME), FIELD_PRIME)
;

pub const ASSERT_NOT_EQUAL =
    \\from starkware.cairo.lang.vm.relocatable import RelocatableValue
    \\both_ints = isinstance(ids.a, int) and isinstance(ids.b, int)
    \\both_relocatable = (
    \\    isinstance(ids.a, RelocatableValue) and isinstance(ids.b, RelocatableValue) and
    \\    ids.a.segment_index == ids.b.segment_index)
    \\assert both_ints or both_relocatable, \
    \\    f'assert_not_equal failed: non-comparable values: {ids.a}, {ids.b}.'
    \\assert (ids.a - ids.b) % PRIME != 0, f'assert_not_equal failed: {ids.a} = {ids.b}.'
;

pub const SQRT =
    \\from starkware.python.math_utils import isqrt
    \\value = ids.value % PRIME
    \\assert value < 2 ** 250, f"value={value} is outside of the range [0, 2**250)."
    \\assert 2 ** 250 < PRIME
    \\ids.root = isqrt(value)
;

pub const UNSIGNED_DIV_REM =
    \\from starkware.cairo.common.math_utils import assert_integer
    \\assert_integer(ids.div)
    \\assert 0 < ids.div <= PRIME // range_check_builtin.bound, \
    \\    f'div={hex(ids.div)} is out of the valid range.'
    \\ids.q, ids.r = divmod(ids.value, ids.div)
;

pub const SIGNED_DIV_REM =
    \\from starkware.cairo.common.math_utils import as_int, assert_integer
    \\
    \\assert_integer(ids.div)
    \\assert 0 < ids.div <= PRIME // range_check_builtin.bound, \
    \\    f'div={hex(ids.div)} is out of the valid range.'
    \\
    \\assert_integer(ids.bound)
    \\assert ids.bound <= range_check_builtin.bound // 2, \
    \\    f'bound={hex(ids.bound)} is out of the valid range.'
    \\
    \\int_value = as_int(ids.value, PRIME)
    \\q, ids.r = divmod(int_value, ids.div)
    \\
    \\assert -ids.bound <= q < ids.bound, \
    \\    f'{int_value} / {ids.div} = {q} is out of the range [{-ids.bound}, {ids.bound}).'
    \\
    \\ids.biased_q = q + ids.bound
;

pub const ASSERT_LE_FELT =
    \\import itertools
    \\
    \\from starkware.cairo.common.math_utils import assert_integer
    \\assert_integer(ids.a)
    \\assert_integer(ids.b)
    \\a = ids.a % PRIME
    \\b = ids.b % PRIME
    \\assert a <= b, f'a = {a} is not less than or equal to b = {b}.'
    \\
    \\# Find an arc less than PRIME / 3, and another less than PRIME / 2.
    \\lengths_and_indices = [(a, 0), (b - a, 1), (PRIME - 1 - b, 2)]
    \\lengths_and_indices.sort()
    \\assert lengths_and_indices[0][0] <= PRIME // 3 and lengths_and_indices[1][0] <= PRIME // 2
    \\excluded = lengths_and_indices[2][1]
    \\
    \\memory[ids.range_check_ptr + 1], memory[ids.range_check_ptr + 0] = (
    \\    divmod(lengths_and_indices[0][0], ids.PRIME_OVER_3_HIGH))
    \\memory[ids.range_check_ptr + 3], memory[ids.range_check_ptr + 2] = (
    \\    divmod(lengths_and_indices[1][0], ids.PRIME_OVER_2_HIGH))
;

pub const ASSERT_LE_FELT_EXCLUDED_0 = "memory[ap] = 1 if excluded != 0 else 0";

pub const ASSERT_LE_FELT_EXCLUDED_1 = "memory[ap] = 1 if excluded != 1 else 0";

pub const ASSERT_LE_FELT_EXCLUDED_2 = "assert excluded == 2";

pub const ASSERT_LT_FELT =
    \\from starkware.cairo.common.math_utils import assert_integer
    \\assert_integer(ids.a)
    \\assert_integer(ids.b)
    \\assert (ids.a % PRIME) < (ids.b % PRIME), \
    \\    f'a = {ids.a % PRIME} is not less than b = {ids.b % PRIME}.'
;

pub const IS_250_BITS = "ids.is_250 = 1 if ids.addr < 2**250 else 0";

pub const ASSERT_250_BITS =
    \\from starkware.cairo.common.math_utils import as_int
    \\
    \\# Correctness check.
    \\value = as_int(ids.value, PRIME) % PRIME
    \\assert value < ids.UPPER_BOUND, f'{value} is outside of the range [0, 2**250).'
    \\
    \\# Calculation for the assertion.
    \\ids.high, ids.low = divmod(ids.value, ids.SHIFT)
;

pub const SPLIT_FELT =
    \\from starkware.cairo.common.math_utils import assert_integer
    \\assert ids.MAX_HIGH < 2**128 and ids.MAX_LOW < 2**128
    \\assert PRIME - 1 == ids.MAX_HIGH * 2**128 + ids.MAX_LOW
    \\assert_integer(ids.value)
    \\ids.low = ids.value & ((1 << 128) - 1)
    \\ids.high = ids.value >> 128
;

pub const SPLIT_INT = "memory[ids.output] = res = (int(ids.value) % PRIME) % ids.base\nassert res < ids.bound, f'split_int(): Limb {res} is out of range.'";

pub const SPLIT_INT_ASSERT_RANGE = "assert ids.value == 0, 'split_int(): value is out of range.'";

pub const ADD_SEGMENT = "memory[ap] = segments.add()";

pub const VM_ENTER_SCOPE = "vm_enter_scope()";
pub const VM_EXIT_SCOPE = "vm_exit_scope()";

pub const MEMCPY_ENTER_SCOPE = "vm_enter_scope({'n': ids.len})";
pub const NONDET_N_GREATER_THAN_10 = "memory[ap] = to_felt_or_relocatable(ids.n >= 10)";
pub const NONDET_N_GREATER_THAN_2 = "memory[ap] = to_felt_or_relocatable(ids.n >= 2)";

pub const UNSAFE_KECCAK =
    \\from eth_hash.auto import keccak
    \\
    \\data, length = ids.data, ids.length
    \\
    \\if '__keccak_max_size' in globals():
    \\    assert length <= __keccak_max_size, \
    \\        f'unsafe_keccak() can only be used with length<={__keccak_max_size}. ' \
    \\        f'Got: length={length}.'
    \\
    \\keccak_input = bytearray()
    \\for word_i, byte_i in enumerate(range(0, length, 16)):
    \\    word = memory[data + word_i]
    \\    n_bytes = min(16, length - byte_i)
    \\    assert 0 <= word < 2 ** (8 * n_bytes)
    \\    keccak_input += word.to_bytes(n_bytes, 'big')
    \\
    \\hashed = keccak(keccak_input)
    \\ids.high = int.from_bytes(hashed[:16], 'big')
    \\ids.low = int.from_bytes(hashed[16:32], 'big')
;

pub const UNSAFE_KECCAK_FINALIZE =
    \\from eth_hash.auto import keccak
    \\keccak_input = bytearray()
    \\n_elms = ids.keccak_state.end_ptr - ids.keccak_state.start_ptr
    \\for word in memory.get_range(ids.keccak_state.start_ptr, n_elms):
    \\    keccak_input += word.to_bytes(16, 'big')
    \\hashed = keccak(keccak_input)
    \\ids.high = int.from_bytes(hashed[:16], 'big')
    \\ids.low = int.from_bytes(hashed[16:32], 'big')
;

pub const SPLIT_INPUT_3 = "ids.high3, ids.low3 = divmod(memory[ids.inputs + 3], 256)";
pub const SPLIT_INPUT_6 = "ids.high6, ids.low6 = divmod(memory[ids.inputs + 6], 256 ** 2)";
pub const SPLIT_INPUT_9 = "ids.high9, ids.low9 = divmod(memory[ids.inputs + 9], 256 ** 3)";
pub const SPLIT_INPUT_12 =
    "ids.high12, ids.low12 = divmod(memory[ids.inputs + 12], 256 ** 4)";
pub const SPLIT_INPUT_15 =
    "ids.high15, ids.low15 = divmod(memory[ids.inputs + 15], 256 ** 5)";

pub const SPLIT_OUTPUT_0 =
    \\ids.output0_low = ids.output0 & ((1 << 128) - 1)
    \\ids.output0_high = ids.output0 >> 128
;
pub const SPLIT_OUTPUT_1 =
    \\ids.output1_low = ids.output1 & ((1 << 128) - 1)
    \\ids.output1_high = ids.output1 >> 128
;

pub const SPLIT_N_BYTES = "ids.n_words_to_copy, ids.n_bytes_left = divmod(ids.n_bytes, ids.BYTES_IN_WORD)";
pub const SPLIT_OUTPUT_MID_LOW_HIGH =
    \\tmp, ids.output1_low = divmod(ids.output1, 256 ** 7)
    \\ids.output1_high, ids.output1_mid = divmod(tmp, 2 ** 128)
;

pub const BIGINT_TO_UINT256 = "ids.low = (ids.x.d0 + ids.x.d1 * ids.BASE) & ((1 << 128) - 1)";
pub const UINT256_ADD =
    \\sum_low = ids.a.low + ids.b.low
    \\ids.carry_low = 1 if sum_low >= ids.SHIFT else 0
    \\sum_high = ids.a.high + ids.b.high + ids.carry_low
    \\ids.carry_high = 1 if sum_high >= ids.SHIFT else 0
;

pub const UINT256_ADD_LOW =
    \\sum_low = ids.a.low + ids.b.low
    \\ids.carry_low = 1 if sum_low >= ids.SHIFT else 0
;

pub const UINT128_ADD =
    \\res = ids.a + ids.b
    \\ids.carry = 1 if res >= ids.SHIFT else 0
;

pub const UINT256_SUB =
    \\def split(num: int, num_bits_shift: int = 128, length: int = 2):
    \\    a = []
    \\    for _ in range(length):
    \\        a.append( num & ((1 << num_bits_shift) - 1) )
    \\        num = num >> num_bits_shift
    \\    return tuple(a)
    \\
    \\def pack(z, num_bits_shift: int = 128) -> int:
    \\    limbs = (z.low, z.high)
    \\    return sum(limb << (num_bits_shift * i) for i, limb in enumerate(limbs))
    \\
    \\a = pack(ids.a)
    \\b = pack(ids.b)
    \\res = (a - b)%2**256
    \\res_split = split(res)
    \\ids.res.low = res_split[0]
    \\ids.res.high = res_split[1]
;

pub const UINT256_SQRT =
    \\from starkware.python.math_utils import isqrt
    \\n = (ids.n.high << 128) + ids.n.low
    \\root = isqrt(n)
    \\assert 0 <= root < 2 ** 128
    \\ids.root.low = root
    \\ids.root.high = 0
;

pub const UINT256_SQRT_FELT =
    \\from starkware.python.math_utils import isqrt
    \\n = (ids.n.high << 128) + ids.n.low
    \\root = isqrt(n)
    \\assert 0 <= root < 2 ** 128
    \\ids.root = root
;

pub const UINT256_SIGNED_NN = "memory[ap] = 1 if 0 <= (ids.a.high % PRIME) < 2 ** 127 else 0";

pub const UINT256_UNSIGNED_DIV_REM =
    \\a = (ids.a.high << 128) + ids.a.low
    \\div = (ids.div.high << 128) + ids.div.low
    \\quotient, remainder = divmod(a, div)
    \\
    \\ids.quotient.low = quotient & ((1 << 128) - 1)
    \\ids.quotient.high = quotient >> 128
    \\ids.remainder.low = remainder & ((1 << 128) - 1)
    \\ids.remainder.high = remainder >> 128
;

pub const UINT256_EXPANDED_UNSIGNED_DIV_REM =
    \\a = (ids.a.high << 128) + ids.a.low
    \\div = (ids.div.b23 << 128) + ids.div.b01
    \\quotient, remainder = divmod(a, div)
    \\
    \\ids.quotient.low = quotient & ((1 << 128) - 1)
    \\ids.quotient.high = quotient >> 128
    \\ids.remainder.low = remainder & ((1 << 128) - 1)
    \\ids.remainder.high = remainder >> 128
;

pub const UINT256_MUL_DIV_MOD =
    \\a = (ids.a.high << 128) + ids.a.low
    \\b = (ids.b.high << 128) + ids.b.low
    \\div = (ids.div.high << 128) + ids.div.low
    \\quotient, remainder = divmod(a * b, div)
    \\
    \\ids.quotient_low.low = quotient & ((1 << 128) - 1)
    \\ids.quotient_low.high = (quotient >> 128) & ((1 << 128) - 1)
    \\ids.quotient_high.low = (quotient >> 256) & ((1 << 128) - 1)
    \\ids.quotient_high.high = quotient >> 384
    \\ids.remainder.low = remainder & ((1 << 128) - 1)
    \\ids.remainder.high = remainder >> 128
;

pub const SPLIT_64 =
    \\ids.low = ids.a & ((1<<64) - 1)
    \\ids.high = ids.a >> 64
;

pub const USORT_ENTER_SCOPE =
    "vm_enter_scope(dict(__usort_max_size = globals().get('__usort_max_size')))";
pub const USORT_BODY =
    \\from collections import defaultdict
    \\
    \\input_ptr = ids.input
    \\input_len = int(ids.input_len)
    \\if __usort_max_size is not None:
    \\    assert input_len <= __usort_max_size, (
    \\        f"usort() can only be used with input_len<={__usort_max_size}. "
    \\        f"Got: input_len={input_len}."
    \\    )
    \\
    \\positions_dict = defaultdict(list)
    \\for i in range(input_len):
    \\    val = memory[input_ptr + i]
    \\    positions_dict[val].append(i)
    \\
    \\output = sorted(positions_dict.keys())
    \\ids.output_len = len(output)
    \\ids.output = segments.gen_arg(output)
    \\ids.multiplicities = segments.gen_arg([len(positions_dict[k]) for k in output])
;

pub const USORT_VERIFY =
    \\last_pos = 0
    \\positions = positions_dict[ids.value][::-1]
;

pub const USORT_VERIFY_MULTIPLICITY_ASSERT = "assert len(positions) == 0";
pub const USORT_VERIFY_MULTIPLICITY_BODY =
    \\current_pos = positions.pop()
    \\ids.next_item_index = current_pos - last_pos
    \\last_pos = current_pos + 1
;

pub const MEMSET_ENTER_SCOPE = "vm_enter_scope({'n': ids.n})";
pub const MEMSET_CONTINUE_LOOP =
    \\n -= 1
    \\ids.continue_loop = 1 if n > 0 else 0
;

pub const MEMCPY_CONTINUE_COPYING =
    \\n -= 1
    \\ids.continue_copying = 1 if n > 0 else 0
;

pub const DEFAULT_DICT_NEW =
    \\if '__dict_manager' not in globals():
    \\    from starkware.cairo.common.dict import DictManager
    \\    __dict_manager = DictManager()
    \\
    \\memory[ap] = __dict_manager.new_default_dict(segments, ids.default_value)
;

pub const DICT_NEW =
    \\if '__dict_manager' not in globals():
    \\    from starkware.cairo.common.dict import DictManager
    \\    __dict_manager = DictManager()
    \\
    \\memory[ap] = __dict_manager.new_dict(segments, initial_dict)
    \\del initial_dict
;

pub const DICT_READ =
    \\dict_tracker = __dict_manager.get_tracker(ids.dict_ptr)
    \\dict_tracker.current_ptr += ids.DictAccess.SIZE
    \\ids.value = dict_tracker.data[ids.key]
;

pub const DICT_WRITE =
    \\dict_tracker = __dict_manager.get_tracker(ids.dict_ptr)
    \\dict_tracker.current_ptr += ids.DictAccess.SIZE
    \\ids.dict_ptr.prev_value = dict_tracker.data[ids.key]
    \\dict_tracker.data[ids.key] = ids.new_value
;

pub const DICT_UPDATE =
    \\# Verify dict pointer and prev value.
    \\dict_tracker = __dict_manager.get_tracker(ids.dict_ptr)
    \\current_value = dict_tracker.data[ids.key]
    \\assert current_value == ids.prev_value, \
    \\    f'Wrong previous value in dict. Got {ids.prev_value}, expected {current_value}.'
    \\
    \\# Update value.
    \\dict_tracker.data[ids.key] = ids.new_value
    \\dict_tracker.current_ptr += ids.DictAccess.SIZE
;

pub const SQUASH_DICT =
    \\dict_access_size = ids.DictAccess.SIZE
    \\address = ids.dict_accesses.address_
    \\assert ids.ptr_diff % dict_access_size == 0, \
    \\    'Accesses array size must be divisible by DictAccess.SIZE'
    \\n_accesses = ids.n_accesses
    \\if '__squash_dict_max_size' in globals():
    \\    assert n_accesses <= __squash_dict_max_size, \
    \\        f'squash_dict() can only be used with n_accesses<={__squash_dict_max_size}. ' \
    \\        f'Got: n_accesses={n_accesses}.'
    \\# A map from key to the list of indices accessing it.
    \\access_indices = {}
    \\for i in range(n_accesses):
    \\    key = memory[address + dict_access_size * i]
    \\    access_indices.setdefault(key, []).append(i)
    \\# Descending list of keys.
    \\keys = sorted(access_indices.keys(), reverse=True)
    \\# Are the keys used bigger than range_check bound.
    \\ids.big_keys = 1 if keys[0] >= range_check_builtin.bound else 0
    \\ids.first_key = key = keys.pop()
;

pub const SQUASH_DICT_INNER_SKIP_LOOP =
    "ids.should_skip_loop = 0 if current_access_indices else 1";
pub const SQUASH_DICT_INNER_FIRST_ITERATION =
    \\current_access_indices = sorted(access_indices[key])[::-1]
    \\current_access_index = current_access_indices.pop()
    \\memory[ids.range_check_ptr] = current_access_index
;

pub const SQUASH_DICT_INNER_CHECK_ACCESS_INDEX =
    \\new_access_index = current_access_indices.pop()
    \\ids.loop_temps.index_delta_minus1 = new_access_index - current_access_index - 1
    \\current_access_index = new_access_index
;

pub const SQUASH_DICT_INNER_CONTINUE_LOOP =
    "ids.loop_temps.should_continue = 1 if current_access_indices else 0";
pub const SQUASH_DICT_INNER_ASSERT_LEN_KEYS = "assert len(keys) == 0";
pub const SQUASH_DICT_INNER_LEN_ASSERT = "assert len(current_access_indices) == 0";
pub const SQUASH_DICT_INNER_USED_ACCESSES_ASSERT =
    "assert ids.n_used_accesses == len(access_indices[key])";
pub const SQUASH_DICT_INNER_NEXT_KEY =
    \\assert len(keys) > 0, 'No keys left but remaining_accesses > 0.'
    \\ids.next_key = key = keys.pop()
;

pub const DICT_SQUASH_UPDATE_PTR =
    \\# Update the DictTracker's current_ptr to point to the end of the squashed dict.
    \\__dict_manager.get_tracker(ids.squashed_dict_start).current_ptr = \
    \\    ids.squashed_dict_end.address_
;

pub const DICT_SQUASH_COPY_DICT =
    \\# Prepare arguments for dict_new. In particular, the same dictionary values should be copied
    \\# to the new (squashed) dictionary.
    \\vm_enter_scope({
    \\    # Make __dict_manager accessible.
    \\    '__dict_manager': __dict_manager,
    \\    # Create a copy of the dict, in case it changes in the future.
    \\    'initial_dict': dict(__dict_manager.get_dict(ids.dict_accesses_end)),
    \\})
;

pub const BLOCK_PERMUTATION =
    \\from starkware.cairo.common.keccak_utils.keccak_utils import keccak_func
    \\_keccak_state_size_felts = int(ids.KECCAK_STATE_SIZE_FELTS)
    \\assert 0 <= _keccak_state_size_felts < 100
    \\
    \\output_values = keccak_func(memory.get_range(
    \\    ids.keccak_ptr - _keccak_state_size_felts, _keccak_state_size_felts))
    \\segments.write_arg(ids.keccak_ptr, output_values)
;

// The 0.10.3 whitelist uses this variant (instead of the one used by the common library), but both hints have the same behaviour
// We should check for future refactors that may discard one of the variants
pub const BLOCK_PERMUTATION_WHITELIST_V1 =
    \\from starkware.cairo.common.cairo_keccak.keccak_utils import keccak_func
    \\_keccak_state_size_felts = int(ids.KECCAK_STATE_SIZE_FELTS)
    \\assert 0 <= _keccak_state_size_felts < 100
    \\
    \\output_values = keccak_func(memory.get_range(
    \\    ids.keccak_ptr - _keccak_state_size_felts, _keccak_state_size_felts))
    \\segments.write_arg(ids.keccak_ptr, output_values)
;

pub const BLOCK_PERMUTATION_WHITELIST_V2 =
    \\from starkware.cairo.common.cairo_keccak.keccak_utils import keccak_func
    \\_keccak_state_size_felts = int(ids.KECCAK_STATE_SIZE_FELTS)
    \\assert 0 <= _keccak_state_size_felts < 100
    \\output_values = keccak_func(memory.get_range(
    \\    ids.keccak_ptr_start, _keccak_state_size_felts))
    \\segments.write_arg(ids.output, output_values)
;

pub const KECCAK_WRITE_ARGS =
    \\segments.write_arg(ids.inputs, [ids.low % 2 ** 64, ids.low // 2 ** 64])
    \\segments.write_arg(ids.inputs + 2, [ids.high % 2 ** 64, ids.high // 2 ** 64])
;

pub const COMPARE_BYTES_IN_WORD_NONDET =
    "memory[ap] = to_felt_or_relocatable(ids.n_bytes < ids.BYTES_IN_WORD)";

pub const COMPARE_KECCAK_FULL_RATE_IN_BYTES_NONDET =
    "memory[ap] = to_felt_or_relocatable(ids.n_bytes >= ids.KECCAK_FULL_RATE_IN_BYTES)";

pub const CAIRO_KECCAK_INPUT_IS_FULL_WORD = "ids.full_word = int(ids.n_bytes >= 8)";

pub const CAIRO_KECCAK_FINALIZE_V1 =
    \\# Add dummy pairs of input and output.
    \\_keccak_state_size_felts = int(ids.KECCAK_STATE_SIZE_FELTS)
    \\_block_size = int(ids.BLOCK_SIZE)
    \\assert 0 <= _keccak_state_size_felts < 100
    \\assert 0 <= _block_size < 10
    \\inp = [0] * _keccak_state_size_felts
    \\padding = (inp + keccak_func(inp)) * _block_size
    \\segments.write_arg(ids.keccak_ptr_end, padding)
;

pub const CAIRO_KECCAK_FINALIZE_V2 =
    \\# Add dummy pairs of input and output.
    \\_keccak_state_size_felts = int(ids.KECCAK_STATE_SIZE_FELTS)
    \\_block_size = int(ids.BLOCK_SIZE)
    \\assert 0 <= _keccak_state_size_felts < 100
    \\assert 0 <= _block_size < 1000
    \\inp = [0] * _keccak_state_size_felts
    \\padding = (inp + keccak_func(inp)) * _block_size
    \\segments.write_arg(ids.keccak_ptr_end, padding)
;

pub const IS_NN = "memory[ap] = 0 if 0 <= (ids.a % PRIME) < range_check_builtin.bound else 1";

pub const IS_NN_OUT_OF_RANGE = "memory[ap] = 0 if 0 <= ((-ids.a - 1) % PRIME) < range_check_builtin.bound else 1";

pub const ASSERT_LE_FELT_V_0_6 =
    \\from starkware.cairo.common.math_utils import assert_integer
    \\assert_integer(ids.a)
    \\assert_integer(ids.b)
    \\assert (ids.a % PRIME) <= (ids.b % PRIME), \
    \\    f'a = {ids.a % PRIME} is not less than or equal to b = {ids.b % PRIME}.'
;

pub const ASSERT_LE_FELT_V_0_8 =
    \\from starkware.cairo.common.math_utils import assert_integer
    \\assert_integer(ids.a)
    \\assert_integer(ids.b)
    \\a = ids.a % PRIME
    \\b = ids.b % PRIME
    \\assert a <= b, f'a = {a} is not less than or equal to b = {b}.'
    \\
    \\ids.small_inputs = int(
    \\    a < range_check_builtin.bound and (b - a) < range_check_builtin.bound)
;

pub const A_B_BITAND_1 =
    \\ids.a_lsb = ids.a & 1
    \\ids.b_lsb = ids.b & 1
;

pub const IS_LE_FELT = "memory[ap] = 0 if (ids.a % PRIME) <= (ids.b % PRIME) else 1";

pub const IS_ADDR_BOUNDED =
    \\# Verify the assumptions on the relationship between 2**250, ADDR_BOUND and PRIME.
    \\ADDR_BOUND = ids.ADDR_BOUND % PRIME
    \\assert (2**250 < ADDR_BOUND <= 2**251) and (2 * 2**250 < PRIME) and (
    \\        ADDR_BOUND * 2 > PRIME), \
    \\    'normalize_address() cannot be used with the current constants.'
    \\ids.is_small = 1 if ids.addr < ADDR_BOUND else 0
;

pub const SPLIT_XX =
    \\PRIME = 2**255 - 19
    \\II = pow(2, (PRIME - 1) // 4, PRIME)
    \\
    \\xx = ids.xx.low + (ids.xx.high<<128)
    \\x = pow(xx, (PRIME + 3) // 8, PRIME)
    \\if (x * x - xx) % PRIME != 0:
    \\    x = (x * II) % PRIME
    \\if x % 2 != 0:
    \\    x = PRIME - x
    \\ids.x.low = x & ((1<<128)-1)
    \\ids.x.high = x >> 128
;

pub const PRINT_ARR =
    \\print(bytes.fromhex(f"{ids.name:062x}").decode().replace('\x00',''))
    \\arr = [memory[ids.arr + i] for i in range(ids.arr_len)]
    \\print(arr)
;

pub const PRINT_FELT =
    \\print(ids.x)
;

pub const PRINT_DICT =
    \\print(bytes.fromhex(f"{ids.name:062x}").decode().replace('\x00',''))
    \\data = __dict_manager.get_dict(ids.dict_ptr)
    \\print(
    \\    {k: v if isinstance(v, int) else [memory[v + i] for i in range(ids.pointer_size)] for k, v in data.items()}
    \\)
;
