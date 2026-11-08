# Environment Inventory Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans inline.

**Goal:** Restore sidebar categories and show all npm/Python environments together with row labels and an environment filter.
**Spec:** docs/superpowers/specs/2026-11-08-environment-inventory-design.md

## Task 1 — Runtime inventory and identity

- [x] Tests: same-source managers coexist; refresh failure affects only matching runtime; mutation targets exact runtime; environment filter preserves distinct names; bounded venv discovery skips unrelated trees.
- [x] RED scripts/test.sh, implement coordinator runtimeStates/configureManagers/canModify, PackageQuery managerPath filter, RuntimeDiscovery project envs, ManagerDiscovery all-environment API.
- [x] GREEN scripts/test.sh and commit.

## Task 2 — Categories and environment UI

- [x] Restore sidebar categories, environment filter above list; always label npm/pip runtime in rows; remove active-runtime settings and provide additive runtime discovery.
- [x] Address pending Go/Cargo review findings with failing regression tests first.
- [x] Update docs, test suite, build, native UI QA and final read-only review; commit verified release.
