# cairo-zig

## 📝 Description

Cairo VM in Zig ♒.

## TODOs

- [ ] Benchmark performances
- [ ] Enable usage as a library
- [ ] Fuzzing
- [ ] Differential testing against Cairo VM in Rust

## 📦 Installation

### 📋 Prerequisites

- [Zig](https://ziglang.org/)

## Usage

```bash
zig build run
```

### 🛠️ Testing

```bash
zig build test --summary all
```

## 📄 License

This project is licensed under the MIT license.

See [LICENSE](LICENSE) for more information.

Happy coding! 🎉

## Acknowledgments

- The structure of the project and some initial code is based on [verkle-cryto](https://github.com/jsign/verkle-crypto) repository by [jsign](https://github.com/jsign).
- The design of the Cairo VM is inspired by [Cairo VM in Rust](https://github.com/lambdaclass/cairo-vm) and [Cairo VM in Go](https://github.com/lambdaclass/cairo-vm_in_go) by [lambdaclass](https://lambdaclass.com/).
- Some cryptographic primitive code generation has been done using the amazing [fiat-crypto](https://github.com/mit-plv/fiat-crypto) by [mit-plv](https://github.com/mit-plv).

## 📚 Resources

Here are some resources to help you get started:

- [Cairo Whitepaper](https://eprint.iacr.org/2021/1063.pdf)
- [Cairo VM in Rust](https://github.com/lambdaclass/cairo-vm)
- [Cairo VM in Go](https://github.com/lambdaclass/cairo-vm_in_go)
