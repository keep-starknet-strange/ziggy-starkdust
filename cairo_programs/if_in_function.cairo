func a{}() {
    [ap] = 5, ap++;

    if ([ap - 1] == 2) {
        [ap] = [ap - 1] + 3, ap++;
    } else {
        [ap] = 10, ap++;
    }
    ret;
}

func main{}() {
    a();

    ret;
}
