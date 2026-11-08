# Go Rust and Unified List Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans task-by-task.

**Goal:** Добавить Go/Cargo и общий список с постоянными метками и верхним фильтром источника.
**Architecture:** Два новых PackageManager; файловые операции Go ограничены одним проверенным бинарником, Cargo — своим tracking registry и явным root. SwiftUI split view становится двухколоночным.
**Tech Stack:** Swift 6, macOS 14+, Foundation, существующие Go/Cargo, JSON, без новых зависимостей.
**Spec:** docs/superpowers/specs/2026-11-08-go-rust-list-design.md

## Global Constraints

- Реальные инструменты не устанавливаются/обновляются/удаляются при тестировании.
- Только явные argv, без shell и --force; Cargo root и Go target задаются точно.
- По умолчанию все источники, метка источника всегда видна.
- Стандартные кнопки окна macOS, без дубликатов.

## Review Focus

- Имена/пути и символьные ссылки не могут расширить файловое удаление Go (задача 1).
- Сборка Go не заменяет текущий бинарник до успешной проверки результата и повторной идентификации (задача 1).
- Cargo root, source, bins и build options сохраняются; Git/локальные origin не становятся crates.io (задача 2).
- Старый/повреждённый реестр и пустая установка различаются (задача 2).
- Фильтр не прячет источник статуса или метку в строке, старый persisted source не сужает стартовый список (задача 3).

### Task 1: Go

**Files:** Sources/AppsCore/{GoManager,ManagedFiles,PackageRecord,PackageManager,ManagerDiscovery}.swift; Tests/AppsCoreTests/GoChecks.swift.
**Interfaces:** GoManager(executable: URL, runner: CommandRunning, trash: FileTrashing); FileTrashing.trash(URL) throws; PackageRecord.identityScope, packageReference, modulePath, buildOptions.

- [ ] Фикстуры build-info JSON, Go env, module latest; тесты symlink/foreign/devel/replaced, exact target, staged promotion/failure, stale fingerprint и Trash на временных файлах.
- [ ] RED через scripts/test.sh.
- [ ] Реализовать Go list/check/upgrade/uninstall с повторной валидацией и временным GOBIN, добавить источник и поля модели.
- [ ] GREEN всей suite и коммит.

### Task 2: Cargo

**Files:** Sources/AppsCore/CargoManager.swift, ManagerDiscovery.swift, PackageRecord.swift; Tests/AppsCoreTests/CargoChecks.swift.
**Interfaces:** CargoManager(executable: URL, root: URL, runner: CommandRunning); .crates2 parsing с root/source scope и точным packageReference.

- [ ] Тесты registry/git/path, bins/features/target/profile, qualified uninstall, no downgrade, corrupted/empty/legacy metadata.
- [ ] RED через scripts/test.sh.
- [ ] Реализовать Cargo list/check/upgrade/uninstall с точным root, сохранением параметров и deadline.
- [ ] GREEN, реальная инвентаризация только чтением, коммит.

### Task 3: Общий список

**Files:** Sources/Apps/{ContentView,AppModel,PackageDetailView,SourceSettingsView}.swift; Tests/AppsCoreTests/CoordinatorChecks.swift; Resources/Info.plist; README.md; docs/validation.md.
**Interfaces:** sourceKey изначально all, верхний Picker; настройки cargoRoot через replaceManager; общий PackageQuery по всем источникам.

- [ ] Проверить общий список/фильтры/одинаковые имена из новых источников, RED→GREEN при изменении логики.
- [ ] Удалить sidebar, всегда отображать SourceBadge, добавить верхний фильтр и состояния источников, настройки Cargo root и точные подтверждения Go/Cargo.
- [ ] Обновить 0.3.0 и документацию, suite + build + signature + native QA.
- [ ] Независимый обзор, важные исправления с регрессиями, финальный коммит и приложение.
