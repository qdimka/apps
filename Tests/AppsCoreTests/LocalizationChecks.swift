import Foundation
import AppsCore

enum LocalizationChecks {
    static var all: [Check] { [
        Check(name: "Background environment additions preserve checked inventory and existing manager reads") {
            let old = FakeManager(source: .pip), added = FakeManager(source: .pip, runtimeSuffix: "new/")
            await old.setAvailableUpdate()
            let store = await PackageCoordinator(managers: [old]); await store.reload()
            let before = await store.packages[0]
            _ = await store.addManagers([added])
            let after = await store.packages
            try expectEqual(after.count, 2)
            try expectEqual(after.first { $0.id == before.id }?.updateStatus, .available)
            try expectEqual(await old.counts().lists, 1)
            try expectEqual(await added.counts().lists, 1)
        },
        Check(name: "Language presentation changes preserve checked inventory selection and manager calls") {
            let manager = FakeManager(source: .npm)
            await manager.setAvailableUpdate()
            let store = await PackageCoordinator(managers: [manager]); await store.reload()
            let before = await store.packages
            await store.relocalize(from: .english, to: .russian)
            let after = await store.packages
            try expectEqual(after.map(\.id), before.map(\.id))
            try expectEqual(after[0].latestVersion, "2")
            try expectEqual(after[0].updateStatus, .available)
            try expectEqual(PackageQuery.filter(after, source: .npm, search: "", updatesOnly: true).first?.id, before[0].id)
            try expectEqual(await manager.counts().lists, 1)
            try expectEqual(after[0].upgradeRestriction, AppLocalization.text("This package is pinned. Unpin it in its manager first.", language: .russian))
        },
        Check(name: "English is the default for absent or unsupported language preferences") {
            try expectEqual(AppLanguage.resolve(nil), .english)
            try expectEqual(AppLanguage.resolve("fr"), .english)
            try expectEqual(AppLanguage.resolve("ru"), .russian)
        },
        Check(name: "English and Russian catalogs format dynamic values without translating them") {
            try expectEqual(AppLocalization.text("Update", language: .english), "Update")
            try expectEqual(AppLocalization.text("Update", language: .russian), "\u{041E}\u{0431}\u{043D}\u{043E}\u{0432}\u{0438}\u{0442}\u{044C}")
            try expectEqual(AppLocalization.text("Remove %@?", arguments: ["@scope/a 100%"], language: .english), "Remove @scope/a 100%?")
            let package = "@scope/a 100%"
            try expectEqual(L("Remove \(package)?", language: .english), "Remove @scope/a 100%?")
            try expectEqual(L("Remove \(package)?", language: .russian), AppLocalization.text("Remove %@?", arguments: [package], language: .russian))
            try expectEqual(AppLocalization.text("unknown-key", language: .russian), "unknown-key")
        },
        Check(name: "Both localization catalogs have identical complete keys and placeholders") {
            let en = try AppLocalization.catalog(.english), ru = try AppLocalization.catalog(.russian)
            try expect(en.count >= 160)
            try expectEqual(Set(en.keys), Set(ru.keys))
            for key in en.keys {
                try expect(!en[key]!.isEmpty && !ru[key]!.isEmpty)
                try expectEqual(en[key]!.components(separatedBy: "%@").count, ru[key]!.components(separatedBy: "%@").count)
            }
        }
    ] }
}
