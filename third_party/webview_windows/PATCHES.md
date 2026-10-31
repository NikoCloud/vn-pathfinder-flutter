# Changes from webview_windows 0.4.0

The package has no way to see a download start, and VN Pathfinder needs one to
put a game's archive in the library and follow its progress. WebView2 has the
event, so this copy passes it through.

- `Webview::SetDownloadFolder`, `Webview::CancelDownload`, and a
  `DownloadStarting` handler in `windows/webview.cc`.
- The `setDownloadFolder` and `cancelDownload` methods and the `downloadEvent`
  event in `windows/webview_bridge.cc`.
- `WebviewController.downloads`, `setDownloadFolder`, `cancelDownload` and the
  `WebviewDownload` class in `lib/src/webview.dart`.

The browser retries a dropped download by itself, resuming if the host allows
it, and each try fires `DownloadStarting` again. So a download with the same
address as one in progress keeps its id and file, and sends a `restarted` event.
Earlier tries stay alive until the download ends, because releasing one silences
the events of the try after it.

Nothing changes unless a download folder is set. Everything else is the upstream
package, under its own licence in `LICENSE`.
