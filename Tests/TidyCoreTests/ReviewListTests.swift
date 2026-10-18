import Testing
@testable import TidyCore

private func item(_ name: String, checked: Bool = true, size: Int64 = 100) -> ReviewList.Item {
    ReviewList.Item(path: "/x/" + name, size: size, label: "name", needsSudo: false, checked: checked)
}

@Test func smallGroupsStartOpenBigOnesClosed() {
    let list = ReviewList(groups: [
        .init(title: "Small", detail: "", items: (1...5).map { item("s\($0)") }),
        .init(title: "Big", detail: "", items: (1...6).map { item("b\($0)") }),
        .init(title: "Empty", detail: "", items: []),
    ])
    #expect(list.groups.map(\.title) == ["Small", "Big"])
    #expect(list.rows.count == 1 + 5 + 1)
}

@Test func groupCheckboxShowsAllSomeNone() {
    var list = ReviewList(groups: [.init(title: "A", detail: "", items: [item("a"), item("b", checked: false)])])
    #expect(list.groups[0].state == .some)
    list.toggle()  // on the header: some → all
    #expect(list.groups[0].state == .all)
    list.toggle()  // all → none
    #expect(list.groups[0].state == .none)
    #expect(list.selectedPaths.isEmpty)
}

@Test func spaceOnAnItemTogglesOnlyThatItem() {
    var list = ReviewList(groups: [.init(title: "A", detail: "", items: [item("a"), item("b")])])
    list.move(by: 2)
    #expect(list.current == .item(0, 1))
    list.toggle()
    #expect(list.selectedPaths == ["/x/a"])
    #expect(list.selectedSize == 100)
}

@Test func aTogglesTheWholeGroupFromAnItem() {
    var list = ReviewList(groups: [
        .init(title: "A", detail: "", items: [item("a"), item("b")]),
        .init(title: "B", detail: "", items: [item("c", checked: false)]),
    ])
    list.move(by: 1)
    list.toggleAllInGroup()  // all → none, only group A
    #expect(list.selectedPaths.isEmpty)
    list.toggleAllInGroup()  // none → all
    #expect(list.selectedPaths == ["/x/a", "/x/b"])
}

@Test func leftJumpsToTheHeaderThenCollapses() {
    var list = ReviewList(groups: [
        .init(title: "A", detail: "", items: [item("a"), item("b")]),
        .init(title: "B", detail: "", items: [item("c")]),
    ])
    list.move(by: 2)
    list.collapse()
    #expect(list.current == .group(0))
    list.collapse()
    #expect(list.rows == [.group(0), .group(1), .item(1, 0)])
    list.expand()
    #expect(list.rows.count == 5)
    #expect(list.selectedPaths.count == 3)  // collapsing never unchecks anything
}

@Test func pickerFiltersAndKeepsSelectionsAcrossFilters() {
    let apps = ["Discord", "Firefox", "Discord PTB"].map {
        App(path: "/Applications/\($0).app", bundleID: nil, bundleName: nil, displayName: nil, executable: nil, source: .manual)
    }
    var picker = AppPicker(apps: apps)
    for c in "DISC" { picker.type(c) }
    #expect(picker.visible.map(\.name) == ["Discord", "Discord PTB"])
    picker.move(by: 1)
    picker.toggle()
    for _ in 0..<4 { picker.backspace() }
    for c in "fire" { picker.type(c) }
    picker.toggle()
    #expect(picker.chosen.map(\.name) == ["Firefox", "Discord PTB"])  // in list order, both kept
    for _ in 0..<4 { picker.backspace() }
    #expect(picker.visible.count == 3)
}

@Test func enterWithNothingSelectedTakesTheHighlightedApp() {
    let apps = ["Alpha", "Beta"].map {
        App(path: "/Applications/\($0).app", bundleID: nil, bundleName: nil, displayName: nil, executable: nil, source: .manual)
    }
    var picker = AppPicker(apps: apps)
    picker.move(by: 1)
    #expect(picker.chosen.map(\.name) == ["Beta"])
}
