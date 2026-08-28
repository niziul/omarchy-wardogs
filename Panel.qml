// Wardogs Zone — armory browser + live WARDOGS build status fed by the public
// wardogs.zone API (weather-plugin pattern: curl in a Process, curl -fsS
// --max-time, bounded retries, last-good data kept on failure).
//
// Left click opens the armory popup · right click settings · middle click a
// free-floating window. Keyboard works everywhere: ↑↓/jk select across the
// list, enter opens the item in the browser, r refresh, s settings, q quit
// the search field, esc close.

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "components"

Panel {
  id: root

  moduleName: "niziul.wardogs"
  ipcTarget: "niziul.wardogs"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // --- state -------------------------------------------------------------
  property var items: []
  property var health: ({ ok: false, version: "", build: "", env: "" })
  // Bar pill: glyph + short build version so the live build is visible at a
  // glance; tooltip carries the full picture.
  readonly property string label: root.health.version !== ""
    ? "󰊓 " + Model.shortVersion(root.health.version)
    : "󰊓"
  readonly property string barTooltip: {
    var bits = ["Wardogs Zone"]
    if (root.health.version !== "") bits.push("build " + root.health.version)
    if (root.items.length > 0) bits.push(root.items.length + " items")
    bits.push(root.onlineText)
    return bits.join(" · ")
  }
  readonly property bool showInBar: root.setting("alwaysShow", true) === true || root.health.ok
  property bool settingsMode: false
  property bool newsMode: false
  property bool winNewsMode: false
  property bool winOpen: false
  // Keyboard/mouse coexistence: the selection ring only tracks the cursor
  // while keyboard navigation is active; mouse hover suspends it.
  property bool keyboardMode: true
  property int panelCursor: 0
  property int winCursor: 0
  property var draftSettings: ({})
  property string settingsStatusText: ""
  property string activeKind: ""
  property string searchText: ""
  property int indexRetries: 0
  property int healthRetries: 0
  property string seenVersion: ""
  property bool seenFileLoaded: false
  property var news: []
  property int newsRetries: 0
  property string newsSeenGuid: ""
  property bool newsSeenFileLoaded: false

  // --- item icons ----------------------------------------------------------
  // Artwork lives at https://wardogs.zone/game/icons/{id}.png. Downloaded
  // lazily (per visible category, or all at once via the settings button)
  // into the cache dir and reused forever afterwards.
  readonly property string iconDir: Quickshell.env("HOME") + "/.cache/wardogs-plugin/icons"
  property var cachedIcons: ({})       // icon file names already on disk
  property int iconEpoch: 0            // bumped when the cache view changes
  property var iconQueue: []           // pending item ids
  property string iconFetchingId: ""   // id currently downloading
  property var failedIcons: ({})       // ids whose icon 404'd; skipped this session
  readonly property int iconsPending: root.iconQueue.length + (root.iconFetchingId !== "" ? 1 : 0)

  // Icon-forward grid: tiles per row for the popup and the standalone window.
  readonly property int panelGridColumns: 4
  readonly property int winGridColumns: 5

  // --- derived & theming ---------------------------------------------------
  readonly property string stateFile: Quickshell.env("HOME") + "/.cache/wardogs-plugin/seen.json"
  readonly property string indexCacheFile: Quickshell.env("HOME") + "/.cache/wardogs-plugin/index.json"
  readonly property string newsCacheFile: Quickshell.env("HOME") + "/.cache/wardogs-plugin/news.json"
  readonly property string newsSeenFilePath: Quickshell.env("HOME") + "/.cache/wardogs-plugin/news-seen.json"
  readonly property string notifyBin: (Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy") + "/bin/omarchy-notification-send"
  readonly property color fg: root.bar ? root.bar.foreground : Color.foreground
  readonly property color dim: Qt.rgba(fg.r, fg.g, fg.b, 0.62)
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
  readonly property int maxStdioBytes: 524288
  // Style.cornerRadius mirrors Hyprland's decoration:rounding, which is 0 on
  // this setup. The plugin pins its own radius so button corners stay
  // consistent regardless of theme/Hyprland changes — 0 keeps them square.
  readonly property real cornerRadius: 0

  readonly property int refreshSeconds: {
    var v = Number(root.setting("refreshIntervalSec", 300))
    if (!isFinite(v)) v = 300
    return Math.round(clamp(v, 60, 86400))
  }
  readonly property var filtered: Model.filterItems(root.items, root.activeKind, root.searchText)
  readonly property string onlineText: root.health.ok ? "online" : "offline"
  readonly property bool indexLoading: indexProc.running || indexRetryTimer.running

  property string kinds: ""

  // --- data loading (weather pattern: curl + retry + last-good kept) -------
  function refresh() {
    root.indexRetries = 0
    root.healthRetries = 0
    root.newsRetries = 0
    if (!indexProc.running) indexProc.running = true
    if (!healthProc.running) healthProc.running = true
    if (!newsProc.running) newsProc.running = true
  }

  function onIndex(raw) {
    var parsed = Model.parseIndex(root.truncateStdio(raw))
    if (!parsed || parsed.length === 0) { root.scheduleIndexRetry(); return }
    root.items = parsed
    root.kinds = Model.kindsList(parsed).join(",")
    // Keep the raw payload on disk so the next shell start can show the
    // armory instantly (and offline) before the network answers.
    indexCache.setText(String(raw || ""))
    if (root.activeKind === "" && root.kinds) {
      root.activeKind = root.setting("defaultKind", "weapon") || "weapon"
    }
  }

  // Boot from the cached index when there is no live data yet; the fetch
  // above then replaces it with a fresh copy.
  function onCacheLoaded(raw) {
    if (root.items.length > 0) return
    var parsed = Model.parseIndex(root.truncateStdio(raw))
    if (!parsed || parsed.length === 0) return
    root.items = parsed
    root.kinds = Model.kindsList(parsed).join(",")
    if (root.activeKind === "" && root.kinds) {
      root.activeKind = root.setting("defaultKind", "weapon") || "weapon"
    }
  }

  function scheduleIndexRetry() {
    if (root.indexRetries >= 3) return
    root.indexRetries++
    indexRetryTimer.restart()
  }

  function onHealth(raw) {
    var h = Model.parseHealth(root.truncateStdio(raw))
    if (!h.ok) { root.scheduleHealthRetry(); return }
    var versionChanged = root.health.version !== "" && root.health.version !== h.version
    root.health = h
    // Offer the change to the seen-version watcher; it decides on notify.
    root.maybeNotifyNewVersion(versionChanged)
  }

  function scheduleHealthRetry() {
    if (root.healthRetries >= 3) return
    root.healthRetries++
    healthRetryTimer.restart()
  }

  function onNews(raw) {
    var parsed = Model.parseRss(root.truncateStdio(raw))
    if (!parsed || parsed.length === 0) { root.scheduleNewsRetry(); return }
    root.news = parsed
    newsCache.setText(JSON.stringify(parsed))
    root.maybeNotifyNewNews()
  }

  function onNewsCacheLoaded(raw) {
    if (root.news.length > 0) return
    var parsed = Model.parseNewsCache(root.truncateStdio(raw))
    if (!parsed || parsed.length === 0) return
    root.news = parsed
  }

  function scheduleNewsRetry() {
    if (root.newsRetries >= 3) return
    root.newsRetries++
    newsRetryTimer.restart()
  }

  function maybeNotifyNewNews() {
    var newest = Model.newestGuid(root.news)
    if (newest === "") return
    if (!root.newsSeenFileLoaded) {
      newsSeenFile.reload()
      return
    }
    if (root.newsSeenGuid !== "" && root.newsSeenGuid !== newest) {
      if (root.setting("notifyOnNewNews", true) === true)
        sendNotification("New on Wardogs Zone", root.news[0].title)
    }
    if (root.newsSeenGuid !== newest) {
      root.newsSeenGuid = newest
      newsSeenFile.setText(JSON.stringify({ guid: newest }))
    }
  }

  function onNewsSeenLoaded(raw) {
    var g = ""
    try {
      var data = JSON.parse(String(raw || "{}"))
      g = data && data.guid ? String(data.guid) : ""
    } catch (e) {}
    root.newsSeenFileLoaded = true
    root.newsSeenGuid = g
    if (root.news.length > 0) root.maybeNotifyNewNews()
  }

  function truncateStdio(raw) {
    var s = String(raw || "")
    return s.length > root.maxStdioBytes ? s.substring(0, root.maxStdioBytes) : s
  }

  function sendNotification(title, body) {
    Quickshell.execDetached([root.notifyBin, title, body])
  }

  // Seen-version persistence via the local state file (FileView for reads, a
  // tiny python helper for writes). Notifies only when we already had a seen
  // version that differs from the newly reported one.
  function maybeNotifyNewVersion(versionChanged) {
    var current = root.health.version
    if (current === "") return
    if (!root.seenFileLoaded) {
      seenFile.reload()
      root.seenVersion = current
    } else if (versionChanged && root.seenVersion !== "" && root.seenVersion !== current) {
      root.seenVersion = current
      persistSeen(current)
      if (root.setting("notifyOnNewVersion", true) === true)
        sendNotification("Wardogs build " + current, "The WARDOGS game build changed; the wardogs.zone database may be updating.")
    } else if (root.seenVersion !== current) {
      root.seenVersion = current
      persistSeen(current)
    }
  }

  function onSeenLoaded(raw) {
    var v = ""
    try {
      var data = JSON.parse(String(raw || "{}"))
      v = data && data.version ? String(data.version) : ""
    } catch (e) {}
    root.seenFileLoaded = true
    root.seenVersion = v
    if (root.health.version !== "" && v !== root.health.version)
      persistSeen(root.health.version)
  }

  function persistSeen(version) {
    persistProc.command = ["python3", pathFromUrl(Qt.resolvedUrl("scripts/persist.py")), "write-version", "--version", version]
    if (!persistProc.running) persistProc.running = true
  }

  function pathFromUrl(url) {
    var value = String(url || "")
    if (value.indexOf("file://") === 0) return decodeURIComponent(value.substring(7))
    return value
  }

  // --- browsing actions ------------------------------------------------------
  function openItem(url) {
    if (url) root.bar.run("xdg-open '" + String(url) + "'")
  }

  function openHub() {
    root.bar.run("xdg-open 'https://wardogs.zone/loadouts/hub'")
  }

  // Big free-floating window (middle-click on the bar pill, or IPC).
  function toggleWindow() {
    root.winOpen = !root.winOpen
    if (root.winOpen) {
      root.winNewsMode = false
      root.refresh()
      root.requestVisibleIcons()
    }
  }

  // --- item icons ------------------------------------------------------------
  // Local file url for an id, or "" while the icon is not cached yet. Reads
  // iconEpoch so callers' bindings re-run once downloads land, and appends it
  // as a query so Image reloads the file after an in-place whitespace/normalize
  // pass (same path, new cache key) instead of serving stale pixels.
  function iconFileUrl(id) {
    var epoch = root.iconEpoch
    var name = Model.iconFileName(id)
    if (name === "" || epoch < 0 || !root.cachedIcons[name]) return ""
    return "file://" + root.iconDir + "/" + name + "?v=" + epoch
  }

  function requestIcon(id) {
    var name = Model.iconFileName(id)
    if (name === "" || root.cachedIcons[name]) return
    if (root.failedIcons[id] || root.iconFetchingId === id) return
    if (root.iconQueue.indexOf(id) !== -1) return
    root.iconQueue = root.iconQueue.concat([id])
    kickIconFetch()
  }

  function kickIconFetch() {
    if (root.iconFetchingId !== "" || root.iconQueue.length === 0) return
    var id = root.iconQueue[0]
    root.iconQueue = root.iconQueue.slice(1)
    root.iconFetchingId = id
    iconFetchProc.command = iconFetchCommand(id)
    iconFetchProc.running = true
  }

  // Atomic download + normalize: curl -f writes no body on 404, the .part
  // rename keeps half-written files out of the cache, and magick pads every
  // icon onto a uniform 96x96 transparent square AND whitens the artwork so
  // tiles render at a consistent size regardless of the source dimensions
  // and re-tint cleanly to the theme foreground (alpha-mask + ColorOverlay).
  // Exit 0 only when the file actually landed.
  function iconFetchCommand(id) {
    var dest = root.iconDir + "/" + Model.iconFileName(id)
    var url = Model.iconUrlFor(id)
    return ["sh", "-c",
      "mkdir -p \"${2%/*}\"; if curl -fsS --max-time 10 -o \"$2.part\" \"$1\"; then magick \"$2.part\" -alpha set -background none -channel RGB -fill white -colorize 100% -resize '96x96>' -extent 96x96 \"$2\" && rm -f \"$2.part\" || { mv \"$2.part\" \"$2\"; }; else rm -f \"$2.part\"; exit 1; fi",
      "sh", url, dest]
  }

  // Queue icons for whatever the user is currently looking at. No-op while
  // every surface showing the list is closed, so shell startup stays offline.
  function requestVisibleIcons() {
    if (!root.opened && !root.winOpen) return
    for (var i = 0; i < root.filtered.length; i++) requestIcon(root.filtered[i].id)
  }

  function prefetchAllIcons() {
    for (var i = 0; i < root.items.length; i++) requestIcon(root.items[i].id)
  }

  // --- keyboard cursor --------------------------------------------------------
  property int navTotal: root.filtered.length

  onNavTotalChanged: {
    if (root.panelCursor >= root.navTotal) root.panelCursor = Math.max(0, root.navTotal - 1)
    if (root.winCursor >= root.navTotal) root.winCursor = Math.max(0, root.navTotal - 1)
    ensurePanelCursorVisible()
  }

  // Grid navigation: dx moves one column, dy moves one full row.
  function moveCursor(which, dx, dy) {
    root.keyboardMode = true
    if (root.navTotal === 0) return
    var cols = which === "win" ? root.winGridColumns : root.panelGridColumns
    var cur = which === "win" ? root.winCursor : root.panelCursor
    var next = clamp(cur + (dx || 0) + (dy || 0) * cols, 0, root.navTotal - 1)
    if (which === "win") { root.winCursor = next; ensureWinCursorVisible() }
    else { root.panelCursor = next; ensurePanelCursorVisible() }
  }

  // Keep the keyboard-selected row on screen while arrowing through the list.
  function ensurePanelCursorVisible() {
    var item = panelRepeater.itemAt(root.panelCursor)
    if (!item) return
    var y = item.mapToItem(scroller.contentItem, 0, 0).y
    if (y < scroller.contentY + Style.space(4))
      scroller.contentY = Math.max(0, y - Style.space(36))
    else if (y + item.height > scroller.contentY + scroller.height - Style.space(4))
      scroller.contentY = y + item.height - scroller.height + Style.space(8)
  }

  function ensureWinCursorVisible() {
    var item = winRepeater.itemAt(root.winCursor)
    if (!item) return
    var y = item.mapToItem(winScroller.contentItem, 0, 0).y
    if (y < winScroller.contentY + Style.space(4))
      winScroller.contentY = Math.max(0, y - Style.space(36))
    else if (y + item.height > winScroller.contentY + winScroller.height - Style.space(4))
      winScroller.contentY = y + item.height - winScroller.height + Style.space(8)
  }

  function activateCursor(which) {
    var i = which === "win" ? root.winCursor : root.panelCursor
    if (i < 0 || i >= root.filtered.length) return
    openItem(Model.itemUrl(root.filtered[i].id))
  }

  // --- settings ----------------------------------------------------------------
  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }

  function cloneObject(value, fallback) {
    try { return JSON.parse(JSON.stringify(value)) } catch (e) { return fallback }
  }

  function normalizedSettings(source) {
    var next = cloneObject(source, {}) || {}
    var interval = Number(next.refreshIntervalSec === undefined || next.refreshIntervalSec === null ? 300 : next.refreshIntervalSec)
    next.refreshIntervalSec = Math.round(clamp(isFinite(interval) ? interval : 300, 60, 86400))
    next.alwaysShow = next.alwaysShow !== false
    next.notifyOnNewVersion = next.notifyOnNewVersion !== false
    next.notifyOnNewNews = next.notifyOnNewNews !== false
    next.defaultKind = String(next.defaultKind || "weapon")
    next.filterText = String(next.filterText || "")
    return next
  }

  function canPersistSettings() {
    return !!(bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
  }

  function draftValue(name, fallback) {
    var value = draftSettings ? draftSettings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function setDraftValue(name, value) {
    var next = normalizedSettings(draftSettings)
    next[name] = value
    draftSettings = next
  }

  function openSettings() {
    draftSettings = normalizedSettings(settings)
    settingsStatusText = ""
    settingsMode = true
    newsMode = false
    open()
    focusPanelKeys()
  }

  function showMain() {
    settingsMode = false
    newsMode = false
    settingsStatusText = ""
    focusPanelKeys()
  }

  function openNews() {
    newsMode = true
    settingsMode = false
    open()
    focusPanelKeys()
  }

  // The popup surface maps asynchronously, so a single callLater focus can
  // fire before the layer-shell window exists and silently no-op. Retry for
  // a bounded time until the key catcher actually holds active focus.
  function focusPanelKeys() {
    focusRetryTimer.attempts = 0
    focusRetryTimer.restart()
  }

  Timer {
    id: focusRetryTimer
    interval: 40
    repeat: true
    property int attempts: 0
    onTriggered: {
      if (!keyCatcher || keyCatcher.activeFocus || attempts > 25) { stop(); return }
      attempts++
      keyCatcher.forceActiveFocus()
    }
  }

  readonly property var settingsItems: [alwaysShowToggle, notifyToggle, notifyNewsToggle, filterField, refreshField]

  function currentSettingsIndex() {
    var win = contentColumn && contentColumn.Window.window ? contentColumn.Window.window : null
    if (!win || !win.activeFocusItem) return -1
    var it = win.activeFocusItem
    while (it) {
      var idx = settingsItems.indexOf(it)
      if (idx !== -1) return idx
      it = it.parent
    }
    return -1
  }

  // Focused settings control, or the first one when nothing is focused yet —
  // Enter always has something sensible to activate.
  function currentSettingsItem() {
    var idx = currentSettingsIndex()
    if (idx === -1) idx = 0
    return settingsItems[idx] || null
  }

  function moveSettingsFocus(delta) {
    var cur = currentSettingsIndex()
    var next = ((cur < 0 ? (delta > 0 ? -1 : 0) : cur) + delta + settingsItems.length) % settingsItems.length
    if (settingsItems[next]) settingsItems[next].forceActiveFocus()
  }

  function saveSettings() {
    var next = normalizedSettings(draftSettings)
    draftSettings = next
    root.settings = next
    if (canPersistSettings()) bar.shell.updateEntryInline(root.moduleName, next)
    // Apply immediately — the saved default is what the user expects to see.
    root.activeKind = next.defaultKind || "weapon"
    root.searchText = String(next.filterText || "")
    settingsStatusText = "Saved"
  }

  // --- bar trigger ------------------------------------------------------------
  // Settings arrive after construction (bar injects them) and change on
  // save; re-apply the persisted defaults both times.
  onSettingsChanged: {
    root.activeKind = root.setting("defaultKind", "weapon") || "weapon"
    root.searchText = String(root.setting("filterText", "") || "")
  }

  onOpenedChanged: {
    if (!opened) return
    refresh()
    requestVisibleIcons()
    // Keyboard nav owns focus on open; "/" or a click moves it to search.
    focusPanelKeys()
  }
  onWinOpenChanged: requestVisibleIcons()
  onActiveKindChanged: {
    root.panelCursor = 0
    root.winCursor = 0
    requestVisibleIcons()
  }
  onSearchTextChanged: {
    root.panelCursor = 0
    root.winCursor = 0
    requestVisibleIcons()
  }

  Timer {
    id: refreshTimer
    interval: root.refreshSeconds * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: indexRetryTimer
    interval: 2500
    onTriggered: if (!indexProc.running) indexProc.running = true
  }

  Timer {
    id: healthRetryTimer
    interval: 2500
    onTriggered: if (!healthProc.running) healthProc.running = true
  }

  Timer {
    id: newsRetryTimer
    interval: 2500
    onTriggered: if (!newsProc.running) newsProc.running = true
  }

  Process {
    id: indexProc
    command: ["curl", "-fsS", "--max-time", "5", "https://wardogs.zone/api/search-index"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.onIndex(root.truncateStdio(text))
    }
  }

  Process {
    id: healthProc
    command: ["curl", "-fsS", "--max-time", "5", "https://wardogs.zone/healthz"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.onHealth(root.truncateStdio(text))
    }
  }

  Process {
    id: newsProc
    command: ["curl", "-fsS", "--max-time", "5", "https://wardogs.zone/news/rss.xml"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.onNews(root.truncateStdio(text))
    }
  }

  // Read the persisted seen-version from the local state file (weather
  // FileView pattern; no network, no shell execution of remote content).
  FileView {
    id: seenFile
    path: root.stateFile
    watchChanges: false
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.onSeenLoaded(text())
    onLoadFailed: root.onSeenLoaded("{}")
  }

  // Cached copy of the last successful /api/search-index payload (FileView
  // setText writes atomically; clipboard/agents plugins use the same shape).
  FileView {
    id: indexCache
    path: root.indexCacheFile
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.onCacheLoaded(text())
    onLoadFailed: root.onCacheLoaded("")
  }

  FileView {
    id: newsCache
    path: root.newsCacheFile
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.onNewsCacheLoaded(text())
    onLoadFailed: root.onNewsCacheLoaded("")
  }

  FileView {
    id: newsSeenFile
    path: root.newsSeenFilePath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.onNewsSeenLoaded(text())
    onLoadFailed: root.onNewsSeenLoaded("{}")
  }

  // Tiny python state helper (local file only; see scripts/persist.py).
  Process {
    id: persistProc
  }

  // One-shot cache pass at startup: migrate any pre-normalization icons
  // onto the uniform 96x96 square AND whiten them into an alpha mask so the
  // ColorOverlay tint always yields full theme-foreground contrast (idempotent
  // — re-running on already-whitened files is a no-op), then learn which files
  // are on disk so they render instantly without touching the network.
  Process {
    id: iconScanProc
    command: ["sh", "-c",
      "mkdir -p \"$1\"; mogrify -channel RGB -fill white -colorize 100% -alpha set -background none -gravity center -resize '96x96>' -extent 96x96 \"$1\"/*.png 2>/dev/null || true; ls -1 \"$1\" || true",
      "sh", root.iconDir]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var names = {}
        var lines = String(text || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
          var n = lines[i].replace(/^\s+|\s+$/g, "")
          if (n !== "") names[n] = true
        }
        root.cachedIcons = names
        root.iconEpoch = root.iconEpoch + 1
      }
    }
  }

  // Sequential icon downloader; one id at a time keeps the site happy and
  // the queue state trivial to reason about.
  Process {
    id: iconFetchProc
    stdout: StdioCollector {}
    stderr: StdioCollector {}
    onExited: function(exitCode) {
      if (root.iconFetchingId === "") return
      if (exitCode === 0) {
        var name = Model.iconFileName(root.iconFetchingId)
        if (name !== "") {
          var known = cloneObject(root.cachedIcons, {})
          known[name] = true
          root.cachedIcons = known
          root.iconEpoch = root.iconEpoch + 1
        }
      } else {
        var failed = cloneObject(root.failedIcons, {})
        failed[root.iconFetchingId] = true
        root.failedIcons = failed
      }
      root.iconFetchingId = ""
      kickIconFetch()
    }
  }

  Component.onCompleted: {
    root.activeKind = root.setting("defaultKind", "weapon")
    root.searchText = root.setting("filterText", "")
    seenFile.reload()
    indexCache.reload()
    newsCache.reload()
    newsSeenFile.reload()
    iconScanProc.running = true
    root.refresh()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(Style.space(520))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: searchInput.activeFocus
      // Esc backs out of settings/news first; only then closes the panel.
      onCloseRequested: (root.settingsMode || root.newsMode) ? root.showMain() : root.close()
      onMoveRequested: function(dx, dy) {
        if (root.newsMode) return
        if (root.settingsMode) {
          if (dy !== 0) root.moveSettingsFocus(dy)
          return
        }
        if (dx === 0 && dy === 0) return
        root.moveCursor("panel", dx, dy)
      }
      onTabRequested: function(direction) {
        if (root.settingsMode) root.moveSettingsFocus(direction)
      }
      onActivateRequested: function() {
        if (root.newsMode) return
        if (!root.settingsMode) { root.activateCursor("panel"); return }
        var cur = root.currentSettingsItem()
        if (cur && typeof cur.clicked === "function") cur.clicked()
      }
      onTextKey: function(t) {
        if ((t === "r" || t === "R") && !root.settingsMode) root.refresh()
        else if (t === "s" || t === "S") { root.settingsMode ? root.saveSettings() : root.openSettings() }
        else if (t === "h" || t === "H") { if (!root.settingsMode) root.openHub() }
        else if (t === "/" && !root.settingsMode && !root.newsMode) {
          searchInput.forceActiveFocus()
          searchInput.cursorPosition = searchInput.text.length
        }
      }
    }

    ColumnLayout {
      id: contentColumn
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      spacing: Style.space(12)

      RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Item {
          Layout.fillWidth: true
          implicitHeight: headerHero.implicitHeight

          PanelHero {
            id: headerHero
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            title: root.settingsMode ? "Wardogs Settings" : root.newsMode ? "Wardogs News" : "Wardogs Zone"
            meta: (root.settingsMode || root.newsMode) ? "" : (root.health.version ? "Build " + root.health.version + " · " + root.onlineText : "loading…")
            foreground: root.fg
            fontFamily: root.fontFamily
            iconComponent: heroIconComponent
          }
        }

        Button {
          visible: !root.settingsMode
          radius: root.cornerRadius
          text: "\uF021"
          tooltipText: "Refresh"
          foreground: root.fg
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          onClicked: root.refresh()
        }

        Button {
          visible: !root.settingsMode && !root.newsMode
          radius: root.cornerRadius
          text: "\uF013"
          tooltipText: "Open settings"
          foreground: root.fg
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          onClicked: root.openSettings()
        }

        Button {
          visible: !root.settingsMode && !root.newsMode
          radius: root.cornerRadius
          text: "\uF09E"
          tooltipText: "News feed"
          foreground: root.fg
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          onClicked: root.openNews()
        }

        Button {
          visible: root.settingsMode || root.newsMode
          radius: root.cornerRadius
          text: "Back"
          tooltipText: "Back to armory"
          foreground: root.fg
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          onClicked: root.showMain()
        }

        Button {
          visible: root.settingsMode
          radius: root.cornerRadius
          text: "Save"
          tooltipText: "Save settings"
          foreground: root.fg
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          active: true
          onClicked: root.saveSettings()
        }
      }

      PanelSeparator { Layout.fillWidth: true; foreground: root.fg }

      SiteLinks {
        visible: !root.settingsMode && !root.newsMode
        Layout.fillWidth: true
        fg: root.fg
        dim: root.dim
        fontFamily: root.fontFamily
        onOpenRequested: function(url) { root.openItem(url) }
      }

      Flickable {
        id: scroller
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        contentWidth: width
        contentHeight: bodyColumn.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        HoverHandler {
          onHoveredChanged: if (hovered) root.panelCursor = Math.max(root.panelCursor, 0)
        }

          ColumnLayout {
            id: bodyColumn
            // Small inset so focus/selection borders never touch the
            // Flickable's clip edge and get sliced.
            x: Style.space(2)
            width: scroller.width - Style.space(4)
            spacing: Style.space(12)

            // ---------- armory ----------
            ColumnLayout {
              visible: !root.settingsMode && !root.newsMode
              Layout.fillWidth: true
              spacing: Style.space(8)

            // Categories get a full-width row; the search field gets its own
            // row below so the pills never get squeezed.
            CategoryPills {
              Layout.fillWidth: true
              items: root.items
              kinds: root.kinds
              activeKind: root.activeKind
              fg: root.fg
              dim: root.dim
              fontFamily: root.fontFamily
              onSetKind: function(k) { root.activeKind = k }
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.space(6)

              TextField {
                id: searchInput
                Layout.fillWidth: true
                placeholderText: "Fuzzy search the armory…  ( / )"
                foreground: root.fg
                accent: Color.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                text: root.searchText
                // Read the field (not the signal arg): this engine binds
                // handler params by the signal's declared name, so a renamed
                // arg arrives undefined.
                onTextEdited: root.searchText = searchInput.text
                Keys.onEscapePressed: searchInput.focus = false
                Keys.onUpPressed: { searchInput.focus = false; root.moveCursor("panel", 0, -1) }
                Keys.onDownPressed: { searchInput.focus = false; root.moveCursor("panel", 0, 1) }
                Keys.onReturnPressed: root.activateCursor("panel")
                Keys.onEnterPressed: root.activateCursor("panel")
              }

              Button {
                visible: root.searchText !== ""
                radius: root.cornerRadius
                text: "\u2715"
                tooltipText: "Clear search"
                foreground: root.fg
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY
                onClicked: {
                  root.searchText = ""
                  searchInput.forceActiveFocus()
                }
              }
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.space(8)

              Text {
                Layout.fillWidth: true
                text: root.items.length === 0
                  ? (root.indexLoading ? "Loading armory…" : "Offline — can't reach wardogs.zone")
                  : (root.filtered.length === 0
                      ? "No items match."
                      : (Model.kindLabel(root.activeKind) + " · " + root.filtered.length + " item(s)"))
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Button {
                visible: root.items.length === 0 && !root.indexLoading
                radius: root.cornerRadius
                text: "Retry"
                tooltipText: "Try fetching the armory again"
                foreground: root.fg
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY
                onClicked: root.refresh()
              }
            }

            GridLayout {
              Layout.fillWidth: true
              Layout.bottomMargin: Style.space(2)
              columns: root.panelGridColumns
              columnSpacing: Style.space(6)
              rowSpacing: Style.space(6)

              HoverHandler {
                onHoveredChanged: if (hovered) root.keyboardMode = false
              }

              Repeater {
                id: panelRepeater
                model: root.filtered

                delegate: ItemTile {
                  required property var modelData
                  required property int index
                  selected: root.keyboardMode && index === root.panelCursor
                  name: modelData.name
                  iconSource: root.iconFileUrl(modelData.id)
                  url: Model.itemUrl(modelData.id)
                  fg: root.fg
                  dim: root.dim
                  fontFamily: root.fontFamily
                  // Clicking a tile moves the keyboard cursor with the mouse.
                  onOpenRequested: {
                    root.panelCursor = index
                    root.openItem(url)
                  }
                  Layout.fillWidth: true
                }
              }
            }
            }

            // ---------- news ----------
            ColumnLayout {
              visible: root.newsMode
              Layout.fillWidth: true
              spacing: Style.space(8)

              Text {
                Layout.fillWidth: true
                visible: root.news.length === 0
                text: root.indexLoading ? "Loading feed…" : "No news yet — offline?"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              NewsList {
                Layout.fillWidth: true
                items: root.news
                maxItems: root.news.length
                compact: false
                fg: root.fg
                dim: root.dim
                fontFamily: root.fontFamily
                onOpenRequested: function(url) { root.openItem(url) }
              }
          }

          // ---------- settings ----------
          ColumnLayout {
            id: settingsSection
            visible: root.settingsMode
            Layout.fillWidth: true
            spacing: Style.space(10)

            Keys.onPressed: function(event) {
              if (event.text === "j") { root.moveSettingsFocus(1); event.accepted = true }
              else if (event.text === "k") { root.moveSettingsFocus(-1); event.accepted = true }
              else if (event.text === "s" || event.text === "S") { root.saveSettings(); event.accepted = true }
              else if (event.key === Qt.Key_Escape) { root.close(); event.accepted = true }
            }

            SectionCard {
              title: "Data"

              ColumnLayout {
                width: parent.width
                spacing: Style.space(8)

                NumberField {
                  id: refreshField
                  property string settingKey: "refreshIntervalSec"
                  label: "Refresh every (seconds)"
                  value: Number(root.draftValue("refreshIntervalSec", 300))
                  from: 60
                  to: 86400
                  stepSize: 60
                  fieldWidth: parent.width
                  foreground: root.fg
                  accent: Color.accent
                  fontFamily: root.fontFamily
                  onModified: function(value) { root.setDraftValue("refreshIntervalSec", value) }
                }

                // Pick the startup category from the kinds the API actually
                // reported — no free-text ids to mistype.
                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(4)

                  Text {
                    text: "Default category"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }

                  CategoryPills {
                    Layout.fillWidth: true
                    items: root.items
                    kinds: root.kinds
                    activeKind: String(root.draftValue("defaultKind", "weapon"))
                    fg: root.fg
                    dim: root.dim
                    fontFamily: root.fontFamily
                    onSetKind: function(k) { root.setDraftValue("defaultKind", k) }
                  }
                }

                TextField {
                  Layout.fillWidth: true
                  id: filterField
                  property string settingKey: "filterText"
                  placeholderText: "default filter (empty = none)"
                  text: String(root.draftValue("filterText", ""))
                  foreground: root.fg
                  accent: Color.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  onTextEdited: root.setDraftValue("filterText", filterField.text)
                }

                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(8)

                  Button {
                    radius: root.cornerRadius
                    text: "Prefetch all icons"
                    tooltipText: "Download every item icon into the local cache"
                    foreground: root.fg
                    fontFamily: root.fontFamily
                    fontSize: Style.font.caption
                    horizontalPadding: Style.spacing.controlPaddingX
                    verticalPadding: Style.spacing.controlPaddingY
                    onClicked: root.prefetchAllIcons()
                  }

                  Text {
                    Layout.fillWidth: true
                    visible: root.iconsPending > 0
                    text: "Fetching icons… " + root.iconsPending + " left"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }
              }
            }

            SectionCard {
              title: "Behavior"

              ColumnLayout {
                width: parent.width
                spacing: Style.space(8)

                Toggle {
                  Layout.fillWidth: true
                  id: alwaysShowToggle
                  label: "Always show icon"
                  description: checked ? "Icon visible even while offline" : "Icon hidden when offline"
                  checked: root.draftValue("alwaysShow", true) === true
                  foreground: root.fg
                  accent: Color.accent
                  fontFamily: root.fontFamily
                  onClicked: root.setDraftValue("alwaysShow", !checked)
                }

                Toggle {
                  Layout.fillWidth: true
                  id: notifyToggle
                  label: "Notify on new build"
                  description: checked ? "Popup when the WARDOGS build version changes" : "No build-change popup"
                  checked: root.draftValue("notifyOnNewVersion", true) === true
                  foreground: root.fg
                  accent: Color.accent
                  fontFamily: root.fontFamily
                  onClicked: root.setDraftValue("notifyOnNewVersion", !checked)
                }

                Toggle {
                  Layout.fillWidth: true
                  id: notifyNewsToggle
                  label: "Notify on new news"
                  description: checked ? "Popup when Wardogs Zone publishes an article" : "No news popup"
                  checked: root.draftValue("notifyOnNewNews", true) === true
                  foreground: root.fg
                  accent: Color.accent
                  fontFamily: root.fontFamily
                  onClicked: root.setDraftValue("notifyOnNewNews", !checked)
                }

                Text {
                  visible: root.settingsStatusText !== ""
                  Layout.fillWidth: true
                  text: root.settingsStatusText
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  horizontalAlignment: Text.AlignHCenter
                }
              }
             }
           }
         }
       }

      // Help pinned to the bottom of the panel — always visible, never scrolls.
      Text {
        visible: !root.settingsMode
        Layout.fillWidth: true
        text: root.newsMode
          ? "click an article to open it · r refresh · esc back"
          : "←→ ↑↓ · jk hl select · enter open · / search · r refresh · s settings · esc close"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
      }

      Text {
        visible: root.settingsMode
        Layout.fillWidth: true
        text: "j/k or ↑↓ select · enter toggle · s save · esc back"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
      }
     }
   }

  // Settings-only section wrapper.
  component SectionCard: BorderSurface {
    id: section
    property string title: ""
    default property alias content: body.data

    Layout.fillWidth: true
    color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.055)
    borderSpec: Border.flat(Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08), 1)
    radius: Style.cornerRadius
    padding: Style.space(10)
    implicitHeight: body.implicitHeight + contentTopInset + contentBottomInset

    ColumnLayout {
      id: body
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.topMargin: section.contentTopInset
      anchors.bottomMargin: section.contentBottomInset
      anchors.leftMargin: section.contentLeftInset
      anchors.rightMargin: section.contentRightInset
      spacing: Style.space(8)

      Text {
        visible: section.title !== ""
        Layout.fillWidth: true
        text: section.title
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }
  }

  Component {
    id: heroIconComponent

    Item {
      width: Style.font.display
      height: Style.font.display

      // Plugin emblem (ships with the plugin, no network needed). Ships as a
      // white alpha-mask, tinted here to the theme foreground so it matches
      // the bar widget and tinted armory tiles on any theme.
      Image {
        id: heroImg
        anchors.fill: parent
        anchors.margins: Style.space(1)
        source: Qt.resolvedUrl("assets/icon.png")
        asynchronous: true
        fillMode: Image.PreserveAspectFit
        mipmap: true
        smooth: true
      }

      ColorOverlay {
        anchors.fill: heroImg
        visible: heroImg.status === Image.Ready
        source: heroImg
        color: root.fg
      }
    }
  }

  IpcHandler {
    target: "niziul.wardogs.window"
    function toggle() { root.toggleWindow() }
    function open() { if (!root.winOpen) root.toggleWindow() }
    function close() { root.winOpen = false }
  }

  // Standalone quickshell window (middle-click on the bar widget).
  PanelWindow {
    id: taskWindow
    visible: root.winOpen
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "niziul-wardogs-window"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    onVisibleChanged: {
      if (visible) Qt.callLater(function() { if (root.winOpen) winKeys.forceActiveFocus() })
      else if (root.opened) root.close()
    }

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, 0.45)

      MouseArea {
        anchors.fill: parent
        onClicked: root.winOpen = false
      }
    }

    Item {
      id: winKeys
      anchors.fill: parent
      focus: true

      Keys.onEscapePressed: {
        if (root.winNewsMode) root.winNewsMode = false
        else root.winOpen = false
      }
      Keys.onLeftPressed: if (!root.winNewsMode) root.moveCursor("win", -1, 0)
      Keys.onRightPressed: if (!root.winNewsMode) root.moveCursor("win", 1, 0)
      Keys.onUpPressed: if (!root.winNewsMode) root.moveCursor("win", 0, -1)
      Keys.onDownPressed: if (!root.winNewsMode) root.moveCursor("win", 0, 1)
      Keys.onReturnPressed: if (!root.winNewsMode) root.activateCursor("win")
      Keys.onEnterPressed: if (!root.winNewsMode) root.activateCursor("win")
      Keys.onSpacePressed: if (!root.winNewsMode) root.activateCursor("win")
      Keys.onPressed: function(event) {
        if (event.modifiers & Qt.ControlModifier || event.modifiers & Qt.AltModifier) return
        if (event.key === Qt.Key_R) root.refresh()
        else if (root.winNewsMode) return
        else if (event.key === Qt.Key_J || event.text === "j") root.moveCursor("win", 0, 1)
        else if (event.key === Qt.Key_K || event.text === "k") root.moveCursor("win", 0, -1)
        else if (event.text === "h" || event.text === "H") root.moveCursor("win", -1, 0)
        else if (event.text === "l" || event.text === "L") root.moveCursor("win", 1, 0)
        else if (event.text === "/") {
          winSearchInput.forceActiveFocus()
          winSearchInput.cursorPosition = winSearchInput.text.length
        }
      }

      BorderSurface {
        id: winCard
        readonly property real sw: taskWindow.screen ? taskWindow.screen.width : Screen.width
        readonly property real sh: taskWindow.screen ? taskWindow.screen.height : Screen.height
        anchors.centerIn: parent
        width: Math.max(Style.space(500), Math.min(sw * 0.5, sw - Style.space(80)))
        height: Math.max(Style.space(420), Math.min(sh * 0.7, sh - Style.space(80)))
        color: Color.popups.background
        radius: Style.cornerRadius
        padding: Style.space(14)

        ColumnLayout {
          id: winCardContent
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          anchors.topMargin: winCard.contentTopInset
          anchors.bottomMargin: winCard.contentBottomInset
          anchors.leftMargin: winCard.contentLeftInset
          anchors.rightMargin: winCard.contentRightInset
          spacing: Style.space(12)

          RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Item {
              Layout.fillWidth: true
              implicitHeight: winHero.implicitHeight

              PanelHero {
                id: winHero
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                title: root.winNewsMode ? "Wardogs News" : "Wardogs Zone"
                meta: root.winNewsMode ? "" : (root.health.version ? "Build " + root.health.version + " · " + root.onlineText : "loading…")
                foreground: root.fg
                fontFamily: root.fontFamily
                iconComponent: heroIconComponent
              }
            }

            Button {
              radius: root.cornerRadius
              text: "\uF021"
              tooltipText: "Refresh"
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY
              onClicked: root.refresh()
            }

            Button {
              radius: root.cornerRadius
              text: "\uF1CA"
              tooltipText: "Open loadout hub"
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY
              onClicked: root.openHub()
            }

            Button {
              visible: !root.winNewsMode
              radius: root.cornerRadius
              text: "\uF09E"
              tooltipText: "News feed"
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY
              onClicked: root.winNewsMode = true
            }

            Button {
              visible: root.winNewsMode
              radius: root.cornerRadius
              text: "Back"
              tooltipText: "Back to armory"
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY
              onClicked: root.winNewsMode = false
            }

            Button {
              radius: root.cornerRadius
              text: "\u2715"
              tooltipText: "Close"
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY
              onClicked: root.winOpen = false
            }
          }

          PanelSeparator { Layout.fillWidth: true; foreground: root.fg }

          SiteLinks {
            visible: !root.winNewsMode
            Layout.fillWidth: true
            fg: root.fg
            dim: root.dim
            fontFamily: root.fontFamily
            onOpenRequested: function(url) { root.openItem(url) }
          }

          CategoryPills {
            visible: !root.winNewsMode
            Layout.fillWidth: true
            items: root.items
            kinds: root.kinds
            activeKind: root.activeKind
            fg: root.fg
            dim: root.dim
            fontFamily: root.fontFamily
            onSetKind: function(k) { root.activeKind = k }
          }

          RowLayout {
            visible: !root.winNewsMode
            Layout.fillWidth: true
            spacing: Style.space(6)

            TextField {
              id: winSearchInput
              Layout.fillWidth: true
              placeholderText: "Fuzzy search the armory…  ( / )"
              foreground: root.fg
              accent: Color.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              text: root.searchText
              onTextEdited: root.searchText = winSearchInput.text
              Keys.onEscapePressed: winKeys.forceActiveFocus()
              Keys.onUpPressed: { winSearchInput.focus = false; root.moveCursor("win", 0, -1) }
              Keys.onDownPressed: { winSearchInput.focus = false; root.moveCursor("win", 0, 1) }
              Keys.onReturnPressed: root.activateCursor("win")
              Keys.onEnterPressed: root.activateCursor("win")
            }

            Button {
              visible: root.searchText !== ""
              radius: root.cornerRadius
              text: "\u2715"
              tooltipText: "Clear search"
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY
              onClicked: {
                root.searchText = ""
                winSearchInput.forceActiveFocus()
              }
            }
          }

          Flickable {
            id: winScroller
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: winList.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
              id: winList
              // Same inset as the popup: keep borders off the clip edge.
              x: Style.space(2)
              width: winScroller.width - Style.space(4)
              spacing: Style.space(8)

              Text {
                visible: !root.winNewsMode && root.filtered.length === 0
                Layout.fillWidth: true
                text: "No items match."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                horizontalAlignment: Text.AlignHCenter
              }

              GridLayout {
                visible: !root.winNewsMode
                Layout.fillWidth: true
                Layout.bottomMargin: Style.space(2)
                columns: root.winGridColumns
                columnSpacing: Style.space(6)
                rowSpacing: Style.space(6)

                HoverHandler {
                  onHoveredChanged: if (hovered) root.keyboardMode = false
                }

                Repeater {
                  id: winRepeater
                  model: root.filtered

                  delegate: ItemTile {
                    required property var modelData
                    required property int index
                    selected: root.keyboardMode && index === root.winCursor
                    name: modelData.name
                    iconSource: root.iconFileUrl(modelData.id)
                    url: Model.itemUrl(modelData.id)
                    fg: root.fg
                    dim: root.dim
                    fontFamily: root.fontFamily
                    // Clicking a tile moves the keyboard cursor with the mouse.
                    onOpenRequested: {
                      root.winCursor = index
                      root.openItem(url)
                    }
                    Layout.fillWidth: true
                  }
                }
              }

            NewsList {
              visible: root.winNewsMode
              Layout.fillWidth: true
              items: root.news
              maxItems: root.news.length
              compact: false
              fg: root.fg
              dim: root.dim
              fontFamily: root.fontFamily
              onOpenRequested: function(url) { root.openItem(url) }
            }
          }
          }

          // Help pinned to the bottom of the window.
          Text {
            Layout.fillWidth: true
            text: root.winNewsMode
              ? "click an article to open it · r refresh · esc back"
              : "←→ ↑↓ · jk hl select · enter open · / search · r refresh · esc close"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
          }
        }
        }
    }
  }
}
