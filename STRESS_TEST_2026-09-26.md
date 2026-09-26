# SwiftSnips stress test — 2026-09-26

Source method: [Emil Kowalski's break-testing post](https://x.com/emilkowalski/status/2103516287452483885). Populate a working interface with awkward, high-volume data; inspect the actual window; repair what fails; repeat the same check.

## Scope and isolation

The automated tests used temporary libraries. Visual checks used a separate debug bundle and a synthetic private fixture, never the installed app's library. The fixture had 5,000 snippets, including a 128-character trigger, a 17,400-character replacement, an unusual email address, Arabic mixed with English, emoji, multiline text, a date variable, a disabled entry, and a match at row 4,999. The separate debug bundle was closed after testing. No Accessibility permission was granted to it.

## Results

| Check | Result |
| --- | --- |
| Maximum library save and reload | Passed: 5,000 snippets round-tripped; save 0.029 s, load 0.012 s; encoded file 1,048,785 bytes. These are measurements on this Mac, not service guarantees. |
| Keyboard matching at maximum library | Passed: 10,000 unmatched events across 5,000 snippets took 1.949 s, about 0.195 ms per event in the release test process. Both an Arabic trigger and a 128-character trigger were exercised in the test suite. |
| Replacement size boundary | Passed: 1,000,000 bytes accepted; 1,000,001 bytes rejected. |
| Compact app window with maximum library | Passed after repair: list count, selected row, editor, and Save control stayed visible. |
| Search for last row | Passed after repair: `/stress-4999` was visible and selected, with its matching editor content. |
| Long replacement | Passed visually: row preview truncates and editor content remains in its own scrollable area. |
| Arabic, English, email, and emoji | Passed visually without overflow. The trigger's punctuation follows native bidirectional text rendering; stored text and matching order were preserved. |
| No search result | Passed after repair: clear explanation and a working **Clear search** action returned to the full library. |
| Existing core and security behavior | All 21 release tests passed, with 0 failures. |

## Defects found and repaired

1. Filtering a large library could leave an unrelated snippet open while the matching result was offscreen. Search now selects a matching result and uses a lazy sidebar that starts at the filtered list's top.
2. The detail pane used its intrinsic height and was centered inside the split view. In a compact window it could clip the header and footer. The detail pane now fills the actual available height and stays anchored at the top.
3. An empty search result showed the first-use message even when the library contained thousands of snippets. It now states that nothing matched and offers **Clear search**.

## Limits of this run

The matching timing is a core-process measurement; a physical 5,000-snippet expansion through the macOS event tap was not performed. Cross-application paste timing and behavior in every destination app remain separate checks. No GitHub repository was created and the installed `/Applications/SwiftSnips.app` was not replaced during this stress-test run.
