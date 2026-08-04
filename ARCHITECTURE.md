# Riff architecture

Riff is a small native macOS app. Its launcher follows a unidirectional input pipeline so typing never performs I/O or unbounded search work on the main thread.

## Launcher pipeline

1. `LauncherView` forwards text edits to `AppModel`; it does not parse or search.
2. `LauncherQueryClassifier` classifies the text exactly once as applications, calculation, currency, graph, or Unicode/Emoji.
3. `AppModel` cancels obsolete work and publishes one coherent `LauncherState` snapshot.
4. Bounded synchronous work is rendered immediately. Application search, Unicode search, currency requests, and graph sampling run in dedicated cancellable services.
5. Completed work is accepted only when its query still matches the current snapshot.

## Boundaries

- `Launcher/LauncherQuery.swift`: query intents and presentation state.
- `AppModel.swift`: coordination, cancellation, selection, and activation.
- `Services/ApplicationSearch.swift`: pre-normalized, off-main application ranking.
- `Services/UnicodeSearch.swift`: lazy Unicode index and localized search.
- `Services/FunctionPlotter.swift`: off-main graph sampling.
- `UI/LauncherView.swift`: launcher composition and layout only.
- `UI/LauncherResultViews.swift`: reusable rows, tiles, image caches, and clipboard preview.

## Performance invariants

- A synchronous query transition publishes one state snapshot.
- Views do not filter, sort, parse, load files, or sample functions in `body`.
- Search tasks check cancellation and stale results never replace the current query.
- Application names and bundle identifiers are normalized once when indexed.
- Application icons and clipboard preview images are cached.
- Result-driven window resizing is immediate; keystrokes never queue window animations.
- The launcher field focuses on the next main-loop turn without an artificial delay.

Architecture and behavior regressions belong in `LauncherArchitectureTests`, while individual search implementations keep focused service tests.

## Clipboard persistence

1. `ClipboardStore` observes pasteboard changes and owns the UI-facing in-memory snapshot.
2. `ClipboardDatabase` is the only durable clipboard store. It writes `clipboard.sqlite3` in WAL mode under Riff's Application Support directory; there is no item-count or expiration policy.
3. Re-copying identical content replaces its existing row and moves it to the newest position. Deleting one item or clearing history updates SQLite before publishing the UI change.
4. Captured images live in the adjacent managed `clipboard-images` directory. Only files inside that directory may be deleted with their records; file references copied from elsewhere are never removed.
5. Legacy `clipboard.json` data is intentionally neither imported nor backed up. After the new database opens successfully, the legacy file and unreferenced legacy managed images are discarded. Clipboard contents and managed images never leave the Mac.

## Local experience metrics

1. `ExperienceMetricsStore` owns one launcher session at a time and accepts only numeric lifecycle events.
2. `LauncherPanelController` records presentation, focus readiness, and abandonment; successful activations are completed by `AppModel` before their side effect runs.
3. `AppModel` associates a monotonic token with the latest non-empty query. Stale asynchronous work cannot resolve a newer token.
4. Only bounded latency samples and counters are encoded in `UserDefaults`. Query text, app identities, clipboard data, notes, and translations are not accepted by the metrics API.
5. Persistence is coalesced after activity settles so instrumentation never adds synchronous disk work to the typing path.
6. The Settings health section can display, copy, or reset the local aggregate snapshot.

## Note completion pipeline

1. The Markdown `NSTextView` reports text and caret changes to `NotePanelController`.
2. IME marked-text sessions, non-caret selections, blank documents, and disabled completion never start a request.
3. `NoteCompletionModel` cancels stale work, waits for a short typing pause, and sends only bounded context around the caret. Cloud mode uses the configured AI provider; local mode selects the 4B or 9B llama.cpp router model and uses `/v1/chat/completions` with thinking disabled.
4. Streaming deltas update one unobtrusive suggestion. `Tab` is consumed only when that suggestion still matches the exact document and caret snapshot; otherwise AppKit and the active input method receive it normally.
5. Exact repeated contexts reuse a bounded in-memory cache.
6. Local failure is surfaced to the note UI and never causes an implicit cloud fallback.
7. The local router is configured with `models-max=1`, so switching quality levels unloads the previous model instead of retaining both in memory.
