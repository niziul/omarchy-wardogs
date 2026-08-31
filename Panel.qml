// Wardogs Zone — armory browser + live WARDOGS build status fed by the public
// wardogs.zone API (weather-plugin pattern: curl in a Process, curl -fsS
// --max-time, bounded retries, last-good data kept on failure).
//
// Left click opens a free-floating, full-width overlay window · right click
// settings · middle click the loadout hub. Keyboard works everywhere:
// ↑↓/jk select across the list, enter opens the item in the browser, r
// refresh, s settings, / search, esc back then close. c marks an item for a
// two-way stat comparison; v opens that comparison (see ComparePanel).

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
    import "Details.js" as Details
    import "Compare.js" as Compare
    import "Hub.js" as Hub
    import "components"

Panel {
    id: root

    moduleName: "niziul.wardogs"
    ipcTarget: "niziul.wardogs"
    manageIpc: true

    property var anchorItem: null
    property var hostWidget: null
    readonly property var barIdentity: hostWidget || root

    // --- state -------------------------------------------------------------
    property var items: []
    property var health: ({
            ok: false,
            version: "",
            build: "",
            env: ""
        })
    // Bar pill: glyph + short build version so the live build is visible at a
    // glance; tooltip carries the full picture.
    // Bare label text — the bar widget paints the emblem image separately and
    // this text to its right (countdown while it lasts, then the build version).
    readonly property string label: {
        var cd = Model.releaseCountdown(root.nowMs);
        if (cd !== "")
            return cd;
        return root.health.version !== "" ? Model.shortVersion(root.health.version) : "";
    }
    readonly property string barTooltip: {
        var bits = ["Wardogs Zone"];
        var cd = Model.releaseCountdown(root.nowMs);
        if (cd !== "")
            bits.push(cd === "LIVE" ? "early access is live" : "early access in " + cd);
        if (root.health.version !== "")
            bits.push("build " + root.health.version);
        if (root.items.length > 0)
            bits.push(root.items.length + " items");
        bits.push(root.onlineText);
        return bits.join(" · ");
    }
    readonly property bool showInBar: root.setting("alwaysShow", true) === true || root.health.ok
    property bool settingsMode: false
    property bool newsMode: false
    // Keyboard/mouse coexistence: the selection ring only tracks the cursor
    // while keyboard navigation is active; mouse hover suspends it.
    property bool keyboardMode: true
    property int winCursor: 0
    property var draftSettings: ({})
    property string settingsStatusText: ""
    property string activeKind: ""
    property string activeSub: ""
    property string searchText: ""
    property int indexRetries: 0
    property int healthRetries: 0
    property string seenVersion: ""
    property bool seenFileLoaded: false
    property var news: []
    property int newsRetries: 0
    property string newsSeenGuid: ""
    property bool newsSeenFileLoaded: false

    // --- stat comparison ----------------------------------------------------
    // Two marked items ("A" and "B") whose normalized details are fetched on
    // demand (per /database/{id} page, see Details.js) and shown side by side.
    // Marking happens from the browse grid with `c`; `v` (or the header button)
    // opens the compare view. Details are cached in-memory for the session and
    // on disk per item so re-comparing is instant and offline-safe.
    property var compareA: null            // first marked filtered row
    property var compareB: null            // second marked filtered row
    property bool compareMode: false       // compare view is the visible body
    property var compareDetailA: null      // normalized detail or null
    property var compareDetailB: null
    property bool compareLoadingA: false
    property bool compareLoadingB: false
    property bool compareErrorA: false
    property bool compareErrorB: false
    property var compareCache: ({})        // id -> normalized detail | false (failed)
    property string compareFetchSlot: ""   // "A" | "B" whose disk cache read is in flight
    property string compareFetchId: ""     // id being read from the disk cache
    property var compareFetchQueue: []     // [{slot,id}] cache reads waiting their turn
    property var compareNetQueue: []       // [{slot,id}] disk misses awaiting the one pair fetch

    // --- loadout hub ----------------------------------------------------------
    // Published builds from wardogs.zone/loadouts/hub: list + per-build
    // detail, fetched live with a disk cache (hub/*.json) and last-good
    // memory, mirroring the news pipeline.
    property bool hubMode: false
    property var hubBuilds: []             // parsed list rows (Hub.parseHubList)
    property string hubBuildId: ""         // "" = list view, else detail for this id
    property var hubBuild: null            // parsed detail for hubBuildId
    property int hubCursor: 0              // list cursor
    property int hubSlotCursor: 0          // detail cursor (flat slot index)
    property bool hubLoading: false
    property bool hubListFailed: false     // live fetch failed; retry on next open
    property string hubError: ""           // detail-view error text
    property var hubDetailCache: ({})      // id -> parsed build (memory, last-good)
    property string hubReadTarget: ""      // "list" | build id whose disk read is in flight
    readonly property string hubDir: Quickshell.env("HOME") + "/.cache/wardogs-plugin/hub"

    // --- stats prefetch (settings) ------------------------------------------
    // Downloads the compare page for every catalog item in id pairs so the
    // details cache is complete and compares open instantly/offline afterwards.
    property var statsQueue: []            // ids still to prefetch
    property var statsBatch: []            // ids in the fetch in flight
    property bool statsPrefetchBusy: false
    property int statsPrefetched: 0        // fetched this session (for the settings readout)
    readonly property bool statsPrefetching: statsPrefetchBusy || statsQueue.length > 0

    // --- item icons ----------------------------------------------------------
    // Artwork lives at https://wardogs.zone/game/icons/{id}.png. Downloaded
    // lazily (per visible category, or all at once via the settings button)
    // into the cache dir and reused forever afterwards.
    readonly property string iconDir: Quickshell.env("HOME") + "/.cache/wardogs-plugin/icons"
    property var cachedIcons: ({})       // icon file names already on disk
    property int iconEpoch: 0            // bumped when the cache view changes
    property int cacheEpoch: 0           // bumped only when files are rewritten in place
    // Ticking clock so the release countdown in the bar label stays current.
    property real nowMs: Date.now()
    property var iconQueue: []           // pending item ids
    property string iconFetchingId: ""   // id currently downloading
    property var failedIcons: ({})       // ids whose icon 404'd; skipped this session
    readonly property int iconsPending: root.iconQueue.length + (root.iconFetchingId !== "" ? 1 : 0)

    // Icon-forward grid: tiles per row for the overlay window.
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
    // Detail pages embed per-item stat JSON that can exceed the index cap, so
    // the compare fetch gets its own (2 MiB) limit before parsing.
    readonly property int maxDetailBytes: 2097152
    readonly property string detailCacheDir: Quickshell.env("HOME") + "/.cache/wardogs-plugin/details"

    function detailCachePath(id) {
        return root.detailCacheDir + "/" + Model.sanitizeId(id) + ".json";
    }
    // Style.cornerRadius mirrors Hyprland's decoration:rounding, which is 0 on
    // this setup. The plugin pins its own radius so button corners stay
    // consistent regardless of theme/Hyprland changes — 0 keeps them square.
    readonly property real cornerRadius: 0
    // Live placeholder: tells the user what the search covers and how big the
    // catalog is, before they type a character.
    readonly property string searchPlaceholder: root.items.length > 0 ? "Search " + root.items.length + " items across all categories…  ( / )" : "Search the armory…  ( / )"

    readonly property int refreshSeconds: {
        var v = Number(root.setting("refreshIntervalSec", 300));
        if (!isFinite(v))
            v = 300;
        return Math.round(clamp(v, 60, 86400));
    }
    // With a query the fuzzy find spans every category and subcategory (the
    // haystack already covers name, type, and caliber); the dropdowns only
    // scope the unsearched browse view.
    readonly property var filtered: root.searchText !== "" ? Model.filterItems(root.items, "", root.searchText) : Model.bySubcategory(Model.filterItems(root.items, root.activeKind, root.searchText), root.activeSub)
    readonly property string onlineText: root.health.ok ? "online" : "offline"
    readonly property bool indexLoading: indexProc.running || indexRetryTimer.running

    property string kinds: ""

    // --- data loading (weather pattern: curl + retry + last-good kept) -------
    function refresh() {
        root.indexRetries = 0;
        root.healthRetries = 0;
        root.newsRetries = 0;
        if (!indexProc.running)
            indexProc.running = true;
        if (!healthProc.running)
            healthProc.running = true;
        if (!newsProc.running)
            newsProc.running = true;
    }

    function onIndex(raw) {
        var parsed = Model.parseIndex(root.truncateStdio(raw));
        if (!parsed || parsed.length === 0) {
            root.scheduleIndexRetry();
            return;
        }
        root.items = parsed;
        root.kinds = Model.kindsList(parsed).join(",");
        // Keep the raw payload on disk so the next shell start can show the
        // armory instantly (and offline) before the network answers.
        indexCache.setText(String(raw || ""));
        if (root.activeKind === "" && root.kinds) {
            root.activeKind = root.setting("defaultKind", "weapon") || "weapon";
        }
    }

    // Boot from the cached index when there is no live data yet; the fetch
    // above then replaces it with a fresh copy.
    function onCacheLoaded(raw) {
        if (root.items.length > 0)
            return;
        var parsed = Model.parseIndex(root.truncateStdio(raw));
        if (!parsed || parsed.length === 0)
            return;
        root.items = parsed;
        root.kinds = Model.kindsList(parsed).join(",");
        if (root.activeKind === "" && root.kinds) {
            root.activeKind = root.setting("defaultKind", "weapon") || "weapon";
        }
    }

    function scheduleIndexRetry() {
        if (root.indexRetries >= 3)
            return;
        root.indexRetries++;
        indexRetryTimer.restart();
    }

    function onHealth(raw) {
        var h = Model.parseHealth(root.truncateStdio(raw));
        if (!h.ok) {
            root.scheduleHealthRetry();
            return;
        }
        var versionChanged = root.health.version !== "" && root.health.version !== h.version;
        root.health = h;
        // Offer the change to the seen-version watcher; it decides on notify.
        root.maybeNotifyNewVersion(versionChanged);
    }

    function scheduleHealthRetry() {
        if (root.healthRetries >= 3)
            return;
        root.healthRetries++;
        healthRetryTimer.restart();
    }

    function onNews(raw) {
        var parsed = Model.parseRss(root.truncateStdio(raw));
        if (!parsed || parsed.length === 0) {
            root.scheduleNewsRetry();
            return;
        }
        root.news = parsed;
        newsCache.setText(JSON.stringify(parsed));
        root.maybeNotifyNewNews();
    }

    function onNewsCacheLoaded(raw) {
        if (root.news.length > 0)
            return;
        var parsed = Model.parseNewsCache(root.truncateStdio(raw));
        if (!parsed || parsed.length === 0)
            return;
        root.news = parsed;
    }

    function scheduleNewsRetry() {
        if (root.newsRetries >= 3)
            return;
        root.newsRetries++;
        newsRetryTimer.restart();
    }

    function maybeNotifyNewNews() {
        var newest = Model.newestGuid(root.news);
        if (newest === "")
            return;
        if (!root.newsSeenFileLoaded) {
            newsSeenFile.reload();
            return;
        }
        if (root.newsSeenGuid !== "" && root.newsSeenGuid !== newest) {
            if (root.setting("notifyOnNewNews", true) === true)
                sendNotification("New on Wardogs Zone", root.news[0].title);
        }
        if (root.newsSeenGuid !== newest) {
            root.newsSeenGuid = newest;
            newsSeenFile.setText(JSON.stringify({
                guid: newest
            }));
        }
    }

    function onNewsSeenLoaded(raw) {
        var g = "";
        try {
            var data = JSON.parse(String(raw || "{}"));
            g = data && data.guid ? String(data.guid) : "";
        } catch (e) {}
        root.newsSeenFileLoaded = true;
        root.newsSeenGuid = g;
        if (root.news.length > 0)
            root.maybeNotifyNewNews();
    }

    function truncateStdio(raw) {
        var s = String(raw || "");
        return s.length > root.maxStdioBytes ? s.substring(0, root.maxStdioBytes) : s;
    }

    function sendNotification(title, body) {
        Quickshell.execDetached([root.notifyBin, title, body]);
    }

    // Seen-version persistence via the local state file (FileView for reads, a
    // tiny python helper for writes). Notifies only when we already had a seen
    // version that differs from the newly reported one.
    function maybeNotifyNewVersion(versionChanged) {
        var current = root.health.version;
        if (current === "")
            return;
        if (!root.seenFileLoaded) {
            seenFile.reload();
            root.seenVersion = current;
        } else if (versionChanged && root.seenVersion !== "" && root.seenVersion !== current) {
            root.seenVersion = current;
            persistSeen(current);
            if (root.setting("notifyOnNewVersion", true) === true)
                sendNotification("Wardogs build " + current, "The WARDOGS game build changed; the wardogs.zone database may be updating.");
        } else if (root.seenVersion !== current) {
            root.seenVersion = current;
            persistSeen(current);
        }
    }

    function onSeenLoaded(raw) {
        var v = "";
        try {
            var data = JSON.parse(String(raw || "{}"));
            v = data && data.version ? String(data.version) : "";
        } catch (e) {}
        root.seenFileLoaded = true;
        root.seenVersion = v;
        if (root.health.version !== "" && v !== root.health.version)
            persistSeen(root.health.version);
    }

    function persistSeen(version) {
        persistProc.command = ["python3", pathFromUrl(Qt.resolvedUrl("scripts/persist.py")), "write-version", "--version", version];
        if (!persistProc.running)
            persistProc.running = true;
    }

    function pathFromUrl(url) {
        var value = String(url || "");
        if (value.indexOf("file://") === 0)
            return decodeURIComponent(value.substring(7));
        return value;
    }

    // --- browsing actions ------------------------------------------------------
    function openItem(url) {
        if (url)
            root.bar.run("xdg-open '" + String(url) + "'");
        toggleWindow();
    }

    // Opens the in-plugin loadout hub (list → build detail). The site itself
    // stays reachable through the site-link toolbar.
    function openHub() {
        hubMode = true;
        settingsMode = false;
        newsMode = false;
        compareMode = false;
        open();
        focusWinKeys();
        if (root.hubBuilds.length === 0 && !root.hubLoading && !root.hubListFailed)
            fetchHubList();
    }

    // The free-floating overlay window (left/middle click on the bar pill, or IPC).
    function toggleWindow() {
        root.toggle();
        if (root.opened) {
            root.settingsMode = false;
            root.newsMode = false;
        }
    }

    // --- item icons ------------------------------------------------------------
    // Local file url for an id, or "" while the icon is not cached yet. Reads
    // iconEpoch so callers' bindings re-run once downloads land, and appends it
    // as a query so Image reloads the file after an in-place whitespace/normalize
    // pass (same path, new cache key) instead of serving stale pixels.
    function iconFileUrl(id) {
        var epoch = root.iconEpoch;
        var name = Model.iconFileName(id);
        if (name === "" || epoch < 0 || !root.cachedIcons[name])
            return "";
        // The version key only moves on in-place rewrites (startup scan), NOT on
        // downloads — a per-download bump would change every tile's cache key and
        // reload the whole grid while the queue drains.
        return "file://" + root.iconDir + "/" + name + "?v=" + root.cacheEpoch;
    }

    function requestIcon(id) {
        var name = Model.iconFileName(id);
        if (name === "" || root.cachedIcons[name])
            return;
        if (root.failedIcons[id] || root.iconFetchingId === id)
            return;
        if (root.iconQueue.indexOf(id) !== -1)
            return;
        root.iconQueue = root.iconQueue.concat([id]);
        kickIconFetch();
    }

    function kickIconFetch() {
        if (root.iconFetchingId !== "" || root.iconQueue.length === 0)
            return;
        var id = root.iconQueue[0];
        root.iconQueue = root.iconQueue.slice(1);
        root.iconFetchingId = id;
        iconFetchProc.command = iconFetchCommand(id);
        iconFetchProc.running = true;
    }

    // Atomic download + normalize: curl -f writes no body on 404, the .part
    // rename keeps half-written files out of the cache, and magick pads every
    // icon onto a uniform 192x192 transparent square AND whitens the artwork so
    // tiles render at a consistent size regardless of the source dimensions
    // and re-tint cleanly to the theme foreground (alpha-mask + ColorOverlay).
    // 192 keeps 2x+ headroom over the ~70 device-pixel draw on a 1.25x screen
    // — a 96 cache forced a visible resample at draw time.
    // Exit 0 only when the file actually landed.
    function iconFetchCommand(id) {
        var dest = root.iconDir + "/" + Model.iconFileName(id);
        var url = Model.iconUrlFor(id);
        return ["sh", "-c", "mkdir -p \"${2%/*}\"; if curl -fsS --max-time 10 -o \"$2.part\" \"$1\"; then magick \"$2.part\" -trim +repage -alpha set -background none -gravity center -channel RGB -fill white -colorize 100% -resize '192x192>' -extent 192x192 \"$2\" && rm -f \"$2.part\" || { mv \"$2.part\" \"$2\"; }; else rm -f \"$2.part\"; exit 1; fi", "sh", url, dest];
    }

    // Queue icons for whatever the user is currently looking at. No-op while
    // the overlay is closed, so shell startup stays offline.
    function requestVisibleIcons() {
        if (!root.opened)
            return;
        for (var i = 0; i < root.filtered.length; i++)
            requestIcon(root.filtered[i].id);
    }

    function prefetchAllIcons() {
        for (var i = 0; i < root.items.length; i++)
            requestIcon(root.items[i].id);
    }

    // --- keyboard cursor --------------------------------------------------------
    property int navTotal: root.filtered.length

    onNavTotalChanged: {
        if (root.winCursor >= root.navTotal)
            root.winCursor = Math.max(0, root.navTotal - 1);
        ensureWinCursorVisible();
    }

    // Grid navigation: dx moves one column, dy moves one full row.
    function moveWinCursor(dx, dy) {
        root.keyboardMode = true;
        if (root.navTotal === 0)
            return;
        var next = clamp(root.winCursor + (dx || 0) + (dy || 0) * root.winGridColumns, 0, root.navTotal - 1);
        root.winCursor = next;
        ensureWinCursorVisible();
    }

    // Keep the keyboard-selected row on screen while arrowing through the list.
    function ensureWinCursorVisible() {
        var item = winRepeater.itemAt(root.winCursor);
        if (!item)
            return;
        var y = item.mapToItem(winScroller.contentItem, 0, 0).y;
        if (y < winScroller.contentY + Style.space(4))
            winScroller.contentY = Math.max(0, y - Style.space(36));
        else if (y + item.height > winScroller.contentY + winScroller.height - Style.space(4))
            winScroller.contentY = y + item.height - winScroller.height + Style.space(8);
    }

    function activateWinCursor() {
        var i = root.winCursor;
        if (i < 0 || i >= root.filtered.length)
            return;
        openItem(Model.itemUrl(root.filtered[i].id));
    }

    // --- settings ----------------------------------------------------------------
    function setting(name, fallback) {
        var value = settings ? settings[name] : undefined;
        return value === undefined || value === null ? fallback : value;
    }

    function clamp(v, lo, hi) {
        return Math.max(lo, Math.min(hi, v));
    }

    function cloneObject(value, fallback) {
        try {
            return JSON.parse(JSON.stringify(value));
        } catch (e) {
            return fallback;
        }
    }

    function normalizedSettings(source) {
        var next = cloneObject(source, {}) || {};
        var interval = Number(next.refreshIntervalSec === undefined || next.refreshIntervalSec === null ? 300 : next.refreshIntervalSec);
        next.refreshIntervalSec = Math.round(clamp(isFinite(interval) ? interval : 300, 60, 86400));
        next.alwaysShow = next.alwaysShow !== false;
        next.notifyOnNewVersion = next.notifyOnNewVersion !== false;
        next.notifyOnNewNews = next.notifyOnNewNews !== false;
        next.defaultKind = String(next.defaultKind || "weapon");
        next.filterText = String(next.filterText || "");
        return next;
    }

    function draftValue(name, fallback) {
        var value = draftSettings ? draftSettings[name] : undefined;
        return value === undefined || value === null ? fallback : value;
    }

    function setDraftValue(name, value) {
        var next = normalizedSettings(draftSettings);
        next[name] = value;
        draftSettings = next;
    }

    function openSettings() {
        draftSettings = normalizedSettings(settings);
        settingsStatusText = "";
        settingsMode = true;
        newsMode = false;
        compareMode = false;
        hubMode = false;
        open();
        focusWinKeys();
    }

    function showMain() {
        settingsMode = false;
        newsMode = false;
        compareMode = false;
        hubMode = false;
        hubBuildId = "";
        hubBuild = null;
        hubSlotCursor = 0;
        hubError = "";
        settingsStatusText = "";
        focusWinKeys();
    }

    function openNews() {
        newsMode = true;
        settingsMode = false;
        compareMode = false;
        hubMode = false;
        open();
        focusWinKeys();
    }

    // --- stat comparison ---------------------------------------------------
    // Marking: `c` toggles the item under the keyboard cursor as slot A, then
    // B; marking a third item replaces A. Re-mapping a slot drops its stale
    // detail state so the panel shows a clean "Loading stats…" on next open.
    function markCompare() {
        if (root.compareMode)
            return;
        var i = root.winCursor;
        if (i < 0 || i >= root.filtered.length)
            return;
        markCompareRow(root.filtered[i]);
    }

    // Generic toggle for any row shaped {id, name} — the browse grid and the
    // hub's slot rows both feed the same compare slots.
    function markCompareRow(row) {
        if (!row || String(row.id || "") === "")
            return;
        if (root.compareA && root.compareA.id === row.id) {
            root.compareA = null;
            root.compareDetailA = null;
            root.compareErrorA = false;
            root.compareLoadingA = false;
            return;
        }
        if (root.compareB && root.compareB.id === row.id) {
            root.compareB = null;
            root.compareDetailB = null;
            root.compareErrorB = false;
            root.compareLoadingB = false;
            return;
        }
        if (root.compareA === null) {
            root.compareA = row;
        } else if (root.compareB === null) {
            root.compareB = row;
        } else {
            root.compareA = row;
            root.compareDetailA = null;
            root.compareErrorA = false;
            root.compareLoadingA = false;
        }
    }

    // Opens the compare sheet even with an incomplete marking so the guide
    // (empty slot) teaches the flow instead of v doing nothing silently.
    function openCompare() {
        root.compareMode = true;
        root.settingsMode = false;
        root.newsMode = false;
        root.hubMode = false;
        requestCompareDetail("A", root.compareA);
        requestCompareDetail("B", root.compareB);
        focusWinKeys();
    }

    // Mirror the whole sheet: rows, details, and per-side load/error states.
    function swapCompare() {
        var ra = root.compareA;
        root.compareA = root.compareB;
        root.compareB = ra;
        var da = root.compareDetailA;
        root.compareDetailA = root.compareDetailB;
        root.compareDetailB = da;
        var la = root.compareLoadingA;
        root.compareLoadingA = root.compareLoadingB;
        root.compareLoadingB = la;
        var ea = root.compareErrorA;
        root.compareErrorA = root.compareErrorB;
        root.compareErrorB = ea;
    }

    // Detail resolution order per slot: in-memory session cache, then the
    // on-disk cache (details/{id}.json), then ONE live fetch of the site's
    // own compare page (/database/compare?items=a,b), which server-renders
    // the full stat blobs for both ids — every kind, vehicles included (the
    // per-item /database pages embed stats only for weapon-family items).
    // Disk reads run one at a time; whatever misses them queues for the
    // single pair fetch.
    function setCompareLoading(slot, loading) {
        if (slot === "A") {
            root.compareLoadingA = loading;
            root.compareErrorA = false;
        } else {
            root.compareLoadingB = loading;
            root.compareErrorB = false;
        }
    }

    function applyCompareDetail(slot, detail) {
        if (slot === "A") {
            root.compareDetailA = detail;
            root.compareLoadingA = false;
            root.compareErrorA = detail === null;
        } else {
            root.compareDetailB = detail;
            root.compareLoadingB = false;
            root.compareErrorB = detail === null;
        }
    }

    function requestCompareDetail(slot, row) {
        if (!row)
            return;
        var id = String(row.id || "");
        if (id === "") {
            applyCompareDetail(slot, null);
            return;
        }
        var hit = root.compareCache[id];
        if (hit !== undefined) {
            applyCompareDetail(slot, hit === false ? null : hit);
            return;
        }
        setCompareLoading(slot, true);
        root.compareFetchQueue = root.compareFetchQueue.concat([{
                    "slot": slot,
                    "id": id
                }]);
        kickCompareCacheRead();
    }

    function kickCompareCacheRead() {
        if (root.compareFetchSlot !== "" || root.compareFetchQueue.length === 0)
            return;
        var next = root.compareFetchQueue[0];
        root.compareFetchQueue = root.compareFetchQueue.slice(1);
        root.compareFetchSlot = next.slot;
        root.compareFetchId = next.id;
        detailCacheReadProc.command = ["sh", "-c", "cat \"$1\" 2>/dev/null || true", "sh", root.detailCachePath(next.id)];
        detailCacheReadProc.running = true;
    }

    // Commit a resolved detail for a slot. Data arriving for an id the user
    // has since un- or re-marked is cached but not applied.
    function finishCompareDetail(slot, id, detail) {
        var cache = cloneObject(root.compareCache, {});
        cache[id] = detail || false;
        root.compareCache = cache;
        var cur = slot === "A" ? root.compareA : root.compareB;
        if (cur && cur.id === id)
            applyCompareDetail(slot, detail);
    }

    // Advance the resolution pipeline after a disk read completes: next cache
    // read first, and once none are pending, the batched pair fetch.
    function advanceCompareFetch() {
        root.compareFetchSlot = "";
        root.compareFetchId = "";
        if (root.compareFetchQueue.length > 0) {
            kickCompareCacheRead();
            return;
        }
        kickCompareNet();
    }

    function kickCompareNet() {
        if (root.compareNetQueue.length === 0 || detailFetchProc.running)
            return;
        var ids = root.compareNetQueue.map(function (e) {
            return e.id;
        });
        // sh -c arg order: $0=sh $1=url $2=cache dir (mkdir first — the
        // FileView write below needs the directory to exist).
        detailFetchProc.command = ["sh", "-c", "mkdir -p \"$2\"; curl -fsS --max-time 8 \"$1\"", "sh", Model.compareUrl(ids), root.detailCacheDir];
        detailFetchProc.running = true;
    }

    // Disk-cache read: empty output (missing file) or a JSON body whose id
    // doesn't match the pending read counts as a miss and queues for the
    // pair fetch.
    function onCompareCacheRaw(raw) {
        var slot = root.compareFetchSlot;
        var id = root.compareFetchId;
        if (slot === "" || id === "")
            return;
        var detail = null;
        try {
            var parsed = JSON.parse(String(raw || ""));
            if (parsed && parsed.id === id)
                detail = parsed;
        } catch (e) {
            detail = null;
        }
        if (detail) {
            finishCompareDetail(slot, id, detail);
        } else {
            root.compareNetQueue = root.compareNetQueue.concat([{
                        "slot": slot,
                        "id": id
                    }]);
        }
        advanceCompareFetch();
    }

    function onCompareDetailHtml(raw) {
        var pending = root.compareNetQueue;
        root.compareNetQueue = [];
        var capped = String(raw || "");
        if (capped.length > root.maxDetailBytes)
            capped = capped.substring(0, root.maxDetailBytes);
        for (var i = 0; i < pending.length; i++) {
            var detail = Details.parseDetails(capped, pending[i].id);
            if (detail) {
                detailCacheView.path = root.detailCachePath(pending[i].id);
                detailCacheView.setText(JSON.stringify(detail));
            }
            finishCompareDetail(pending[i].slot, pending[i].id, detail);
        }
    }

    // --- loadout hub ----------------------------------------------------------
    // Resolution order per view: memory (hubBuilds / hubDetailCache), then
    // the disk cache (hub/list.json, hub/{id}.json), then the live page.
    // Live failures keep the last-good data and set an error line.
    function hubCachePath(name) {
        return root.hubDir + "/" + name + ".json";
    }

    function fetchHubList() {
        root.hubLoading = true;
        root.hubListFailed = false;
        root.hubError = "";
        root.hubReadTarget = "list";
        hubCacheReadProc.command = ["sh", "-c", "cat \"$1\" 2>/dev/null || true", "sh", root.hubCachePath("list")];
        hubCacheReadProc.running = true;
    }

    function openHubBuild(id) {
        if (id === "")
            return;
        root.hubBuildId = id;
        root.hubSlotCursor = 0;
        root.hubError = "";
        var hit = root.hubDetailCache[id];
        if (hit) {
            root.hubBuild = hit;
            requestHubSlotIcons(hit);
            return;
        }
        root.hubBuild = null;
        root.hubReadTarget = id;
        hubCacheReadProc.command = ["sh", "-c", "cat \"$1\" 2>/dev/null || true", "sh", root.hubCachePath(id)];
        hubCacheReadProc.running = true;
    }

    function applyHubBuild(id, build) {
        var cache = cloneObject(root.hubDetailCache, {});
        cache[id] = build;
        root.hubDetailCache = cache;
        if (root.hubBuildId === id) {
            root.hubBuild = build;
            requestHubSlotIcons(build);
        }
    }

    function requestHubSlotIcons(build) {
        if (!build)
            return;
        var seen = {};
        build.slots.forEach(function (s) {
            if (s.itemId !== "" && !seen[s.itemId]) {
                seen[s.itemId] = true;
                requestIcon(s.itemId);
            }
        });
    }

    function closeHubBuild() {
        root.hubBuildId = "";
        root.hubBuild = null;
        root.hubSlotCursor = 0;
        root.hubError = "";
    }

    function hubRows() {
        // Flat slot count for the detail cursor.
        return root.hubBuild ? root.hubBuild.slots.length : 0;
    }

    // The hub panel filters/sorts its list internally (search + hot/top +
    // role chips); the cursor indexes into THAT list, so activation reads
    // hubPanel.filteredBuilds rather than the raw hubBuilds.
    function hubMove(d) {
        if (root.hubBuildId === "") {
            var n = hubPanel.filteredBuilds.length;
            if (n === 0)
                return;
            root.hubCursor = clamp(root.hubCursor + d, 0, n - 1);
        } else {
            root.hubSlotCursor = clamp(root.hubSlotCursor + d, 0, Math.max(0, hubRows() - 1));
        }
    }

    function hubActivate() {
        if (root.hubBuildId === "") {
            var list = hubPanel.filteredBuilds;
            if (root.hubCursor < list.length)
                openHubBuild(list[root.hubCursor].id);
        } else if (root.hubSlotCursor < hubRows()) {
            openItem(Model.itemUrl(root.hubBuild.slots[root.hubSlotCursor].itemId));
        }
    }

    function markHubSlot() {
        if (root.hubBuildId === "" || root.hubSlotCursor >= hubRows())
            return;
        var slot = root.hubBuild.slots[root.hubSlotCursor];
        markCompareRow({
            "id": slot.itemId,
            "name": slot.name
        });
    }

    function onHubCacheRaw(raw) {
        var target = root.hubReadTarget;
        if (target === "")
            return;
        var parsed = null;
        try {
            var j = JSON.parse(String(raw || ""));
            if (j && (Array.isArray(j) ? j.length > 0 : j.title))
                parsed = j;
        } catch (e) {
            parsed = null;
        }
        if (target === "list") {
            root.hubLoading = false;
            if (parsed) {
                root.hubBuilds = parsed;
                root.hubReadTarget = "";
                root.hubBuilds.forEach(function (b) {
                    requestIcon(b.iconId);
                });
                return;
            }
            // disk miss → live fetch; hubReadTarget stays set so the
            // response is routed back to the right handler
            fetchHubListNetwork();
        } else {
            if (parsed) {
                root.hubReadTarget = "";
                applyHubBuild(target, parsed);
                return;
            }
            fetchHubBuildNetwork(target);
        }
    }

    function hubFetch(url) {
        // sh -c arg order: $0=sh $1=url $2=cache dir (mkdir first — the
        // FileView cache write below needs the directory to exist).
        hubFetchProc.command = ["sh", "-c", "mkdir -p \"$2\"; curl -fsS --max-time 8 \"$1\"", "sh", url, root.hubDir];
        hubFetchProc.running = true;
    }

    function fetchHubListNetwork() {
        hubFetch("https://wardogs.zone/loadouts/hub");
    }

    function fetchHubBuildNetwork(id) {
        hubFetch("https://wardogs.zone/loadouts/hub/" + id);
    }

    function onHubListHtml(raw) {
        root.hubReadTarget = "";
        root.hubLoading = false;
        var capped = String(raw || "");
        if (capped.length > root.maxDetailBytes)
            capped = capped.substring(0, root.maxDetailBytes);
        var builds = Hub.parseHubList(capped);
        if (builds.length > 0) {
            root.hubBuilds = builds;
            hubCacheView.path = root.hubCachePath("list");
            hubCacheView.setText(JSON.stringify(builds));
            builds.forEach(function (b) {
                requestIcon(b.iconId);
            });
        } else {
            root.hubListFailed = true;
            root.hubError = builds.length === 0 && root.hubBuilds.length === 0 ? "Offline — can't reach the loadout hub." : "";
        }
    }

    function onHubBuildHtml(raw) {
        var id = root.hubReadTarget;
        root.hubReadTarget = "";
        if (id === "" || id === "list")
            return;
        var capped = String(raw || "");
        if (capped.length > root.maxDetailBytes)
            capped = capped.substring(0, root.maxDetailBytes);
        var build = Hub.parseHubBuild(capped);
        if (build && build.title !== "") {
            build.id = id;
            hubCacheView.path = root.hubCachePath(id);
            hubCacheView.setText(JSON.stringify(build));
            applyHubBuild(id, build);
            root.hubError = "";
        } else {
            root.hubError = "Could not load this build — open it on the site instead.";
        }
    }

    // --- stats prefetch -----------------------------------------------------
    // Queue every item whose detail is not already resolved in memory; the
    // compare page is fetched two ids at a time (the shape proven to render
    // both stat blobs) and each parse lands in the shared details disk cache.
    function prefetchAllStats() {
        var missing = [];
        for (var i = 0; i < root.items.length; i++) {
            var id = String(root.items[i].id || "");
            if (id === "" || root.compareCache[id] !== undefined)
                continue;
            missing.push(id);
        }
        root.statsQueue = missing;
        kickStatsPrefetch();
    }

    function kickStatsPrefetch() {
        if (root.statsPrefetchBusy || root.statsQueue.length === 0)
            return;
        root.statsBatch = root.statsQueue.slice(0, 2);
        root.statsQueue = root.statsQueue.slice(2);
        root.statsPrefetchBusy = true;
        // sh -c arg order: $0=sh $1=url $2=cache dir.
        statsPrefetchProc.command = ["sh", "-c", "mkdir -p \"$2\"; curl -fsS --max-time 8 \"$1\"", "sh", Model.compareUrl(root.statsBatch), root.detailCacheDir];
        statsPrefetchProc.running = true;
    }

    function onStatsPrefetchHtml(raw) {
        var capped = String(raw || "");
        if (capped.length > root.maxDetailBytes)
            capped = capped.substring(0, root.maxDetailBytes);
        var cache = cloneObject(root.compareCache, {});
        for (var i = 0; i < root.statsBatch.length; i++) {
            var id = root.statsBatch[i];
            var detail = Details.parseDetails(capped, id);
            if (detail) {
                detailCacheView.path = root.detailCachePath(id);
                detailCacheView.setText(JSON.stringify(detail));
            }
            cache[id] = detail || false;
            root.statsPrefetched = root.statsPrefetched + 1;
        }
        root.compareCache = cache;
        root.statsBatch = [];
        root.statsPrefetchBusy = false;
        kickStatsPrefetch();
    }

    // The overlay window maps asynchronously, so a single callLater focus can
    // fire before the layer-shell window exists and silently no-op. Retry for
    // a bounded time until the key catcher actually holds active focus.
    function focusWinKeys() {
        focusRetryTimer.attempts = 0;
        focusRetryTimer.restart();
    }

    Timer {
        id: focusRetryTimer
        interval: 40
        repeat: true
        property int attempts: 0
        onTriggered: {
            if (!winKeys || winKeys.activeFocus || attempts > 25) {
                stop();
                return;
            }
            attempts++;
            winKeys.forceActiveFocus();
        }
    }

    readonly property var settingsItems: [alwaysShowToggle, notifyToggle, notifyNewsToggle, filterField, refreshField]

    function currentSettingsIndex() {
        var win = winKeys ? winKeys.Window.window : null;
        if (!win || !win.activeFocusItem)
            return -1;
        var it = win.activeFocusItem;
        while (it) {
            var idx = settingsItems.indexOf(it);
            if (idx !== -1)
                return idx;
            it = it.parent;
        }
        return -1;
    }

    // Focused settings control, or the first one when nothing is focused yet —
    // Enter always has something sensible to activate.
    function currentSettingsItem() {
        var idx = currentSettingsIndex();
        if (idx === -1)
            idx = 0;
        return settingsItems[idx] || null;
    }

    function moveSettingsFocus(delta) {
        var cur = currentSettingsIndex();
        var next = ((cur < 0 ? (delta > 0 ? -1 : 0) : cur) + delta + settingsItems.length) % settingsItems.length;
        if (settingsItems[next])
            settingsItems[next].forceActiveFocus();
    }

    function saveSettings() {
        var next = normalizedSettings(draftSettings);
        draftSettings = next;
        root.settings = next;
        // Keep the host bar widget in sync immediately (clock/F1 pattern) — it
        // re-injects its settings on bar changes, and a stale snapshot there
        // would clobber the just-saved values until the next shell restart.
        if (root.hostWidget && "settings" in root.hostWidget)
            root.hostWidget.settings = next;
        var persisted = false;
        if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function") {
            bar.shell.updateEntryInline(root.moduleName, next);
            persisted = true;
        }
        // Apply immediately — the saved default is what the user expects to see.
        root.activeKind = next.defaultKind || "weapon";
        root.searchText = String(next.filterText || "");
        settingsStatusText = persisted ? "Saved" : "Could not save";
    }

    // --- bar trigger ------------------------------------------------------------
    // Settings arrive after construction (bar injects them) and change on
    // save; re-apply the persisted defaults both times.
    onSettingsChanged: {
        root.activeKind = root.setting("defaultKind", "weapon") || "weapon";
        root.searchText = String(root.setting("filterText", "") || "");
    }

    onOpenedChanged: {
        if (!opened)
            return;
        refresh();
        requestVisibleIcons();
        // Keyboard nav owns focus on open; "/" or a click moves it to search.
        focusWinKeys();
    }
    onActiveKindChanged: {
        root.winCursor = 0;
        requestVisibleIcons();
    }
    onSearchTextChanged: {
        root.winCursor = 0;
        requestVisibleIcons();
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
        onTriggered: if (!indexProc.running)
            indexProc.running = true
    }

    Timer {
        id: healthRetryTimer
        interval: 2500
        onTriggered: if (!healthProc.running)
            healthProc.running = true
    }

    Timer {
        id: newsRetryTimer
        interval: 2500
        onTriggered: if (!newsProc.running)
            newsProc.running = true
    }

    // Ticks the release countdown in the bar label.
    Timer {
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.nowMs = Date.now()
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

    // Per-item compare detail cache. WRITES go through the FileView (setText
    // is atomic; path is assigned by kickCompareFetch for the pending id).
    // READS go through detailCacheReadProc below: a FileView reload() on a
    // dynamically assigned path fires neither loaded() nor loadFailed() for
    // a missing file, which stalls the whole fetch chain — cat is immune.
    FileView {
        id: detailCacheView
        watchChanges: false
        atomicWrites: true
        printErrors: false
    }

    // Disk-cache read for the pending compare fetch: prints the cached JSON
    // or nothing when the file is missing/failed; onCompareCacheRaw treats
    // empty output as a miss.
    Process {
        id: detailCacheReadProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.onCompareCacheRaw(text)
        }
    }

    // One-shot detail page downloader for the compare view (sequential, like
    // the icon fetcher: command is set per fetch by fetchCompareDetailNetwork).
    Process {
        id: detailFetchProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.onCompareDetailHtml(text)
        }
        stderr: StdioCollector {}
    }

    // Background stats prefetcher (settings): independent of detailFetchProc
    // so an open compare sheet never contends with the bulk run.
    Process {
        id: statsPrefetchProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.onStatsPrefetchHtml(text)
        }
        stderr: StdioCollector {}
    }

    // Hub: disk-cache read (cat) + live page fetch; the in-flight target
    // ("list" or a build id) routes each response to its parser.
    Process {
        id: hubCacheReadProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.onHubCacheRaw(text)
        }
    }

    Process {
        id: hubFetchProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                if (root.hubReadTarget === "list")
                    root.onHubListHtml(text);
                else
                    root.onHubBuildHtml(text);
            }
        }
        stderr: StdioCollector {}
    }

    FileView {
        id: hubCacheView
        watchChanges: false
        atomicWrites: true
        printErrors: false
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
        command: ["sh", "-c", "mkdir -p \"$1\"; mogrify -trim +repage -alpha set -background none -gravity center -channel RGB -fill white -colorize 100% -resize '192x192>' -extent 192x192 \"$1\"/*.png 2>/dev/null || true; ls -1 \"$1\" || true", "sh", root.iconDir]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var names = {};
                var lines = String(text || "").split("\n");
                for (var i = 0; i < lines.length; i++) {
                    var n = lines[i].replace(/^\s+|\s+$/g, "");
                    if (n !== "")
                        names[n] = true;
                }
                root.cachedIcons = names;
                root.iconEpoch = root.iconEpoch + 1;
                root.cacheEpoch = root.cacheEpoch + 1;
            }
        }
    }

    // Sequential icon downloader; one id at a time keeps the site happy and
    // the queue state trivial to reason about.
    Process {
        id: iconFetchProc
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: function (exitCode) {
            if (root.iconFetchingId === "")
                return;
            if (exitCode === 0) {
                var name = Model.iconFileName(root.iconFetchingId);
                if (name !== "") {
                    var known = cloneObject(root.cachedIcons, {});
                    known[name] = true;
                    root.cachedIcons = known;
                    root.iconEpoch = root.iconEpoch + 1;
                }
            } else {
                var failed = cloneObject(root.failedIcons, {});
                failed[root.iconFetchingId] = true;
                root.failedIcons = failed;
            }
            root.iconFetchingId = "";
            kickIconFetch();
        }
    }

    Component.onCompleted: {
        root.activeKind = root.setting("defaultKind", "weapon");
        root.searchText = root.setting("filterText", "");
        seenFile.reload();
        indexCache.reload();
        newsCache.reload();
        newsSeenFile.reload();
        iconScanProc.running = true;
        root.refresh();
    }

    // Small bordered A/B slot tag used by the marked-items strip; `dimmed`
    // renders an unassigned slot so the strip reads "A set / B empty" at a
    // glance.
    component CompareSlotTag: Rectangle {
        property string letter: ""
        property bool dimmed: false

        implicitWidth: Style.space(18)
        implicitHeight: Style.space(18)
        radius: Style.space(3)
        color: "transparent"
        border.width: 1
        border.color: dimmed ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.3) : root.fg

        Text {
            anchors.centerIn: parent
            text: parent.letter
            color: parent.dimmed ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.4) : root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
        }
    }

    // Settings-only section wrapper.
    component SectionCard: BorderSurface {
        id: section
        property string title: ""
        default property alias content: body.data

        Layout.fillWidth: true
        color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.055)
        borderSpec: Border.controlSpec("normal", root.fg, Color.accent)
        radius: Style.cornerRadius
        padding: Style.space(5)
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
                anchors.verticalCenter: parent.verticalCenter
                source: Qt.resolvedUrl("assets/wardogs-icon.webp")
                visible: status === Image.Ready
                fillMode: Image.PreserveAspectFit
                height: Style.space(28)
                width: height
                mipmap: true
            }
            // Image {
            //   id: heroImg
            //   anchors.fill: parent
            //   anchors.margins: Style.space(1)
            //   source: Qt.resolvedUrl("assets/icon.png")
            //   asynchronous: true
            //   fillMode: Image.PreserveAspectFit
            //   mipmap: true
            //   smooth: true
            // }
            //
            ColorOverlay {
                anchors.fill: heroImg
                visible: heroImg.status === Image.Ready
                source: heroImg
                color: root.fg
            }
        }
    }

    IpcHandler {
        target: "niziul.wardogs.settings"
        function save() {
            root.openSettings();
            root.saveSettings();
        }
        function setRefreshInterval(sec: int) {
            root.openSettings();
            root.setDraftValue("refreshIntervalSec", sec);
            root.saveSettings();
        }
    }

    IpcHandler {
        target: "niziul.wardogs.window"
        function toggle() {
            root.toggleWindow();
        }
        function open() {
            if (!root.opened)
                root.toggleWindow();
        }
        function close() {
            root.close();
        }
    }

    // The free-floating overlay window (left/middle click on the bar widget).
    PanelWindow {
        id: taskWindow
        visible: root.opened
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "niziul-wardogs-window"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        onVisibleChanged: {
            if (visible)
                Qt.callLater(function () {
                    if (root.opened)
                        winKeys.forceActiveFocus();
                });
        }

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.45)

            MouseArea {
                anchors.fill: parent
                onClicked: root.close()
            }
        }

        Item {
            id: winKeys
            anchors.fill: parent
            focus: true

            Keys.onEscapePressed: {
                if (root.hubMode && root.hubBuildId !== "") {
                    closeHubBuild();
                } else if (root.settingsMode || root.newsMode || root.compareMode || root.hubMode)
                    root.showMain();
                else
                    root.close();
            }
            Keys.onLeftPressed: if (!root.settingsMode && !root.newsMode && !root.compareMode && !root.hubMode)
                root.moveWinCursor(-1, 0)
            Keys.onRightPressed: if (!root.settingsMode && !root.newsMode && !root.compareMode && !root.hubMode)
                root.moveWinCursor(1, 0)
            Keys.onUpPressed: if (!root.settingsMode && !root.newsMode && !root.compareMode)
                root.hubMode ? root.hubMove(-1) : root.moveWinCursor(0, -1)
            Keys.onDownPressed: if (!root.settingsMode && !root.newsMode && !root.compareMode)
                root.hubMode ? root.hubMove(1) : root.moveWinCursor(0, 1)
            Keys.onReturnPressed: {
                if (root.settingsMode) {
                    var cur = root.currentSettingsItem();
                    if (cur && typeof cur.clicked === "function")
                        cur.clicked();
                } else if (root.hubMode)
                    root.hubActivate();
                else if (!root.newsMode && !root.compareMode)
                    root.activateWinCursor();
            }
            Keys.onEnterPressed: {
                if (root.settingsMode) {
                    var cur = root.currentSettingsItem();
                    if (cur && typeof cur.clicked === "function")
                        cur.clicked();
                } else if (root.hubMode)
                    root.hubActivate();
                else if (!root.newsMode && !root.compareMode)
                    root.activateWinCursor();
            }
            Keys.onSpacePressed: if (!root.settingsMode && !root.newsMode && !root.compareMode && !root.hubMode)
                root.activateWinCursor()
            Keys.onPressed: function (event) {
                if (event.modifiers & Qt.ControlModifier || event.modifiers & Qt.AltModifier)
                    return;
                if (event.key === Qt.Key_R)
                    root.refresh();
                else if (root.settingsMode) {
                    if (event.text === "s" || event.text === "S")
                        root.saveSettings();
                    else if (event.key === Qt.Key_J || event.text === "j")
                        root.moveSettingsFocus(1);
                    else if (event.key === Qt.Key_K || event.text === "k")
                        root.moveSettingsFocus(-1);
                    else if (event.text === "/" || event.key === Qt.Key_Escape) {}
                    return;
                } else if (root.newsMode)
                    return;
                else if (root.hubMode) {
                    // Hub: j/k move the cursor, c marks the slot's item into
                    // the compare sheet, v opens the compare, esc already
                    // handled above (detail → list → armory).
                    if (event.key === Qt.Key_J || event.text === "j")
                        root.hubMove(1);
                    else if (event.key === Qt.Key_K || event.text === "k")
                        root.hubMove(-1);
                    else if (event.text === "c" || event.text === "C")
                        root.markHubSlot();
                    else if (event.text === "v" || event.text === "V")
                        root.openCompare();
                    else if (event.text === "/" && root.hubBuildId === "") {
                        hubPanel.searchField.forceActiveFocus();
                        hubPanel.searchField.cursorPosition = hubPanel.searchField.text.length;
                    }
                    return;
                } else if (root.compareMode) {
                    // Compare view: x swaps sides, v (or esc) goes back.
                    if (event.text === "x" || event.text === "X")
                        root.swapCompare();
                    else if (event.text === "v" || event.text === "V")
                        root.showMain();
                    return;
                } else if (event.key === Qt.Key_J || event.text === "j")
                    root.moveWinCursor(0, 1);
                else if (event.key === Qt.Key_K || event.text === "k")
                    root.moveWinCursor(0, -1);
                else
                // else if (event.text === "h" || event.text === "H") root.openHub()
                if (event.text === "h" || event.text === "H")
                    root.moveWinCursor(-1, 0);
                else if (event.text === "l" || event.text === "L")
                    root.moveWinCursor(1, 0);
                else if (event.text === "c" || event.text === "C")
                    root.markCompare();
                else if (event.text === "v" || event.text === "V")
                    root.openCompare();
                else if (event.text === "s" || event.text === "S")
                    root.openSettings();
                else if (event.text === "n" || event.text === "N")
                    root.openNews();
                else if (event.text === "/") {
                    winSearchInput.forceActiveFocus();
                    winSearchInput.cursorPosition = winSearchInput.text.length;
                }
            }

            BorderSurface {
                id: winCard
                readonly property real sw: taskWindow.screen ? taskWindow.screen.width : Screen.width
                readonly property real sh: taskWindow.screen ? taskWindow.screen.height : Screen.height
                // Fractional card geometry puts every child border on half pixels,
                // where a 1px line anti-aliases across two device rows. Round both
                // the size and the centered position to keep borders crisp.
                anchors.centerIn: parent
                width: Math.round(Math.max(Style.space(500), sw - Style.space(80)))
                height: Math.round(Math.max(Style.space(420), Math.min(sh * 0.7, sh - Style.space(80))))
                x: Math.round((parent.width - width) / 2)
                y: Math.round((parent.height - height) / 2)
                color: Color.popups.background
                radius: Style.cornerRadius
                padding: Style.space(14)

                // Consume clicks on empty card areas (padding, text, background).
                // Without this they fall through the card to the scrim's
                // close-on-click MouseArea and the window closes unexpectedly.
                MouseArea {
                    anchors.fill: parent
                }

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

                    Item {
                        id: winHeaderRow
                        Layout.fillWidth: true
                        // Anchored thirds instead of a RowLayout so the site-link
                        // toolbar can sit on the true horizontal center of the
                        // header regardless of how wide the hero or buttons are.
                        implicitHeight: Math.max(winHero.implicitHeight, winToolsScope.implicitHeight, headerButtons.implicitHeight)
                        // Hovering anywhere on the window header reveals the site-link
                        // toolbar; keyboard focus on one of its buttons keeps it visible.

                        PanelHero {
                            id: winHero
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                                title: root.settingsMode ? "Wardogs Settings" : root.newsMode ? "Wardogs News" : root.compareMode ? "Compare Items" : root.hubMode ? "Loadout Hub" : "Wardogs Zone"
                                meta: (root.settingsMode || root.newsMode) ? "" : root.compareMode ? (root.compareA && root.compareB ? String(root.compareA.name) + "  vs  " + String(root.compareB.name) : "") : root.hubMode ? (root.hubBuildId !== "" && root.hubBuild ? String(root.hubBuild.title) : root.hubBuilds.length + " builds published") : (root.health.version ? "Build " + root.health.version + " · " + root.onlineText : "loading…")
                            foreground: root.fg
                            fontFamily: root.fontFamily
                            iconComponent: heroIconComponent
                        }

                        FocusScope {
                            id: winToolsScope
                            visible: !root.settingsMode && !root.newsMode && !root.compareMode
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.verticalCenter: parent.verticalCenter
                            implicitWidth: winSiteLinks.implicitWidth
                            implicitHeight: winSiteLinks.implicitHeight

                            SiteLinks {
                                id: winSiteLinks
                                anchors.centerIn: parent
                                fg: root.fg
                                fontFamily: root.fontFamily
                                cornerRadius: root.cornerRadius
                                onOpenRequested: function (url) {
                                    root.openItem(url);
                                    winKeys.forceActiveFocus();
                                }
                            }
                        }

                        Row {
                            id: headerButtons
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8

                            // The toolbar expands to the right of the hero badge on hover/focus.
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
                            id: hubButton
                            visible: !root.settingsMode && !root.newsMode && !root.compareMode
                            radius: root.cornerRadius
                            tooltipText: "Open loadout hub"
                            foreground: root.fg
                            fontFamily: root.fontFamily
                            fontSize: Style.font.caption
                            implicitWidth: Style.font.icon + horizontalPadding * 2 + _reservedBorderLeft + _reservedBorderRight
                            implicitHeight: Style.font.icon + verticalPadding * 2 + _reservedBorderTop + _reservedBorderBottom
                            horizontalPadding: Style.spacing.controlPaddingX
                            verticalPadding: Style.spacing.controlPaddingY
                            onClicked: root.openHub()

                            SvgIcon {
                                anchors.centerIn: parent
                                source: "wardogs-grid.svg"
                                color: root.fg
                                size: Style.font.icon
                            }
                        }

                        Button {
                            id: newsButton
                            visible: !root.settingsMode && !root.newsMode && !root.compareMode
                            radius: root.cornerRadius
                            tooltipText: "News feed"
                            foreground: root.fg
                            fontFamily: root.fontFamily
                            fontSize: Style.font.caption
                            implicitWidth: Style.font.icon + horizontalPadding * 2 + _reservedBorderLeft + _reservedBorderRight
                            implicitHeight: Style.font.icon + verticalPadding * 2 + _reservedBorderTop + _reservedBorderBottom
                            horizontalPadding: Style.spacing.controlPaddingX
                            verticalPadding: Style.spacing.controlPaddingY
                            onClicked: root.openNews()

                            SvgIcon {
                                anchors.centerIn: parent
                                source: "wardogs-news.svg"
                                color: root.fg
                                size: Style.font.icon
                            }
                        }

                            Button {
                                visible: !root.settingsMode && !root.newsMode && !root.compareMode
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
                                visible: !root.compareMode && !root.settingsMode && !root.newsMode && root.compareA !== null && root.compareB !== null
                                radius: root.cornerRadius
                                text: "Compare"
                                tooltipText: "Compare marked items (v)"
                                foreground: root.fg
                                fontFamily: root.fontFamily
                                fontSize: Style.font.caption
                                horizontalPadding: Style.spacing.controlPaddingX
                                verticalPadding: Style.spacing.controlPaddingY
                                active: true
                                onClicked: root.openCompare()
                            }

                            Button {
                                visible: root.settingsMode || root.newsMode || root.compareMode
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

                            Button {
                                radius: root.cornerRadius
                                text: "\u2715"
                                tooltipText: "Close"
                                foreground: root.fg
                                fontFamily: root.fontFamily
                                fontSize: Style.font.caption
                                horizontalPadding: Style.spacing.controlPaddingX
                                verticalPadding: Style.spacing.controlPaddingY
                                onClicked: root.close()
                            }
                        }
                    }

                    PanelSeparator {
                        Layout.fillWidth: true
                        foreground: root.fg
                    }

                    RowLayout {
                        visible: !root.settingsMode && !root.newsMode && !root.compareMode && !root.hubMode
                        Layout.fillWidth: true
                        spacing: Style.space(6)

                        TextField {
                            id: winSearchInput
                            Layout.fillWidth: true
                            placeholderText: root.searchPlaceholder
                            foreground: root.fg
                            accent: Color.accent
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.bodySmall
                            text: root.searchText
                            onTextEdited: root.searchText = winSearchInput.text
                            Keys.onEscapePressed: winKeys.forceActiveFocus()
                            Keys.onUpPressed: {
                                winSearchInput.focus = false;
                                root.moveWinCursor(0, -1);
                            }
                            Keys.onDownPressed: {
                                winSearchInput.focus = false;
                                root.moveWinCursor(0, 1);
                            }
                            Keys.onReturnPressed: root.activateWinCursor()
                            Keys.onEnterPressed: root.activateWinCursor()
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
                                root.searchText = "";
                                winSearchInput.forceActiveFocus();
                            }
                        }

                        CategorySelect {
                            Layout.alignment: Qt.AlignVCenter
                            rowHeight: Math.round(winSearchInput.implicitHeight)
                            focusTarget: winKeys
                            items: root.items
                            kinds: root.kinds
                            activeKind: root.activeKind
                            fg: root.fg
                            fontFamily: root.fontFamily
                            onSetKind: function (k) {
                                root.activeKind = k;
                                root.activeSub = "";
                            }
                        }

                        SubcategorySelect {
                            Layout.alignment: Qt.AlignVCenter
                            rowHeight: Math.round(winSearchInput.implicitHeight)
                            focusTarget: winKeys
                            items: root.items
                            activeKind: root.activeKind
                            activeSub: root.activeSub
                            fg: root.fg
                            fontFamily: root.fontFamily
                            onSetSub: function (s) {
                                root.activeSub = s;
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
                                visible: !root.settingsMode && !root.newsMode && !root.compareMode && !root.hubMode
                                Layout.fillWidth: true
                                text: root.items.length === 0 ? (root.indexLoading ? "Loading armory…" : "Offline — can't reach wardogs.zone") : (root.filtered.length === 0 ? "No items match." : (root.searchText !== "" ? "Search · " + root.filtered.length + " item(s) across categories" : (Model.kindLabel(root.activeKind) + " · " + root.filtered.length + " item(s)")))
                                color: root.dim
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                horizontalAlignment: Text.AlignHCenter
                            }

                            // Marked-items strip: keeps the compare slots visible
                            // while browsing so "c" never feels like a no-op.
                            RowLayout {
                                visible: !root.settingsMode && !root.newsMode && !root.compareMode && (root.compareA !== null || root.compareB !== null)
                                Layout.fillWidth: true
                                spacing: Style.space(8)

                                CompareSlotTag {
                                    letter: "A"
                                    dimmed: root.compareA === null
                                }

                                Text {
                                    Layout.maximumWidth: winScroller.width * 0.3
                                    text: root.compareA ? String(root.compareA.name) : "empty — mark with c"
                                    color: root.compareA ? root.fg : root.dim
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.caption
                                    font.italic: root.compareA === null
                                    elide: Text.ElideRight
                                }

                                CompareSlotTag {
                                    letter: "B"
                                    dimmed: root.compareB === null
                                }

                                Text {
                                    Layout.maximumWidth: winScroller.width * 0.3
                                    text: root.compareB ? String(root.compareB.name) : "empty — mark with c"
                                    color: root.compareB ? root.fg : root.dim
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.caption
                                    font.italic: root.compareB === null
                                    elide: Text.ElideRight
                                }

                                Item {
                                    Layout.fillWidth: true
                                }

                                Text {
                                    visible: root.compareA !== null && root.compareB !== null
                                    text: "v compare"
                                    color: Color.accent
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.caption
                                    horizontalAlignment: Text.AlignRight
                                }
                            }

                            GridLayout {
                                visible: !root.settingsMode && !root.newsMode && !root.compareMode && !root.hubMode
                                Layout.fillWidth: true
                                Layout.bottomMargin: Style.space(2)
                                columns: root.winGridColumns
                                columnSpacing: Style.space(6)
                                rowSpacing: Style.space(6)

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
                                        badge: root.compareA && root.compareA.id === modelData.id ? "A" : root.compareB && root.compareB.id === modelData.id ? "B" : ""
                                        // Clicking a tile moves the keyboard cursor with the mouse.
                                        onOpenRequested: {
                                            root.winCursor = index;
                                            root.openItem(url);
                                        }
                                        Layout.fillWidth: true
                                    }
                                }
                            }

                            // ---------- compare ----------
                            ColumnLayout {
                                visible: root.compareMode && (root.compareA === null || root.compareB === null)
                                Layout.fillWidth: true
                                spacing: Style.space(4)

                                Text {
                                    Layout.fillWidth: true
                                    text: "Compare needs two items"
                                    color: root.fg
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.body
                                    font.bold: true
                                    horizontalAlignment: Text.AlignHCenter
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: root.compareA === null && root.compareB === null ? "Mark any two items in the armory with c, then press v again." : "Slot " + (root.compareA === null ? "A" : "B") + " is still empty — mark one more item with c, or press v/esc to go back."
                                    color: root.dim
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.caption
                                    wrapMode: Text.WordWrap
                                    horizontalAlignment: Text.AlignHCenter
                                }
                            }

                            ComparePanel {
                                visible: root.compareMode && root.compareA !== null && root.compareB !== null
                                Layout.fillWidth: true
                                Layout.preferredHeight: Math.max(Style.space(300), winScroller.height - Style.space(50))
                                leftItem: root.compareA
                                rightItem: root.compareB
                                leftDetail: root.compareDetailA
                                rightDetail: root.compareDetailB
                                leftLoading: root.compareLoadingA
                                rightLoading: root.compareLoadingB
                                leftError: root.compareErrorA
                                rightError: root.compareErrorB
                                fg: root.fg
                                dim: root.dim
                                fontFamily: root.fontFamily
                            }

                            // ---------- loadout hub ----------
                            HubPanel {
                                id: hubPanel
                                visible: root.hubMode
                                Layout.fillWidth: true
                                listMode: root.hubBuildId === ""
                                builds: root.hubBuilds
                                build: root.hubBuild
                                cursor: root.hubBuildId === "" ? root.hubCursor : root.hubSlotCursor
                                loading: root.hubLoading
                                error: root.hubError
                                fg: root.fg
                                dim: root.dim
                                fontFamily: root.fontFamily
                                iconUrlOf: root.iconFileUrl
                                focusTarget: winKeys
                                onOpenBuild: function (id) {
                                    openHubBuild(id);
                                }
                                onOpenItem: function (url) {
                                    root.openItem(url);
                                }
                                onMarkSlot: function (index) {
                                    root.hubSlotCursor = index;
                                    root.markHubSlot();
                                }
                            }

                            NewsList {
                                visible: root.newsMode
                                Layout.fillWidth: true
                                items: root.news
                                maxItems: root.news.length
                                compact: false
                                fg: root.fg
                                dim: root.dim
                                fontFamily: root.fontFamily
                                onOpenRequested: function (url) {
                                    root.openItem(url);
                                }
                            }

                            // ---------- settings ----------
                            ColumnLayout {
                                id: settingsSection
                                visible: root.settingsMode
                                Layout.fillWidth: true
                                spacing: Style.space(10)

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
                                            onModified: function (value) {
                                                root.setDraftValue("refreshIntervalSec", value);
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: Style.space(4)

                                            Text {
                                                text: "Default category"
                                                color: root.dim
                                                font.family: root.fontFamily
                                                font.pixelSize: Style.font.caption
                                            }

                                            CategorySelect {
                                                focusTarget: winKeys
                                                items: root.items
                                                kinds: root.kinds
                                                activeKind: String(root.draftValue("defaultKind", "weapon"))
                                                fg: root.fg
                                                fontFamily: root.fontFamily
                                                onSetKind: function (k) {
                                                    root.setDraftValue("defaultKind", k);
                                                }
                                            }
                                        }

                                        TextField {
                                            id: filterField
                                            Layout.fillWidth: true
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

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: Style.space(8)

                                            Button {
                                                radius: root.cornerRadius
                                                text: root.statsPrefetching ? "Fetching stats…" : "Prefetch all stats"
                                                tooltipText: "Download every item's stat details into the local cache (compare opens instantly afterwards)"
                                                foreground: root.fg
                                                fontFamily: root.fontFamily
                                                fontSize: Style.font.caption
                                                horizontalPadding: Style.spacing.controlPaddingX
                                                verticalPadding: Style.spacing.controlPaddingY
                                                onClicked: root.prefetchAllStats()
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                visible: root.statsPrefetching
                                                text: "Fetching stats… " + root.statsQueue.length + " items left"
                                                color: root.dim
                                                font.family: root.fontFamily
                                                font.pixelSize: Style.font.caption
                                                elide: Text.ElideRight
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                visible: !root.statsPrefetching && root.statsPrefetched > 0
                                                text: "Cached " + root.statsPrefetched + " item stats this session"
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
                                            id: alwaysShowToggle
                                            Layout.fillWidth: true
                                            label: "Always show icon"
                                            description: checked ? "Icon visible even while offline" : "Icon hidden when offline"
                                            checked: root.draftValue("alwaysShow", true) === true
                                            foreground: root.fg
                                            accent: Color.accent
                                            fontFamily: root.fontFamily
                                            onClicked: root.setDraftValue("alwaysShow", !checked)
                                        }

                                        Toggle {
                                            id: notifyToggle
                                            Layout.fillWidth: true
                                            label: "Notify on new build"
                                            description: checked ? "Popup when the WARDOGS build version changes" : "No build-change popup"
                                            checked: root.draftValue("notifyOnNewVersion", true) === true
                                            foreground: root.fg
                                            accent: Color.accent
                                            fontFamily: root.fontFamily
                                            onClicked: root.setDraftValue("notifyOnNewVersion", !checked)
                                        }

                                        Toggle {
                                            id: notifyNewsToggle
                                            Layout.fillWidth: true
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

                    // Help pinned to the bottom of the window.
                    Text {
                        Layout.fillWidth: true
                        text: root.settingsMode ? "j/k or ↑↓ select · enter toggle · s save · esc back" : root.newsMode ? "click an article to open it · r refresh · esc back" : root.compareMode ? "x swap sides · v or esc back to the armory" : root.hubMode ? (root.hubBuildId !== "" ? "enter open item · c mark for compare · esc back to builds" : "↑↓ or jk select · enter open build · / search · hot/top + role filters · esc back") : "←→ ↑↓ · jk select · enter open · c mark for compare · v compare · / search · r refresh · n news ·  s settings · esc close"
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
