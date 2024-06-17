func a{}() -> (b: felt) {
    return (5,);
}

func main{}() {
    a();
    if ([ap - 1] == 5) {
        a();
    }

    if ([ap - 1] == 0) {
        [ap] = 1, ap++;
        [ap] = 1;
    }
    ret;
}
