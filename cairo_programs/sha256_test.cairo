%builtins range_check bitwise

from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin
from starkware.cairo.common.registers import get_label_location
from starkware.cairo.common.invoke import invoke
from starkware.cairo.common.alloc import alloc

from cairo_programs.sha256 import sha256, finalize_sha256

// Taken from https://github.com/cartridge-gg/cairo-sha256/blob/8d2ae515ab5cc9fc530c2dcf3ed1172bd181136e/tests/test_sha256.cairo
func test_sha256_hello_world{bitwise_ptr: BitwiseBuiltin*, range_check_ptr}() {
    alloc_locals;

    let (hello_world) = alloc();
    assert hello_world[0] = 'hell';
    assert hello_world[1] = 'o wo';
    assert hello_world[2] = 'rld\x00';

    let (local sha256_ptr: felt*) = alloc();
    let sha256_ptr_start = sha256_ptr;
    let (hash) = sha256{sha256_ptr=sha256_ptr}(hello_world, 11);
    finalize_sha256(sha256_ptr_start=sha256_ptr_start, sha256_ptr_end=sha256_ptr);

    assert hash[0] = 3108841401;
    assert hash[1] = 2471312904;
    assert hash[2] = 2771276503;
    assert hash[3] = 3665669114;
    assert hash[4] = 3297046499;
    assert hash[5] = 2052292846;
    assert hash[6] = 2424895404;
    assert hash[7] = 3807366633;

    return ();
}

func test_sha256_multichunks{bitwise_ptr: BitwiseBuiltin*, range_check_ptr}() {
    alloc_locals;

    let (phrase) = alloc();
    // phrase="this is an example message which should take multiple chunks"
    // 01110100 01101000 01101001 01110011
    assert phrase[0] = 1952999795;
    // 00100000 01101001 01110011 00100000
    assert phrase[1] = 543781664;
    // 01100001 01101110 00100000 01100101
    assert phrase[2] = 1634607205;
    // 01111000 01100001 01101101 01110000
    assert phrase[3] = 2019650928;
    // 01101100 01100101 00100000 01101101
    assert phrase[4] = 1818566765;
    // 01100101 01110011 01110011 01100001
    assert phrase[5] = 1702064993;
    // 01100111 01100101 00100000 01110111
    assert phrase[6] = 1734680695;
    // 01101000 01101001 01100011 01101000
    assert phrase[7] = 1751737192;
    // 00100000 01110011 01101000 01101111
    assert phrase[8] = 544434287;
    // 01110101 01101100 01100100 00100000
    assert phrase[9] = 1970037792;
    // 01110100 01100001 01101011 01100101
    assert phrase[10] = 1952541541;
    // 00100000 01101101 01110101 01101100
    assert phrase[11] = 544044396;
    // 01110100 01101001 01110000 01101100
    assert phrase[12] = 1953067116;
    // 01100101 00100000 01100011 01101000
    assert phrase[13] = 1696621416;
    // 01110101 01101110 01101011 01110011
    assert phrase[14] = 1970170739;

    let (local sha256_ptr: felt*) = alloc();
    let sha256_ptr_start = sha256_ptr;
    let (hash) = sha256{sha256_ptr=sha256_ptr}(phrase, 60);
    finalize_sha256(sha256_ptr_start=sha256_ptr_start, sha256_ptr_end=sha256_ptr);

    assert hash[0] = 3714276112;
    assert hash[1] = 759782134;
    assert hash[2] = 1331117438;
    assert hash[3] = 1287649296;
    assert hash[4] = 699003633;
    assert hash[5] = 2214481798;
    assert hash[6] = 3208491254;
    assert hash[7] = 789740750;

    return ();
}

// test vectors from: https://www.di-mgt.com.au/sha_testvectors.html

func test_sha256_0bits{bitwise_ptr: BitwiseBuiltin*, range_check_ptr}() {
    alloc_locals;

    let (empty) = alloc();
    let (local sha256_ptr: felt*) = alloc();
    let sha256_ptr_start = sha256_ptr;
    let (hash) = sha256{sha256_ptr=sha256_ptr}(empty, 0);
    finalize_sha256(sha256_ptr_start=sha256_ptr_start, sha256_ptr_end=sha256_ptr);

    assert hash[0] = 0xe3b0c442;
    assert hash[1] = 0x98fc1c14;
    assert hash[2] = 0x9afbf4c8;
    assert hash[3] = 0x996fb924;
    assert hash[4] = 0x27ae41e4;
    assert hash[5] = 0x649b934c;
    assert hash[6] = 0xa495991b;
    assert hash[7] = 0x7852b855;

    return ();
}

