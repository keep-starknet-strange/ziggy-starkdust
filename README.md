<!-- markdownlint-disable MD033 -->
<!-- markdownlint-disable MD041 -->
<p align="center">
  <img src="https://github.com/keep-starknet-strange/cairo-zig/blob/main/docs/kit/logo/starknet-zig-logo.png?raw=true" alt="Logo"/>
  <h1 align="center">cairo-zig</h1>
</p>

<div align="center">
<br />

<a href="https://github.com/keep-starknet-strange/cairo-zig/actions/workflows/test.yml"><img alt="GitHub Workflow Status (with event)" src="https://img.shields.io/github/actions/workflow/status/keep-starknet-strange/cairo-zig/test.yml?style=for-the-badge" height=30></a>
<a href="https://securityscorecards.dev/viewer/?uri=github.com/keep-starknet-strange/cairo-zig"><img alt="OpenSSF Scorecard Report" src="https://img.shields.io/ossf-scorecard/github.com/keep-starknet-strange/cairo-zig?label=openssf%20scorecard&style=for-the-badge" height=30></a>
<a href="https://github.com/keep-starknet-strange/cairo-zig/blob/main/LICENSE"><img src="https://img.shields.io/github/license/keep-starknet-strange/cairo-zig.svg?style=for-the-badge" alt="Project license" height="30"></a>
<a href="https://twitter.com/StarknetZig"><img src="https://img.shields.io/twitter/follow/StarknetZig?style=for-the-badge&logo=twitter" alt="Follow StarknetZig on Twitter" height="30"></a>

</div>

> _Note that `cairo-zig` is still experimental. Breaking changes will be made before the first stable release. The library is also NOT audited or reviewed for security at the moment. Use at your own risk._

## 📦 Installation

### 📋 Prerequisites

- [Zig](https://ziglang.org/)

Alternatively, if you have [nix](https://nixos.org/) installed, you can get the full development environment `nix develop`.

## ⚡ Wanna get up to speed fast?

<details>
  <summary>👇 ⚡ Zig </summary>

- [Zig language reference](https://ziglang.org/documentation/master/)
- [Zig Learn](https://ziglearn.org/)
- [Ziglings](https://ziglings.org/)

</details>

<details>
  <summary>👇 🐺 Cairo VM </summary>

- [Cairo Whitepaper](https://eprint.iacr.org/2021/1063.pdf)
- [OG Cairo VM in Python](https://github.com/starkware-libs/cairo-lang/tree/master/src/starkware/cairo/lang/vm)
- [Cairo VM in Rust](https://github.com/lambdaclass/cairo-vm)
- [Cairo VM in Go](https://github.com/lambdaclass/cairo-vm_in_go)

</details>

## 🔧 Build

```bash
make build
```

## 🤖 Usage

You can display the help message by running:

```bash
./zig-out/bin/cairo-zig --help
```

### Run a cairo program

```bash
./zig-out/bin/cairo-zig execute --proof-mode=false
```

### 🧪 Testing

Run all tests with test summary:

```bash
make test
```

Run a single test, for example, the "Felt252 zero" test: 

```console
$ make test-filter FILTER="Felt252 zero"
All 2 tests passed.
```

Notice that 2 tests passed despite running only 1 test, because
our tests are wrapped in another test call within `src/tests.zig`.

### 🔒 Security

#### Security guidelines

For security guidelines, please refer to [SECURITY.md](docs/SECURITY.md).

#### OpenSSF Scorecard

We are using the [OpenSSF Scorecard](https://securityscorecards.dev/) to track the security of this project.

Scorecard assesses open source projects for security risks through a series of automated checks.

You can see the current scorecard for this project [here](https://securityscorecards.dev/viewer/?uri=github.com/keep-starknet-strange/cairo-zig).

## 🙏 Acknowledgments

- The structure of the project and some initial code related to prime field functions is based on [verkle-cryto](https://github.com/jsign/verkle-crypto) repository by [jsign](https://github.com/jsign).
- The design of the Cairo VM is inspired by [Cairo VM in Rust](https://github.com/lambdaclass/cairo-vm) and [Cairo VM in Go](https://github.com/lambdaclass/cairo-vm_in_go) by [lambdaclass](https://lambdaclass.com/).
- Some cryptographic primitive code generation has been done using the amazing [fiat-crypto](https://github.com/mit-plv/fiat-crypto) by [mit-plv](https://github.com/mit-plv).
- [sig](https://github.com/Syndica/sig) has been a great source of inspiration for the project structure and the way to use Zig.
- [nektro](https://github.com/nektro/) for the [zig-time](https://github.com/nektro/zig-time) library.

## ⚡ Why Zig?

<details>
  <summary>👇 ⚡ </summary>

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

</details>

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
      <td align="center" valign="top" width="14.28%"><a href="https://ceccon.me/"><img src="https://avatars.githubusercontent.com/u/282580?v=4?s=100" width="100px;" alt="Francesco Ceccon"/><br /><sub><b>Francesco Ceccon</b></sub></a><br /><a href="https://github.com/keep-starknet-strange/cairo-zig/commits?author=fracek" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/tcoratger"><img src="https://avatars.githubusercontent.com/u/60488569?v=4?s=100" width="100px;" alt="Thomas Coratger"/><br /><sub><b>Thomas Coratger</b></sub></a><br /><a href="https://github.com/keep-starknet-strange/cairo-zig/commits?author=tcoratger" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/lambda-0x"><img src="https://avatars.githubusercontent.com/u/87354252?v=4?s=100" width="100px;" alt="lambda-0x"/><br /><sub><b>lambda-0x</b></sub></a><br /><a href="https://github.com/keep-starknet-strange/cairo-zig/commits?author=lambda-0x" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://nils-mathieu.fr/"><img src="https://avatars.githubusercontent.com/u/80390054?v=4?s=100" width="100px;" alt="Nils"/><br /><sub><b>Nils</b></sub></a><br /><a href="https://github.com/keep-starknet-strange/cairo-zig/commits?author=nils-mathieu" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/jobez"><img src="https://avatars.githubusercontent.com/u/615197?v=4?s=100" width="100px;" alt="johann bestowrous"/><br /><sub><b>johann bestowrous</b></sub></a><br /><a href="https://github.com/keep-starknet-strange/cairo-zig/commits?author=jobez" title="Code">💻</a></td>
    </tr>
    <tr>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/lana-shanghai"><img src="https://avatars.githubusercontent.com/u/31368580?v=4?s=100" width="100px;" alt="lanaivina"/><br /><sub><b>lanaivina</b></sub></a><br /><a href="https://github.com/keep-starknet-strange/cairo-zig/commits?author=lana-shanghai" title="Code">💻</a></td>
    </tr>
  </tbody>
</table>

<!-- markdownlint-restore -->
<!-- prettier-ignore-end -->

<!-- ALL-CONTRIBUTORS-LIST:END -->

This project follows the [all-contributors](https://github.com/all-contributors/all-contributors) specification. Contributions of any kind welcome!
