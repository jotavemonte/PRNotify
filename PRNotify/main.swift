import AppKit

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate

// Without a main menu, text fields don't receive ⌘V/⌘A/⌘C/⌘X.
// We only need the Edit items — no need for a visible menu bar.
let mainMenu = NSMenu()

let editMenuItem = NSMenuItem()
mainMenu.addItem(editMenuItem)

let editMenu = NSMenu(title: "Edit")
editMenu.addItem(NSMenuItem(title: "Cut",        action: #selector(NSText.cut(_:)),             keyEquivalent: "x"))
editMenu.addItem(NSMenuItem(title: "Copy",       action: #selector(NSText.copy(_:)),            keyEquivalent: "c"))
editMenu.addItem(NSMenuItem(title: "Paste",      action: #selector(NSText.paste(_:)),           keyEquivalent: "v"))
editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)),       keyEquivalent: "a"))
editMenu.addItem(NSMenuItem(title: "Undo",       action: #selector(UndoManager.undo),           keyEquivalent: "z"))
editMenu.addItem(NSMenuItem(title: "Redo",       action: Selector(("redo:")),                   keyEquivalent: "Z"))
editMenuItem.submenu = editMenu

NSApp.mainMenu = mainMenu

NSApp.run()
