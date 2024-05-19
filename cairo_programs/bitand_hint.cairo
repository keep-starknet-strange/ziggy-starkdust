func main() {
    alloc_locals;
    let a = 7;
    let b = 999;

    local a_lsb;
    local b_lsb;

    %{
       ids.a_lsb = ids.a & 1
       ids.b_lsb = ids.b & 1
   %}

    assert a_lsb = 1;
    assert b_lsb = 1;

    return();
}
