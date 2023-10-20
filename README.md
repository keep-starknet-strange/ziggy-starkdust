<p align="center">
  <img src="https://github.com/keep-starknet-strange/cairo-zig/blob/main/docs/kit/logo/starknet-zig-logo.png?raw=true" alt="Logo"/>
  <h1 align="center">cairo-zig</h1>
</p>

<div align="center">
<br />

[![GitHub Workflow Status](https://github.com/keep-starknet-strange/cairo-zig/actions/workflows/test.yml/badge.svg)](https://github.com/keep-starknet-strange/cairo-zig/actions/workflows/test.yml)
[![Project license](https://img.shields.io/github/license/keep-starknet-strange/cairo-zig.svg?style=flat-square)](LICENSE)
[![Pull Requests welcome](https://img.shields.io/badge/PRs-welcome-ff69b4.svg?style=flat-square)](https://github.com/keep-starknet-strange/cairo-zig/issues?q=is%3Aissue+is%3Aopen+label%3A%22help+wanted%22)

</div>

> _Note that `cairo-zig` is still experimental. Breaking changes will be made before the first stable release. The library is also NOT audited or reviewed for security at the moment. Use at your own risk._

## 📦 Installation

### 📋 Prerequisites

- [Zig](https://ziglang.org/)

## 🔧 Build

```bash
zig build
```

## 🤖 Usage

You can display the help message by running:

```bash
./zig-out/bin/cairo-zig --help
```

```text
cairo-zig
Version: 0.0.1
Author: StarkWare & Contributors

USAGE:
  cairo-zig [OPTIONS]

Cairo Virtual Machine written in Zig.
Highly experimental, use at your own risk.

COMMANDS:
  execute   Execute a cairo program.

OPTIONS:
  -h, --help   Prints help information
```

### Run a cairo program

```
./zig-out/bin/cairo-zig execute --proof-mode=false
```

### 🧪 Testing

```bash
zig build test --summary all
```

## 🔤 TODOs

- [ ] Add test coverage (investigate using [kcov](https://github.com/SimonKagstrom/kcov), [code coverage for zig article](https://zig.news/squeek502/code-coverage-for-zig-1dk1)).
- [ ] Benchmark performances.
- [ ] Enable usage as a library.
- [ ] Fuzzing.
- [ ] Differential testing against Cairo VM in Rust.
- [ ] Memory leaks detection (i.e use tools like [valgrind](https://valgrind.org/)).
- [ ] Check [Zig style guide](https://ziglang.org/documentation/master/#Style-Guide) and apply it.
- [ ] Create documentation.

## 📄 License

This project is licensed under the MIT license.

See [LICENSE](LICENSE) for more information.

Happy coding! 🎉

## 📚 Resources

Here are some resources to help you get started:

- [Cairo Whitepaper](https://eprint.iacr.org/2021/1063.pdf)
- [Cairo VM in Rust](https://github.com/lambdaclass/cairo-vm)
- [Cairo VM in Go](https://github.com/lambdaclass/cairo-vm_in_go)

## 🙏 Acknowledgments

- The structure of the project and some initial code related to prime field functions is based on [verkle-cryto](https://github.com/jsign/verkle-crypto) repository by [jsign](https://github.com/jsign).
- The design of the Cairo VM is inspired by [Cairo VM in Rust](https://github.com/lambdaclass/cairo-vm) and [Cairo VM in Go](https://github.com/lambdaclass/cairo-vm_in_go) by [lambdaclass](https://lambdaclass.com/).
- Some cryptographic primitive code generation has been done using the amazing [fiat-crypto](https://github.com/mit-plv/fiat-crypto) by [mit-plv](https://github.com/mit-plv).
- [sig](https://github.com/Syndica/sig) has been a great source of inspiration for the project structure and the way to use Zig.
- [nektro](https://github.com/nektro/) for the [zig-time](https://github.com/nektro/zig-time) library.
