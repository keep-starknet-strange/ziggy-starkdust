<!-- markdownlint-disable MD033 -->
<!-- markdownlint-disable MD041 -->
<p align="center">
  <img src="https://github.com/keep-starknet-strange/ziggy-starkdust/blob/main/docs/kit/logo/starknet-zig-logo.png?raw=true" alt="Logo"/>
  <h1 align="center">ziggy-starkdust</h1>
</p>

<div align="center">
<br />

<a href="https://github.com/keep-starknet-strange/ziggy-starkdust/actions/workflows/test.yml"><img alt="GitHub Workflow Status (with event)" src="https://img.shields.io/github/actions/workflow/status/keep-starknet-strange/ziggy-starkdust/test.yml?style=for-the-badge" height=30></a>
<a href="https://securityscorecards.dev/viewer/?uri=github.com/keep-starknet-strange/ziggy-starkdust"><img alt="OpenSSF Scorecard Report" src="https://img.shields.io/ossf-scorecard/github.com/keep-starknet-strange/ziggy-starkdust?label=openssf%20scorecard&style=for-the-badge" height=30></a>
<a href="https://github.com/keep-starknet-strange/ziggy-starkdust/blob/main/LICENSE"><img src="https://img.shields.io/github/license/keep-starknet-strange/ziggy-starkdust.svg?style=for-the-badge" alt="Project license" height="30"></a>
<a href="https://twitter.com/StarknetZig"><img src="https://img.shields.io/twitter/follow/StarknetZig?style=for-the-badge&logo=twitter" alt="Follow StarknetZig on Twitter" height="30"></a>