func test_sha256_24bits{bitwise_ptr: BitwiseBuiltin*, range_check_ptr}() {
    alloc_locals;

    let (local sha256_ptr: felt*) = alloc();
    let sha256_ptr_start = sha256_ptr;
    let (hash) = sha256{sha256_ptr=sha256_ptr}(new ('abc\x00'), 3);
    finalize_sha256(sha256_ptr_start=sha256_ptr_start, sha256_ptr_end=sha256_ptr);

    assert hash[0] = 0xba7816bf;
    assert hash[1] = 0x8f01cfea;
    assert hash[2] = 0x414140de;
    assert hash[3] = 0x5dae2223;
    assert hash[4] = 0xb00361a3;
    assert hash[5] = 0x96177a9c;
    assert hash[6] = 0xb410ff61;
    assert hash[7] = 0xf20015ad;

    return ();
}

func test_sha256_448bits{bitwise_ptr: BitwiseBuiltin*, range_check_ptr}() {
    alloc_locals;

    let (input) = alloc();
    assert input[0] = 'abcd';
    assert input[1] = 'bcde';
    assert input[2] = 'cdef';
    assert input[3] = 'defg';
    assert input[4] = 'efgh';
    assert input[5] = 'fghi';
    assert input[6] = 'ghij';
    assert input[7] = 'hijk';
    assert input[8] = 'ijkl';
    assert input[9] = 'jklm';
    assert input[10] = 'klmn';
    assert input[11] = 'lmno';
    assert input[12] = 'mnop';
    assert input[13] = 'nopq';

    let (local sha256_ptr: felt*) = alloc();
    let sha256_ptr_start = sha256_ptr;
    let (hash) = sha256{sha256_ptr=sha256_ptr}(input, 56);
    finalize_sha256(sha256_ptr_start=sha256_ptr_start, sha256_ptr_end=sha256_ptr);

    assert hash[0] = 0x248d6a61;
    assert hash[1] = 0xd20638b8;
    assert hash[2] = 0xe5c02693;
    assert hash[3] = 0x0c3e6039;
    assert hash[4] = 0xa33ce459;
    assert hash[5] = 0x64ff2167;
    assert hash[6] = 0xf6ecedd4;
    assert hash[7] = 0x19db06c1;

    return ();
}

func test_sha256_504bits{bitwise_ptr: BitwiseBuiltin*, range_check_ptr}() {
    alloc_locals;
    // Input String: "0000111122223333444455556666777788889999aaaabbbbccccddddeeeefff"
    let (input) = alloc();
    assert input[0] = '0000';
    assert input[1] = '1111';
    assert input[2] = '2222';
    assert input[3] = '3333';
    assert input[4] = '4444';
    assert input[5] = '5555';
    assert input[6] = '6666';
    assert input[7] = '7777';
    assert input[8] = '8888';
    assert input[9] = '9999';
    assert input[10] = 'aaaa';
    assert input[11] = 'bbbb';
    assert input[12] = 'cccc';
    assert input[13] = 'dddd';
    assert input[14] = 'eeee';
    assert input[15] = 'fff\x00';

    let (local sha256_ptr: felt*) = alloc();
    let sha256_ptr_start = sha256_ptr;
    let (hash) = sha256{sha256_ptr=sha256_ptr}(input, 63);
    finalize_sha256(sha256_ptr_start=sha256_ptr_start, sha256_ptr_end=sha256_ptr);

    // Resulting hash: 214072bf9da123ca5a8925edb05a6f071fc48fa66494d08513b9ba1b82df20cd
    assert hash[0] = 0x214072bf;
    assert hash[1] = 0x9da123ca;
    assert hash[2] = 0x5a8925ed;
    assert hash[3] = 0xb05a6f07;
    assert hash[4] = 0x1fc48fa6;
    assert hash[5] = 0x6494d085;
    assert hash[6] = 0x13b9ba1b;
    assert hash[7] = 0x82df20cd;

    return ();
}

