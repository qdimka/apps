# Historical specifications and implementation plans

These files record earlier requirements and implementation work. They are loaded only when
explicitly requested or when investigating a decision. Do not automatically load this directory
as agent instructions. For current behavior, read [architecture.md](../architecture.md) and the
[root README](../../README.md).

| Specification | Plan | Status and precedence |
| --- | --- | --- |
| [Initial CLI manager](specs/2026-11-08-cli-manager-design.md) | [Initial implementation](plans/2026-11-08-apps.md) | Shipped as 0.1; later sources and execution safeguards extend this design |
| [npm and pip](specs/2026-11-08-npm-pip-design.md) | [npm/pip implementation](plans/2026-11-08-npm-pip.md) | Shipped as 0.2; single-active-runtime behavior superseded by environment inventory |
| [Go and Rust](specs/2026-11-08-go-rust-list-design.md) | [Go/Cargo implementation](plans/2026-11-08-go-rust-list.md) | Adapters shipped in 0.3; removal of the sidebar was superseded by user clarification |
| [Environment inventory](specs/2026-11-08-environment-inventory-design.md) | [Environment implementation](plans/2026-11-08-environment-inventory.md) | Current navigation and multi-runtime behavior, shipped in 0.3 |

Historical verification is recorded in [validation.md](../validation.md). Old commands and
proposals are historical context; use root agent instructions for current verification commands.