[![Exploration_Team](https://img.shields.io/badge/Exploration_Team-29296E.svg?&style=for-the-badge&logo=data:image/svg%2bxml;base64,PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz48c3ZnIGlkPSJhIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAxODEgMTgxIj48ZGVmcz48c3R5bGU+LmJ7ZmlsbDojZmZmO308L3N0eWxlPjwvZGVmcz48cGF0aCBjbGFzcz0iYiIgZD0iTTE3Ni43Niw4OC4xOGwtMzYtMzcuNDNjLTEuMzMtMS40OC0zLjQxLTIuMDQtNS4zMS0xLjQybC0xMC42MiwyLjk4LTEyLjk1LDMuNjNoLjc4YzUuMTQtNC41Nyw5LjktOS41NSwxNC4yNS0xNC44OSwxLjY4LTEuNjgsMS44MS0yLjcyLDAtNC4yN0w5Mi40NSwuNzZxLTEuOTQtMS4wNC00LjAxLC4xM2MtMTIuMDQsMTIuNDMtMjMuODMsMjQuNzQtMzYsMzcuNjktMS4yLDEuNDUtMS41LDMuNDQtLjc4LDUuMThsNC4yNywxNi41OGMwLDIuNzIsMS40Miw1LjU3LDIuMDcsOC4yOS00LjczLTUuNjEtOS43NC0xMC45Ny0xNS4wMi0xNi4wNi0xLjY4LTEuODEtMi41OS0xLjgxLTQuNCwwTDQuMzksODguMDVjLTEuNjgsMi4zMy0xLjgxLDIuMzMsMCw0LjUzbDM1Ljg3LDM3LjNjMS4zNiwxLjUzLDMuNSwyLjEsNS40NCwxLjQybDExLjQtMy4xMSwxMi45NS0zLjYzdi45MWMtNS4yOSw0LjE3LTEwLjIyLDguNzYtMTQuNzYsMTMuNzNxLTMuNjMsMi45OC0uNzgsNS4zMWwzMy40MSwzNC44NGMyLjIsMi4yLDIuOTgsMi4yLDUuMTgsMGwzNS40OC0zNy4xN2MxLjU5LTEuMzgsMi4xNi0zLjYsMS40Mi01LjU3LTEuNjgtNi4wOS0zLjI0LTEyLjMtNC43OS0xOC4zOS0uNzQtMi4yNy0xLjIyLTQuNjItMS40Mi02Ljk5LDQuMyw1LjkzLDkuMDcsMTEuNTIsMTQuMjUsMTYuNzEsMS42OCwxLjY4LDIuNzIsMS42OCw0LjQsMGwzNC4zMi0zNS43NHExLjU1LTEuODEsMC00LjAxWm0tNzIuMjYsMTUuMTVjLTMuMTEtLjc4LTYuMDktMS41NS05LjE5LTIuNTktMS43OC0uMzQtMy42MSwuMy00Ljc5LDEuNjhsLTEyLjk1LDEzLjg2Yy0uNzYsLjg1LTEuNDUsMS43Ni0yLjA3LDIuNzJoLS42NWMxLjMtNS4zMSwyLjcyLTEwLjYyLDQuMDEtMTUuOGwxLjY4LTYuNzNjLjg0LTIuMTgsLjE1LTQuNjUtMS42OC02LjA5bC0xMi45NS0xNC4xMmMtLjY0LS40NS0xLjE0LTEuMDgtMS40Mi0xLjgxbDE5LjA0LDUuMTgsMi41OSwuNzhjMi4wNCwuNzYsNC4zMywuMTQsNS43LTEuNTVsMTIuOTUtMTQuMzhzLjc4LTEuMDQsMS42OC0xLjE3Yy0xLjgxLDYuNi0yLjk4LDE0LjEyLTUuNDQsMjAuNDYtMS4wOCwyLjk2LS4wOCw2LjI4LDIuNDYsOC4xNiw0LjI3LDQuMTQsOC4yOSw4LjU1LDEyLjk1LDEyLjk1LDAsMCwxLjMsLjkxLDEuNDIsMi4wN2wtMTMuMzQtMy42M1oiLz48L3N2Zz4=)](https://github.com/keep-starknet-strange)

</div>

> _Note that `ziggy-starkdust` is still experimental. Breaking changes will be made before the first stable release. The library is also NOT audited or reviewed for security at the moment. Use at your own risk._

## 📦 Installation

### 📋 Prerequisites

- [Zig](https://ziglang.org/)

Alternatively, if you have [nix](https://nixos.org/) installed, you can get the full development environment `nix develop`.

- Also you need installed python, so we can compile cairo0 programs in benchmarks/integration tests, to insatll them just run: 
  ```bash
  make deps
  ```
  if u got macos:
  ```bash 
  make deps-macos
  ```
- After you need compile all cairo0 programs, to use test or benchmarks:
  ```bash
  make compile-cairo-programs
  ```
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
./zig-out/bin/ziggy-starkdust --help
```

### Run a cairo program

Without proof mode:
```bash
./zig-out/bin/ziggy-starkdust execute --filename cairo_programs/fibonacci.json
```

With proof mode:
```bash
./zig-out/bin/ziggy-starkdust execute --filename cairo_programs/fibonacci.json --proof-mode
```

With memory layout, trace, proof mode and custom layout:
```bash
./zig-out/bin/ziggy-starkdust execute --filename cairo_programs/fibonacci.json --memory-file=/dev/null --trace-file=/dev/null --proof-mode=true --layout all_cairo
```


### 🧪 Testing

Run all integration tests with summary:
```bash
make build-integration-test
./zig-out/bin/integration_test
```

Run all benchmarks and compare:
```bash
make build-compare-benchmarks
```

Run all programs and compare output memory/trace for Zig/Rust cairo-vm:
```bash
make build-compare-output
```


Run all unit tests with test summary:

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

In order to compare two memory files or trace files, use the following command: 

`vbindiff cairo_programs/expected_fibonacci.trace cairo_programs/fibonacci.trace`

## 📊 Benchmarks

### Installing benchmark dependencies

In order to compile programs you need to install the cairo-lang package.

Running the  `make deps` (or the `make deps-macos`  if you are runnning in MacOS) command will create a virtual environment with all the required dependencies.

Run the complete benchmark suite with Make:

```bash
make build-compare-benchmarks
```


### 🔒 Security

#### Security guidelines

For security guidelines, please refer to [SECURITY.md](docs/SECURITY.md).

#### OpenSSF Scorecard

We are using the [OpenSSF Scorecard](https://securityscorecards.dev/) to track the security of this project.

Scorecard assesses open source projects for security risks through a series of automated checks.

You can see the current scorecard for this project [here](https://securityscorecards.dev/viewer/?uri=github.com/keep-starknet-strange/ziggy-starkdust).

## 🙏 Acknowledgments

- The structure of the project and some initial code related to prime field functions is based on [verkle-cryto](https://github.com/jsign/verkle-crypto) repository by [jsign](https://github.com/jsign).
- The design of the Cairo VM is inspired by [Cairo VM in Rust](https://github.com/lambdaclass/cairo-vm) and [Cairo VM in Go](https://github.com/lambdaclass/cairo-vm_in_go) by [lambdaclass](https://lambdaclass.com/).
- Some cryptographic primitive code generation has been done using the amazing [fiat-crypto](https://github.com/mit-plv/fiat-crypto) by [mit-plv](https://github.com/mit-plv).
- [sig](https://github.com/Syndica/sig) has been a great source of inspiration for the project structure and the way to use Zig.
- [nektro](https://github.com/nektro/) for the [zig-time](https://github.com/nektro/zig-time) library.
- The Cairo files used in this project are sourced from the [Cairo VM in Rust](https://github.com/lambdaclass/cairo-vm) by [lambdaclass](https://lambdaclass.com/).

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
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/abdelhamidbakhta"><img src="https://avatars.githubusercontent.com/u/45264458?v=4?s=100" width="100px;" alt="Abdel @ StarkWare "/><br /><sub><b>Abdel @ StarkWare </b></sub></a><br /><a href="https://github.com/keep-starknet-strange/ziggy-starkdust/commits?author=abdelhamidbakhta" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://bingcicle.github.io/"><img src="https://avatars.githubusercontent.com/u/25565268?v=4?s=100" width="100px;" alt="bing"/><br /><sub><b>bing</b></sub></a><br /><a href="https://github.com/keep-starknet-strange/ziggy-starkdust/commits?author=bingcicle" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://ceccon.me/"><img src="https://avatars.githubusercontent.com/u/282580?v=4?s=100" width="100px;" alt="Francesco Ceccon"/><br /><sub><b>Francesco Ceccon</b></sub></a><br /><a href="https://github.com/keep-starknet-strange/ziggy-starkdust/commits?author=fracek" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/tcoratger"><img src="https://avatars.githubusercontent.com/u/60488569?v=4?s=100" width="100px;" alt="Thomas Coratger"/><br /><sub><b>Thomas Coratger</b></sub></a><br /><a href="https://github.com/keep-starknet-strange/ziggy-starkdust/commits?author=tcoratger" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/lambda-0x"><img src="https://avatars.githubusercontent.com/u/87354252?v=4?s=100" width="100px;" alt="lambda-0x"/><br /><sub><b>lambda-0x</b></sub></a><br /><a href="https://github.com/keep-starknet-strange/ziggy-starkdust/commits?author=lambda-0x" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://nils-mathieu.fr/"><img src="https://avatars.githubusercontent.com/u/80390054?v=4?s=100" width="100px;" alt="Nils"/><br /><sub><b>Nils</b></sub></a><br /><a href="https://github.com/keep-starknet-strange/ziggy-starkdust/commits?author=nils-mathieu" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/jobez"><img src="https://avatars.githubusercontent.com/u/615197?v=4?s=100" width="100px;" alt="johann bestowrous"/><br /><sub><b>johann bestowrous</b></sub></a><br /><a href="https://github.com/keep-starknet-strange/ziggy-starkdust/commits?author=jobez" title="Code">💻</a></td>
    </tr>
    <tr>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/lana-shanghai"><img src="https://avatars.githubusercontent.com/u/31368580?v=4?s=100" width="100px;" alt="lanaivina"/><br /><sub><b>lanaivina</b></sub></a><br /><a href="https://github.com/keep-starknet-strange/ziggy-starkdust/commits?author=lana-shanghai" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/dhruvkelawala"><img src="https://avatars.githubusercontent.com/u/50968441?v=4?s=100" width="100px;" alt="Dhruv Kelawala"/><br /><sub><b>Dhruv Kelawala</b></sub></a><br /><a href="https://github.com/keep-starknet-strange/ziggy-starkdust/commits?author=dhruvkelawala" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/Godspower-Eze"><img src="https://avatars.githubusercontent.com/u/61994334?v=4?s=100" width="100px;" alt="Godspower Eze"/><br /><sub><b>Godspower Eze</b></sub></a><br /><a href="https://github.com/keep-starknet-strange/ziggy-starkdust/commits?author=Godspower-Eze" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/edisontim"><img src="https://avatars.githubusercontent.com/u/76473430?v=4?s=100" width="100px;" alt="tedison"/><br /><sub><b>tedison</b></sub></a><br /><a href="https://github.com/keep-starknet-strange/ziggy-starkdust/commits?author=edisontim" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/ptisserand"><img src="https://avatars.githubusercontent.com/u/544314?v=4?s=100" width="100px;" alt="ptisserand"/><br /><sub><b>ptisserand</b></sub></a><br /><a href="https://github.com/keep-starknet-strange/ziggy-starkdust/commits?author=ptisserand" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://ndcroos.github.io/site/"><img src="https://avatars.githubusercontent.com/u/16431833?v=4?s=100" width="100px;" alt="ndcroos"/><br /><sub><b>ndcroos</b></sub></a><br /><a href="https://github.com/keep-starknet-strange/ziggy-starkdust/commits?author=ndcroos" title="Documentation">📖</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/0xicosahedron"><img src="https://avatars.githubusercontent.com/u/83328087?v=4?s=100" width="100px;" alt="Icosahedron"/><br /><sub><b>Icosahedron</b></sub></a><br /><a href="https://github.com/keep-starknet-strange/ziggy-starkdust/commits?author=0xicosahedron" title="Code">💻</a></td>
    </tr>
    <tr>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/pjserol"><img src="https://avatars.githubusercontent.com/u/3019795?v=4?s=100" width="100px;" alt="Pierre-Jean"/><br /><sub><b>Pierre-Jean</b></sub></a><br /><a href="https://github.com/keep-starknet-strange/ziggy-starkdust/commits?author=pjserol" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/tudorpintea999"><img src="https://avatars.githubusercontent.com/u/87604944?v=4?s=100" width="100px;" alt="iwantanode"/><br /><sub><b>iwantanode</b></sub></a><br /><a href="https://github.com/keep-starknet-strange/ziggy-starkdust/commits?author=tudorpintea999" title="Documentation">📖</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/StringNick"><img src="https://avatars.githubusercontent.com/u/13052752?v=4?s=100" width="100px;" alt="Nikita Orlov"/><br /><sub><b>Nikita Orlov</b></sub></a><br /><a href="https://github.com/keep-starknet-strange/ziggy-starkdust/commits?author=StringNick" title="Code">💻</a></td>
    </tr>
  </tbody>
</table>

<!-- markdownlint-restore -->
<!-- prettier-ignore-end -->

<!-- ALL-CONTRIBUTORS-LIST:END -->

This project follows the [all-contributors](https://github.com/all-contributors/all-contributors) specification. Contributions of any kind welcome!