func test_sha256_512bits{bitwise_ptr: BitwiseBuiltin*, range_check_ptr}() {
    alloc_locals;
    // Input String: "0000111122223333444455556666777788889999aaaabbbbccccddddeeeeffff"
    let (input) = alloc();
    assert input[0] = '0000';
    assert input[1] = '1111';
    assert input[2] = '2222';
    assert input[3] = '3333';
    assert input[4] = '4444';
    assert input[5] = '5555';
    assert input[6] = '6666';
    assert input[7] = '7777';
    assert input[8] = '8888';
    assert input[9] = '9999';
    assert input[10] = 'aaaa';
    assert input[11] = 'bbbb';
    assert input[12] = 'cccc';
    assert input[13] = 'dddd';
    assert input[14] = 'eeee';
    assert input[15] = 'ffff';

    let (local sha256_ptr: felt*) = alloc();
    let sha256_ptr_start = sha256_ptr;
    let (hash) = sha256{sha256_ptr=sha256_ptr}(input, 64);
    finalize_sha256(sha256_ptr_start=sha256_ptr_start, sha256_ptr_end=sha256_ptr);

    // Resulting hash: c7a7d8c0472c7f6234380e9dd3a55eb24d3e5dba9d106b74a260dc787f2f6df8
    assert hash[0] = 0xc7a7d8c0;
    assert hash[1] = 0x472c7f62;
    assert hash[2] = 0x34380e9d;
    assert hash[3] = 0xd3a55eb2;
    assert hash[4] = 0x4d3e5dba;
    assert hash[5] = 0x9d106b74;
    assert hash[6] = 0xa260dc78;
    assert hash[7] = 0x7f2f6df8;

    return ();
}

func test_sha256_1024bits{bitwise_ptr: BitwiseBuiltin*, range_check_ptr}() {
    alloc_locals;
    // Input String: "0000111122223333444455556666777788889999aaaabbbbccccddddeeeeffff0000111122223333444455556666777788889999aaaabbbbccccddddeeeeffff"
    let (input) = alloc();
    assert input[0] = '0000';
    assert input[1] = '1111';
    assert input[2] = '2222';
    assert input[3] = '3333';
    assert input[4] = '4444';
    assert input[5] = '5555';
    assert input[6] = '6666';
    assert input[7] = '7777';
    assert input[8] = '8888';
    assert input[9] = '9999';
    assert input[10] = 'aaaa';
    assert input[11] = 'bbbb';
    assert input[12] = 'cccc';
    assert input[13] = 'dddd';
    assert input[14] = 'eeee';
    assert input[15] = 'ffff';
    assert input[16] = '0000';
    assert input[17] = '1111';
    assert input[18] = '2222';
    assert input[19] = '3333';
    assert input[20] = '4444';
    assert input[21] = '5555';
    assert input[22] = '6666';
    assert input[23] = '7777';
    assert input[24] = '8888';
    assert input[25] = '9999';
    assert input[26] = 'aaaa';
    assert input[27] = 'bbbb';
    assert input[28] = 'cccc';
    assert input[29] = 'dddd';
    assert input[30] = 'eeee';
    assert input[31] = 'ffff';

    let (local sha256_ptr: felt*) = alloc();
    let sha256_ptr_start = sha256_ptr;
    let (hash) = sha256{sha256_ptr=sha256_ptr}(input, 128);
    finalize_sha256(sha256_ptr_start=sha256_ptr_start, sha256_ptr_end=sha256_ptr);

    // Resulting hash: e324cc62be4f0465591b5cac1309ab4d5a9ee4ae8e99158c50cef7597898f046
    assert hash[0] = 0xe324cc62;
    assert hash[1] = 0xbe4f0465;
    assert hash[2] = 0x591b5cac;
    assert hash[3] = 0x1309ab4d;
    assert hash[4] = 0x5a9ee4ae;
    assert hash[5] = 0x8e99158c;
    assert hash[6] = 0x50cef759;
    assert hash[7] = 0x7898f046;

    return ();
}

