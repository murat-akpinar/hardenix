# hardenix — Documentation

Architecture and internals documentation for the **final target state** of the
project: the hardening script that exists today, plus the fleet web UI that is
planned on top of it.

| Document | Covers | Status of what it describes |
|----------|--------|------------------------------|
| [architecture.md](architecture.md) | The big picture: components, security layers, data flows, golden-image workflow | Script: **shipped** · Web UI: **planned** |
| [script-internals.md](script-internals.md) | How `linuxharden.sh` works inside: pipeline, mode flows, backup/revert contract, profiles | **Shipped** (v1.1.0) |
| [fleet-webui.md](fleet-webui.md) | The fleet management web UI: architecture, data model, job engine, security model | **Planned** (design final, see `todo/webui-plan.md`) |

Conventions used throughout:

- ✅ = implemented and tested on real machines
- 🔜 = designed and approved, not yet built
- Paths like `run_apply()` refer to functions in `linuxharden.sh`.

User-facing usage documentation (flags, examples, warnings) lives in the main
[README.md](../README.md) / [README_TR.md](../README_TR.md); this directory is for
understanding *how the system is built and why*.
