func main() {
    [ap + 0] = 11, ap++;
    [ap + 0] = 1000, ap++;
    [ap - 1] = [ap + 0] * [ap - 2], ap++;

    [ap + 0] = 1, ap++;
    [ap + 0] = 2, ap++;
    [ap - 2] = [ap + 0] * [ap - 1], ap++;

    return ();
}