func test_sha256_896bits{bitwise_ptr: BitwiseBuiltin*, range_check_ptr}() {
    alloc_locals;

    let (input) = alloc();
    assert input[0] = 'abcd';
    assert input[1] = 'efgh';
    assert input[2] = 'bcde';
    assert input[3] = 'fghi';
    assert input[4] = 'cdef';
    assert input[5] = 'ghij';
    assert input[6] = 'defg';
    assert input[7] = 'hijk';
    assert input[8] = 'efgh';
    assert input[9] = 'ijkl';
    assert input[10] = 'fghi';
    assert input[11] = 'jklm';
    assert input[12] = 'ghij';
    assert input[13] = 'klmn';
    assert input[14] = 'hijk';
    assert input[15] = 'lmno';
    assert input[16] = 'ijkl';
    assert input[17] = 'mnop';
    assert input[18] = 'jklm';
    assert input[19] = 'nopq';
    assert input[20] = 'klmn';
    assert input[21] = 'opqr';
    assert input[22] = 'lmno';
    assert input[23] = 'pqrs';
    assert input[24] = 'mnop';
    assert input[25] = 'qrst';
    assert input[26] = 'nopq';
    assert input[27] = 'rstu';

    let (local sha256_ptr: felt*) = alloc();
    let sha256_ptr_start = sha256_ptr;
    let (hash) = sha256{sha256_ptr=sha256_ptr}(input, 112);
    finalize_sha256(sha256_ptr_start=sha256_ptr_start, sha256_ptr_end=sha256_ptr);

    assert hash[0] = 0xcf5b16a7;
    assert hash[1] = 0x78af8380;
    assert hash[2] = 0x036ce59e;
    assert hash[3] = 0x7b049237;
    assert hash[4] = 0x0b249b11;
    assert hash[5] = 0xe8f07a51;
    assert hash[6] = 0xafac4503;
    assert hash[7] = 0x7afee9d1;

    return ();
}

func test_sha256_client_data{bitwise_ptr: BitwiseBuiltin*, range_check_ptr}() {
    alloc_locals;

    let (client_data_json) = alloc();
    assert client_data_json[0] = 2065855609;
    assert client_data_json[1] = 1885676090;
    assert client_data_json[2] = 578250082;
    assert client_data_json[3] = 1635087464;
    assert client_data_json[4] = 1848534885;
    assert client_data_json[5] = 1948396578;
    assert client_data_json[6] = 1667785068;
    assert client_data_json[7] = 1818586727;
    assert client_data_json[8] = 1696741922;
    assert client_data_json[9] = 813183028;
    assert client_data_json[10] = 879047521;
    assert client_data_json[11] = 1684224052;
    assert client_data_json[12] = 895825200;
    assert client_data_json[13] = 828518449;
    assert client_data_json[14] = 1664497968;
    assert client_data_json[15] = 878994482;
    assert client_data_json[16] = 1647338340;
    assert client_data_json[17] = 811872312;
    assert client_data_json[18] = 878862896;
    assert client_data_json[19] = 825373744;
    assert client_data_json[20] = 959854180;
    assert client_data_json[21] = 859398963;
    assert client_data_json[22] = 825636148;
    assert client_data_json[23] = 942761062;
    assert client_data_json[24] = 1667327286;
    assert client_data_json[25] = 896999980;
    assert client_data_json[26] = 577729129;
    assert client_data_json[27] = 1734962722;
    assert client_data_json[28] = 975333492;
    assert client_data_json[29] = 1953526586;
    assert client_data_json[30] = 791634799;
    assert client_data_json[31] = 1853125231;
    assert client_data_json[32] = 1819043186;
    assert client_data_json[33] = 761606451;
    assert client_data_json[34] = 1886665079;
    assert client_data_json[35] = 2004233840;
    assert client_data_json[36] = 1919252073;
    assert client_data_json[37] = 1702309475;
    assert client_data_json[38] = 1634890866;
    assert client_data_json[39] = 1768187749;
    assert client_data_json[40] = 778528546;
    assert client_data_json[41] = 740451186;
    assert client_data_json[42] = 1869837135;
    assert client_data_json[43] = 1919510377;
    assert client_data_json[44] = 1847736934;
    assert client_data_json[45] = 1634497381;
    assert client_data_json[46] = 2097152000;

    let (local sha256_ptr: felt*) = alloc();
    let sha256_ptr_start = sha256_ptr;
    let (hash) = sha256{sha256_ptr=sha256_ptr}(client_data_json, 185);
    finalize_sha256(sha256_ptr_start=sha256_ptr_start, sha256_ptr_end=sha256_ptr);

    assert hash[0] = 0x08ad1974;
    assert hash[1] = 0x216096a7;
    assert hash[2] = 0x6ff36a54;
    assert hash[3] = 0x159891a3;
    assert hash[4] = 0x57d21a90;
    assert hash[5] = 0x2c358e6f;
    assert hash[6] = 0xeb02f14c;
    assert hash[7] = 0xcaf48fcd;

    return ();
}

func main{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}() {
    test_sha256_hello_world();
    test_sha256_multichunks();
    test_sha256_0bits();
    test_sha256_24bits();
    test_sha256_448bits();
    test_sha256_504bits();
    test_sha256_512bits();
    test_sha256_1024bits();
    test_sha256_896bits();
    test_sha256_client_data();
    return ();
}
