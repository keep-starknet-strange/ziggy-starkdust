// factorial(n) =  n!
func factorial(n) -> (result: felt) {
    if (n == 1) {
        return (n,);
    }
    let (a) = factorial(n - 1);
    return (n * a,);
}

func main() {
    // Make sure the factorial(10) == 3628800
    let (y) = factorial(10);
    y = 3628800;
    return ();
}
