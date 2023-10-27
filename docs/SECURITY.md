# Security Guidelines

## Introduction

Security is a top priority in the development of Cairo-Zig. This document outlines some security best practices that contributors should follow, as well as procedures for reporting security vulnerabilities.

---

## Security Best Practices

### Code Quality Rules

- **Understandable and Simplicity:** Keep your code as simple and straightforward as possible.

- **Code Reviews:** Every pull request must be reviewed by at least one other developer who is knowledgeable about the code and context.

- **Limited Scope:** Minimize the accessibility of functions, classes, and variables by reducing their scope whenever possible.

- **Error Handling:** Always check for error returns unless you are absolutely sure that the function cannot return an error.

- **Input Validation:** Validate input from all untrusted data sources.

### NASA's Power of Ten Rules

We adhere to the [NASA Power of Ten Rules](https://en.wikipedia.org/wiki/The_Power_of_10:_Rules_for_Developing_Safety-Critical_Code) for safer code:

1. **Avoid complex flow constructs, such as `goto` and recursion.**
2. **All loops must have a fixed upper bound and be provably terminable.**
3. **Avoid dynamic memory allocation after initialization.**
4. **No function should be longer than what can be printed on a single sheet of paper.**
5. **Assert liberally to document internal assumptions and invariants.**
6. **Minimize global and shared data.**
7. **Use at least two runtime assertions per function.**
8. **Data objects must be declared at the smallest possible level of scope.**
9. **Check the return value of all non-void functions, or cast to void to indicate the result is useless.**
10. **Limit the scope of data to the smallest possible lexical scope.**

---

## Vulnerability Reporting

### Critical Vulnerabilities

For critical vulnerabilities, please do **NOT** open an issue. Instead, send an email directly to [security@starkware.co](mailto:security@starkware.co).

Critical vulnerabilities include but are not limited to:

- Code execution attacks
- Privilege escalation
- Data leaks

### Non-Critical Vulnerabilities

For non-critical vulnerabilities, such as issues that are relevant but do not pose an immediate threat to the integrity of the system, you may open a GitHub issue in the [cairo-zig repository](https://github.com/keep-starknet-strange/cairo-zig/issues).

---

## Conclusion

Adhering to these guidelines is essential for ensuring that Cairo-Zig remains a secure and reliable codebase. Your cooperation is greatly appreciated.

---

For any further questions, feel free to contact [security@starkware.co](mailto:security@starkware.co).
