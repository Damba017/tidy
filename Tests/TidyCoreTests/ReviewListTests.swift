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

@Test func tabJumpsBetweenGroupHeaders() {
    var list = ReviewList(groups: [
        .init(title: "A", detail: "", items: [item("a1"), item("a2")]),
        .init(title: "B", detail: "", items: (1...8).map { item("b\($0)") }),  // starts closed
        .init(title: "C", detail: "", items: [item("c1")]),
    ])
    list.jumpToGroup(forward: true)
    #expect(list.current == .group(1))
    list.jumpToGroup(forward: true)
    #expect(list.current == .group(2))
    list.move(by: 1)
    #expect(list.current == .item(2, 0))
    list.jumpToGroup(forward: false)
    #expect(list.current == .group(2))  // from an item: its own header first
    list.jumpToGroup(forward: false)
    #expect(list.current == .group(1))
}

@Test func tabGoesRoundAtTheEnds() {
    var list = ReviewList(groups: [
        .init(title: "A", detail: "", items: [item("a1")]),
        .init(title: "B", detail: "", items: [item("b1")]),
    ])
    list.jumpToGroup(forward: false)  // ⇧Tab on the first group → the last
    #expect(list.current == .group(1))
    list.move(by: 1)                  // on the last group's item
    list.jumpToGroup(forward: true)   // Tab past the last group → the first
    #expect(list.current == .group(0))
}

@Test func searchShowsOnlyMatchesInOpenedGroups() {
    var list = ReviewList(groups: [
        .init(title: "Caches & logs", detail: "", items: [item("Godot"), item("pycache-ish")]),
        .init(title: "Dev junk", detail: "", items: (1...8).map { item("proj\($0)/__pycache__") }),  // closed
        .init(title: "Orphans", detail: "", items: [item("com.gone.app", checked: false)]),
    ])
    list.setSearch("PYCACHE")
    #expect(list.rows.count == 1 + 1 + 1 + 8)  // both groups with hits, opened; Orphans hidden
    #expect(list.matchCount == 9)
    list.setSearch("orphans")  // a group's name matches all of its items
    #expect(list.rows == [.group(2), .item(2, 0)])
    list.setSearch("")
    #expect(list.rows.count == 1 + 2 + 1 + 1 + 1)  // back to normal: Dev junk closed again
}

@Test func toggleWhileSearchingOnlyTouchesWhatIsShown() {
    var list = ReviewList(groups: [
        .init(title: "Dev junk", detail: "", items: [item("a/__pycache__"), item("b/node_modules"), item("c/__pycache__")]),
    ])
    list.setSearch("pycache")
    list.toggle()  // on the header: all shown checked → uncheck just those
    #expect(list.selectedPaths == ["/x/b/node_modules"])
    list.toggleAllInGroup()
    #expect(list.selectedPaths.count == 3)
    list.setSearch("")
    #expect(list.groups[0].state == .all)
}

private func candidates(_ names: [String]) -> [Candidate] {
    names.map {
        Candidate(app: App(path: "/Applications/\($0).app", bundleID: nil, bundleName: nil, displayName: nil,
                           executable: nil, source: .manual))
    }
}

@Test func pickerFiltersAndKeepsSelectionsAcrossFilters() {
    var picker = AppPicker(candidates: candidates(["Discord", "Firefox", "Discord PTB"]))
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
    var picker = AppPicker(candidates: candidates(["Alpha", "Beta"]))
    picker.move(by: 1)
    #expect(picker.chosen.map(\.name) == ["Beta"])
}
