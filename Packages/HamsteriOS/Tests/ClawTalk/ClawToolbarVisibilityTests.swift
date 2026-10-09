import HamsterKeyboardKit
import XCTest

final class ClawToolbarVisibilityTests: XCTestCase {
  func testEmptyInputShowsActionsNotCandidates() {
    let state = ClawToolbarVisibility.resolve(
      inputIsEmpty: true, panelIsOpen: false,
      candidatesAreExpanded: false, hasSuggestions: false
    )
    XCTAssertTrue(state.showsFunctionBar)
    XCTAssertFalse(state.showsCandidateBar)
    XCTAssertFalse(state.showsPanel)
  }

  func testActivePinyinShowsCandidatesAndHidesOldActions() {
    let state = ClawToolbarVisibility.resolve(
      inputIsEmpty: false, panelIsOpen: false,
      candidatesAreExpanded: false, hasSuggestions: true
    )
    XCTAssertFalse(state.showsFunctionBar)
    XCTAssertTrue(state.showsCandidateBar)
    XCTAssertTrue(state.showsSuggestions)
  }

  func testPanelRemainsExclusiveWhenRimeInputChanges() {
    for inputIsEmpty in [true, false] {
      let state = ClawToolbarVisibility.resolve(
        inputIsEmpty: inputIsEmpty, panelIsOpen: true,
        candidatesAreExpanded: false, hasSuggestions: true
      )
      XCTAssertTrue(state.showsPanel)
      XCTAssertTrue(state.showsFunctionBar)
      XCTAssertFalse(state.showsCandidateBar)
      XCTAssertFalse(state.showsSuggestions)
    }
  }

  func testExpandedCandidatesNeverShowSuggestionsOrOldActions() {
    let state = ClawToolbarVisibility.resolve(
      inputIsEmpty: false, panelIsOpen: false,
      candidatesAreExpanded: true, hasSuggestions: true
    )
    XCTAssertFalse(state.showsFunctionBar)
    XCTAssertTrue(state.showsCandidateBar)
    XCTAssertFalse(state.showsSuggestions)
  }
}
