import AppKit

@MainActor
enum AppMenuBuilder {
    static func install() {
        let mainMenu = NSMenu()
        let servicesMenu = NSMenu(title: "Services")

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        appMenuItem.submenu = appMenu(servicesMenu: servicesMenu)

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        editMenuItem.submenu = editMenu()

        NSApp.mainMenu = mainMenu
        NSApp.servicesMenu = servicesMenu
    }

    private static func appMenu(servicesMenu: NSMenu) -> NSMenu {
        let menu = NSMenu(title: "Fitbit Air Mood")
        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        servicesItem.submenu = servicesMenu
        menu.addItem(servicesItem)
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit Fitbit Air Mood",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")

        menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")

        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(redo)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")

        let pasteAndMatchStyle = NSMenuItem(
            title: "Paste and Match Style",
            action: #selector(NSTextView.pasteAsPlainText(_:)),
            keyEquivalent: "v"
        )
        pasteAndMatchStyle.keyEquivalentModifierMask = [.command, .option, .shift]
        menu.addItem(pasteAndMatchStyle)

        menu.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        menu.addItem(.separator())

        let dictationItem = NSMenuItem(
            title: "Start Dictation",
            action: Selector(("startDictation:")),
            keyEquivalent: ""
        )
        menu.addItem(dictationItem)

        menu.addItem(
            withTitle: "Emoji & Symbols",
            action: #selector(NSApplication.orderFrontCharacterPalette(_:)),
            keyEquivalent: " "
        ).keyEquivalentModifierMask = [.control, .command]

        return menu
    }
}
