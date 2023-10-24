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

Alternatively, if you have [nix](https://nixos.org/) installed, you can get the full development environment `nix develop`.

## ⚡ Wanna learn Zig fast?

- [Zig language reference](https://ziglang.org/documentation/master/)
- [Zig Learn](https://ziglearn.org/)
- [Ziglings](https://ziglings.org/)

## 🔧 Build

```bash
zig build
```

## 🤖 Usage

You can display the help message by running:

```bash
./zig-out/bin/cairo-zig --help
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


## ⚡ Why Zig?

Choosing Zig for a third implementation of the Cairo VM brings several advantages, offering a unique blend of features not entirely covered by the existing Rust and Go implementations.

### 1. Simplicity and Readability

Zig aims for simplicity and clarity, enabling developers to read and understand the code quickly. It omits certain features like classes and exceptions to keep the language simple, which can be particularly useful for a VM where performance and maintainability are key.

### 2. Performance

Zig compiles to highly efficient native code, similar to Rust, making it an excellent choice for computationally-intensive tasks. The language's design gives the programmer direct control over memory and CPU, without unnecessary abstractions.

### 3. Explicit Control with Safety Features

Zig provides an environment where you have explicit control over memory allocation, similar to C and C++. While this does mean you're responsible for managing memory yourself, Zig offers certain safety features to catch common errors, like undefined behavior, during compile time or by providing runtime checks. This approach allows for a blend of performance and safety, making it a suitable choice for a VM where you often need fine-grained control.

### 4. C Interoperability

Zig offers first-class C interoperability without requiring any bindings or wrappers. This feature can be a game-changer for integrating with existing technologies.

### 5. Flexibility

Zig's comptime (compile-time) features offer powerful metaprogramming capabilities. This allows for expressive yet efficient code, as you can generate specialized routines at compile-time, reducing the need for runtime polymorphism.

### 6. Minimal Dependencies

Zig aims to reduce dependencies to a minimum, which could simplify the deployment and distribution of Cairo VM. This is particularly advantageous for systems that require high-reliability or have limited resources.

### 7. Community and Ecosystem

Although younger than Rust and Go, Zig's community is enthusiastic and rapidly growing. Adopting Zig at this stage means you can be a significant contributor to its ecosystem.

By choosing Zig for the third implementation of Cairo VM, we aim to leverage these features to build a high-performance, reliable, and maintainable virtual machine.


## 📄 License

This project is licensed under the MIT license.

See [LICENSE](LICENSE) for more information.

Happy coding! 🎉
## Contributors ✨

Thanks goes to these wonderful people ([emoji key](https://allcontributors.org/docs/en/emoji-key)):

<!-- ALL-CONTRIBUTORS-LIST:START - Do not remove or modify this section -->
<!-- prettier-ignore-start -->
<!-- markdownlint-disable -->
<table>
  <tbody>
    <tr>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/abdelhamidbakhta"><img src="https://avatars.githubusercontent.com/u/45264458?v=4?s=100" width="100px;" alt="Abdel @ StarkWare "/><br /><sub><b>Abdel @ StarkWare </b></sub></a><br /><a href="https://github.com/keep-starknet-strange/cairo-zig/commits?author=abdelhamidbakhta" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://bingcicle.github.io/"><img src="https://avatars.githubusercontent.com/u/25565268?v=4?s=100" width="100px;" alt="bing"/><br /><sub><b>bing</b></sub></a><br /><a href="https://github.com/keep-starknet-strange/cairo-zig/commits?author=bingcicle" title="Code">💻</a></td>
    </tr>
  </tbody>
</table>

<!-- markdownlint-restore -->
<!-- prettier-ignore-end -->

<!-- ALL-CONTRIBUTORS-LIST:END -->

This project follows the [all-contributors](https://github.com/all-contributors/all-contributors) specification. Contributions of any kind welcome!