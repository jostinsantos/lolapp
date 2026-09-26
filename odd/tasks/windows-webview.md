# Windows WebView support

## Objective
Make the app's existing hidden extraction probes and visible WebView flows work on Windows instead of throwing `A platform implementation for webview_flutter has not been set`.

## Problem and why
The current `main` checkout uses `webview_flutter` plus its Android implementation, but registers no Windows `WebViewPlatform`. The first Windows runtime error occurs when the automatic HLS hidden probe constructs a `WebViewController`; the same unsupported API is also used by seven other app flows. The user identified this as the first known Windows problem after launching the app.

## Scope
- Use a Windows-capable implementation consistent with the existing Android behavior; prior project investigation selected `flutter_inappwebview` 6.1.5 and its endorsed Windows/WebView2 implementation because it supports the required controller, widget, JavaScript bridge, navigation, and user-agent behavior.
- Migrate all eight current WebView call-site files, including the hidden HLS probes, content/discover/download/player extractors, general web player, and TV player.
- Add focused automated coverage and verify Windows plugin registration/build; then launch the app and exercise the reported server-search path if possible.

## Constraints
- User asked to work from Jostin's general `main`; implementation starts from the current `main` commit on a feature branch.
- Preserve the user's local `windows/nuget.exe` and the restored Windows runner manifest/icon, plus Flutter-generated plugin files modified during their run/build attempts.
- Strict TDD: `flutter test`; preference source is prior project instruction/memory `TDD estricto`.
- No remote access, push, pull request, or merge.
- Avoid expanding scope beyond Windows WebView support and required regression tests.

## Authorized scope
The user asked to get the Windows version running, then reported the known `WebViewPlatform.instance` assertion from that running app in this same task. Treat this as authorization to fix this runtime blocker using the already-selected Windows WebView integration.

## Delivery
- Route: delegated direct.
- Trigger evidence: mapping trigger — the runtime call flow and eight call sites span 4+ files; writer trigger — migrating the non-trivial Dart/WebView integration spans multiple files. A read-only mapper completed the map before writing.
- TDD mode: strict; source: project preference `TDD estricto`; runner: `flutter test`.
- Forecast: approximately 500 authored changed lines excluding generated files, based on the equivalent previously implemented migration. User-selected delivery strategy: `feature-branch-chain` (resolved before any commit because the forecast exceeded ~400 lines). This WW-1 change is one work-unit candidate; no commit or PR has been created yet, so slice/commit membership remains pending parent delivery handling.
- Feature branch: `codex/windows-webview-support`, based on current `main`.

## Acceptance criteria
- None of the supported app flows throws the missing `WebViewPlatform` assertion on Windows.
- Hidden extraction probes and visible WebViews preserve navigation, JavaScript messaging/injection, user-agent configuration, and cleanup behavior.
- Android implementation and existing behavior continue to compile.
- Focused Flutter tests pass and Windows build succeeds with the user's local NuGet available on PATH for that process.
- Report any runtime validation not performed.

## Tasks
- [x] WW-1 — Add the Windows-capable WebView adapter and migrate all eight WebView call sites with behavior parity. Route: delegated direct. Trigger: writer trigger (multiple non-trivial Dart files); prep/read research delegated with the writer. Checks: strict TDD using `flutter test`; `flutter analyze` on affected Dart files.
- [ ] WW-2 — Verify generated Windows plugin registration, build, and exercise the server-search HLS probe. Route: delegated direct. Checks: `flutter pub get`, focused tests, `flutter build windows` with `windows/` prepended to PATH for NuGet; interactive Windows runtime check.

## Progress and evidence
- 2026-09-25: Current main verified to still use `webview_flutter ^4.4.0` and `webview_flutter_android ^3.12.0`, with no Windows implementation in the generated registrant. Current lock has `webview_flutter 4.9.0` and Android 3.16.9.
- Read-only mapping traced the screenshot assertion from server-search kickoff through `language_aggregator.dart`, `ExtractorHlsService.buscarFuente`, and `_HiddenProbeState.initState` in `lib/data/extractors/hls/hls_extractor.dart`; controller creation fails because no Windows `WebViewPlatform` is registered.
- Eight current call-site files identified: `lib/data/extractors/hls/hls_extractor.dart`, `lib/data/extractors/providers/content/extractor_hls.dart`, `lib/features/downloads/presentation/extractor_download_page.dart`, `lib/features/player/data/extractor.dart`, `lib/features/player/data/extractor_mobil.dart`, `lib/features/discover/domain/extractor.dart`, `lib/features/player/presentation/web_player_view.dart`, and `lib/features/player/presentation/tv/tv_player_webview.dart`.
- Prior `codex/windows-video-player` implementation and commit `0926d2c` are historical reference only; their changes are absent from current main after the user reset to Jostin's main. This task re-applies the approved approach from the current base.
- Current tree also contains the separately requested Windows runner fixes (`windows/runner/runner.exe.manifest` and `windows/runner/resources/app_icon.ico`) and user-provided `windows/nuget.exe`; generated plugin registrant files are modified from build attempts and must be preserved/inspected, not blindly reverted.
- ✅ WW-1 implementation: Added `lib/data/webview/app_webview.dart` adapter on `flutter_inappwebview` 6.1.5 and migrated all eight current WebView call-site files, including the general mobile web player omitted from the historical seven-file implementation. Migrated six MediaDetector scripts from `postMessage` to the InAppWebView `callHandler` bridge and replaced Android-only media gesture configuration with the adapter setting.
- ✅ WW-1 TDD evidence: Initial `flutter test test/data/webview/app_webview_navigation_test.dart` was RED before implementation because the new adapter and dependency did not exist (unresolved package/source and symbols). After adapter, dependency, and migrations, the same focused test was GREEN (16/16, covering all eight call-site imports, both navigation-policy mappings, and all six media-detector bridges). `flutter pub get` succeeded and resolved `flutter_inappwebview_windows 0.6.0`.
- ✅ WW-1 analysis: `flutter analyze` on the adapter, eight call-site files, and test reports 6 existing info/warning lints and no errors; the diagnostics are the pre-existing `use_build_context_synchronously`, local underscore naming, unnecessary underscores, and unnecessary non-null assertion. No Windows build or interactive runtime validation was run in WW-1; these remain WW-2.
- Generated Windows files were inspected before dependency resolution: the prior working copies matched `HEAD` content despite line-ending status noise. `flutter pub get` then added the InAppWebView Windows plugin to `windows/flutter/generated_plugin_registrant.cc` and `windows/flutter/generated_plugins.cmake`; `generated_plugin_registrant.h` and the user-owned NuGet/runner files were left unchanged.

## Next step
Parent reviews WW-1 evidence and handles the authorized feature-branch-chain delivery/commit policy. Then continue with WW-2: verify Windows build and exercise the server-search HLS probe interactively.

## Relevant files
- `lib/data/extractors/hls/hls_extractor.dart` — screenshot's hidden HLS probe.
- `windows/flutter/generated_plugin_registrant.cc` — current Windows plugin registration (locally modified by Flutter runs).
- `pubspec.yaml` — current WebView dependency constraints.
