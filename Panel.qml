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
    property var compareA: null            // first marked row {id,name,...}
    property var compareB: null            // second marked row
    property bool compareMode: false       // compare view is the visible body
    property bool mapChooserVisible: false // maps icon → choose a region
    property var compareCache: ({})        // id -> normalized detail | false (failed once)
    property string compareFetchId: ""     // id being read from the disk cache
    property var compareFetchQueue: []     // [id] disk reads waiting their turn
    property var compareNetQueue: []       // [id] disk misses awaiting a pair fetch
    property var compareInFlight: []       // [id] ids in the live pair fetch

    // Slots are pointers into compareCache; load/error state derives from
    // the cache so swaps and re-marks can never orphan an in-flight fetch.
    function compareDetailOf(row) {
        if (!row)
            return null;
        var d = root.compareCache[String(row.id)];
        return d && d !== false ? d : null;
    }

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
    property var hubReadQueue: []          // cache reads waiting their turn (shared proc)
    property string hubNetTarget: ""       // "list" | build id whose live fetch is in flight
    property string hubPendingFetch: ""    // deferred miss, kicked when the slot frees
    readonly property string hubDir: Quickshell.env("HOME") + "/.cache/wardogs-plugin/hub"
    property string hubQuery: ""           // pinned search field
    property string hubRole: ""            // pinned role chip ("" = all)
    property string hubSort: "hot"         // pinned sort chip: hot | new | top
    readonly property var hubFiltered: Hub.filterBuilds(root.hubBuilds, root.hubQuery, root.hubRole, root.hubSort)
    readonly property var hubRoleOptions: Hub.hubRoles()

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
    readonly property int winGridColumns: 6

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

    // soft-scrolls the keyboard selection into view; imperative so user
    // flicks and drags are never animated behind their back
    NumberAnimation {
        id: scrollRevealAnim
        target: winScroller
        property: "contentY"
        duration: 200
        easing.type: Easing.OutCubic
    }

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
        var target = -1;
        if (y < winScroller.contentY + Style.space(4))
            target = Math.max(0, y - Style.space(36));
        else if (y + item.height > winScroller.contentY + winScroller.height - Style.space(4))
            target = y + item.height - winScroller.height + Style.space(8);
        if (target >= 0) {
            // never scroll past the content ends
            var max = Math.max(0, winScroller.contentHeight - winScroller.height);
            scrollRevealAnim.to = Math.max(0, Math.min(target, max));
            scrollRevealAnim.restart();
        }
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

    // Generic toggle for any row shaped {id, name} — the browse grid, the
    // hub's slot cards and build cards all feed the same compare slots.
    // The third mark replaces A. Details live in compareCache keyed by id;
    // slots only point at them.
    function markCompareRow(row) {
        if (!row || String(row.id || "") === "")
            return;
        if (root.compareA && root.compareA.id === row.id) {
            root.compareA = null;
            console.log("[compare] unmark A", row.id);
            return;
        }
        if (root.compareB && root.compareB.id === row.id) {
            root.compareB = null;
            console.log("[compare] unmark B", row.id);
            return;
        }
        if (root.compareA === null) {
            root.compareA = row;
            console.log("[compare] mark A", row.id);
        } else if (root.compareB === null) {
            root.compareB = row;
            console.log("[compare] mark B", row.id);
        } else {
            root.compareA = row;
            console.log("[compare] replace A", row.id);
        }
    }

    function openCompare() {
        root.compareMode = true;
        root.settingsMode = false;
        root.newsMode = false;
        root.hubMode = false;
        ensureCompareDetail(root.compareA);
        ensureCompareDetail(root.compareB);
        focusWinKeys();
    }

    // Swapping the pointers swaps the whole sheet — details and load state
    // derive per id, so an in-flight fetch lands on the right side however
    // the slots are shuffled mid-load.
    function swapCompare() {
        var a = root.compareA;
        root.compareA = root.compareB;
        root.compareB = a;
    }

    // Is this id anywhere in the resolution pipeline?
    function comparePending(id) {
        if (root.compareFetchId === id)
            return true;
        var i;
        for (i = 0; i < root.compareFetchQueue.length; i++)
            if (root.compareFetchQueue[i] === id)
                return true;
        for (i = 0; i < root.compareNetQueue.length; i++)
            if (root.compareNetQueue[i] === id)
                return true;
        for (i = 0; i < root.compareInFlight.length; i++)
            if (root.compareInFlight[i] === id)
                return true;
        return false;
    }

    // Make sure the row's detail resolves eventually: memory/disk caches,
    // then the pair fetch. A failed resolve (false) clears on every open so
    // a transient site/network failure retries instead of sticking for the
    // whole session.
    function ensureCompareDetail(row) {
        if (!row)
            return;
        var id = String(row.id || "");
        if (id === "")
            return;
        if (root.compareCache[id] === false) {
            var cache = cloneObject(root.compareCache, {});
            delete cache[id];
            root.compareCache = cache;
        }
        if (root.compareCache[id] !== undefined)
            return;
        if (comparePending(id))
            return;
        root.compareFetchQueue = root.compareFetchQueue.concat([id]);
        kickCompareCacheRead();
    }

    function kickCompareCacheRead() {
        if (root.compareFetchId !== "" || root.compareFetchQueue.length === 0)
            return;
        var id = root.compareFetchQueue[0];
        root.compareFetchQueue = root.compareFetchQueue.slice(1);
        root.compareFetchId = id;
        detailCacheReadProc.command = ["sh", "-c", "cat \"$1\" 2>/dev/null || true", "sh", root.detailCachePath(id)];
        detailCacheReadProc.running = true;
    }

    function commitCompareDetail(id, detail) {
        var cache = cloneObject(root.compareCache, {});
        cache[id] = detail || false;
        root.compareCache = cache;
    }

    // Pipeline: next disk read, and once none are pending, the pair fetch.
    function advanceCompareFetch() {
        root.compareFetchId = "";
        if (root.compareFetchQueue.length > 0) {
            kickCompareCacheRead();
            return;
        }
        kickCompareNet();
    }

    // The site's compare endpoint renders two stat blobs per request —
    // batch misses two ids at a time (the shape proven to render both).
    function kickCompareNet() {
        if (root.compareInFlight.length > 0 || root.compareNetQueue.length === 0 || detailFetchProc.running)
            return;
        var batch = root.compareNetQueue.slice(0, 2);
        root.compareNetQueue = root.compareNetQueue.slice(batch.length);
        root.compareInFlight = batch;
        detailFetchProc.command = ["sh", "-c", "mkdir -p \"$2\"; curl -fsS --max-time 8 \"$1\"", "sh", Model.compareUrl(batch), root.detailCacheDir];
        detailFetchProc.running = true;
    }

    // Disk-cache read: a body whose id matches counts as a hit; anything
    // else queues for the pair fetch.
    function onCompareCacheRaw(raw) {
        var id = root.compareFetchId;
        if (id === "")
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
            commitCompareDetail(id, detail);
        } else if (root.compareNetQueue.indexOf(id) === -1 && root.compareInFlight.indexOf(id) === -1) {
            root.compareNetQueue = root.compareNetQueue.concat([id]);
        }
        advanceCompareFetch();
    }

    function onCompareDetailHtml(raw) {
        var batch = root.compareInFlight;
        root.compareInFlight = [];
        var capped = String(raw || "");
        if (capped.length > root.maxDetailBytes)
            capped = capped.substring(0, root.maxDetailBytes);
        for (var i = 0; i < batch.length; i++) {
            var id = batch[i];
            var detail = capped === "" ? null : Details.parseDetails(capped, id);
            if (detail) {
                detailCacheView.path = root.detailCachePath(id);
                detailCacheView.setText(JSON.stringify(detail));
            }
            commitCompareDetail(id, detail);
        }
        kickCompareNet();
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
        enqueueHubRead("list");
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
            // stale-while-revalidate: the cache may predate a republish, so
            // refresh in the background — the sheet stays up either way
            refreshHubBuild(id);
            return;
        }
        root.hubBuild = null;
        enqueueHubRead(id);
    }

    // Cache reads share one Process; rapid openHub + openHubBuild calls must
    // not overwrite each other's target, so reads queue and start in order.
    function enqueueHubRead(target) {
        if (root.hubReadTarget === target || root.hubReadQueue.indexOf(target) !== -1)
            return;
        if (root.hubReadTarget === "") {
            startHubRead(target);
            return;
        }
        root.hubReadQueue = root.hubReadQueue.filter(function (t) {
            return t !== target;
        }).concat([target]);
    }

    function startHubRead(target) {
        root.hubReadTarget = target;
        hubCacheReadProc.command = ["sh", "-c", "cat \"$1\" 2>/dev/null || true", "sh", target === "list" ? root.hubCachePath("list") : root.hubCachePath(target)];
        hubCacheReadProc.running = true;
    }

    function dequeueHubRead() {
        if (root.hubReadQueue.length === 0)
            return;
        var next = root.hubReadQueue[0];
        root.hubReadQueue = root.hubReadQueue.slice(1);
        startHubRead(next);
    }

    function applyHubBuild(id, build) {
        console.log("[hubdbg] apply", id, "title", build ? String(build.title) : "null", "keys", build ? Object.keys(build).join(",") : "-");
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
        // Flat slot count for the detail cursor: everything except the
        // Traversal slots, which render only in the storage grid (the raw
        // slots array is grouped non-traversal-first).
        var n = 0;
        if (root.hubBuild) {
            for (var i = 0; i < root.hubBuild.slots.length; i++) {
                if (root.hubBuild.slots[i].section !== "Traversal")
                    n++;
            }
        }
        return n;
    }

    // The hub panel filters/sorts its list internally (search + hot/top +
    // role chips); the cursor indexes into THAT list, so activation reads
    // hubPanel.filteredBuilds rather than the raw hubBuilds.
    function hubMove(d) {
        if (root.hubBuildId === "") {
            var n = root.hubFiltered.length;
            if (n === 0)
                return;
            root.hubCursor = clamp(root.hubCursor + d, 0, n - 1);
        } else {
            root.hubSlotCursor = clamp(root.hubSlotCursor + d, 0, Math.max(0, hubRows() - 1));
        }
        hubPanel.revealCursor();
    }

    function hubActivate() {
        if (root.hubBuildId === "") {
            var list = root.hubFiltered;
            if (root.hubCursor < list.length)
                openHubBuild(list[root.hubCursor].id);
        } else if (root.hubSlotCursor < hubRows()) {
            openItem(Model.itemUrl(root.hubBuild.slots[root.hubSlotCursor].itemId));
        }
    }

    function markHubSlot() {
        markHubSlotAt(root.hubSlotCursor);
    }

    // Raw-index marking so mouse paths (parachute card, grid cells) can mark
    // traversal slots the keyboard cursor never reaches.
    function markHubSlotAt(index) {
        if (root.hubBuildId === "" || root.hubBuild === null)
            return;
        if (index < 0 || index >= root.hubBuild.slots.length)
            return;
        var slot = root.hubBuild.slots[index];
        if (String(slot.itemId) === "")
            return;
        markCompareRow({
            "id": slot.itemId,
            "name": slot.name
        });
    }

    // Mark the build under the list cursor for a build-vs-build compare.
    // The card's summary numbers are seeded into the detail cache so the
    // sheet resolves instantly — a /database fetch can't resolve build ids.
    function markHubBuild() {
        if (root.hubCursor >= root.hubFiltered.length)
            return;
        var row = root.hubFiltered[root.hubCursor];
        var marked = (root.compareA && root.compareA.id === row.id) || (root.compareB && root.compareB.id === row.id);
        // The pseudo detail doubles as the slot row (id + name) AND the
        // seeded cache entry, so the sheet resolves with zero fetching.
        var detail = Hub.buildToDetail(row);
        if (!marked) {
            var cache = cloneObject(root.compareCache, {});
            cache[row.id] = detail;
            root.compareCache = cache;
        }
        markCompareRow(detail);
    }

    function onHubCacheRaw(raw) {
        var target = root.hubReadTarget;
        root.hubReadTarget = "";
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
            if (parsed && parsed.v === Hub.CACHE_VERSION && parsed.builds) {
                root.hubLoading = false;
                root.hubBuilds = parsed.builds;
                root.hubBuilds.forEach(function (b) {
                    requestIcon(b.iconId);
                });
            } else {
                // disk miss (or pre-versioning cache) → live fetch; keep the
                // loading flag up so the list reads "Loading hub…" instead
                // of flashing "No builds match."
                root.hubLoading = true;
                queueHubFetch("list");
            }
        } else {
            if (parsed && parsed.v === Hub.CACHE_VERSION) {
                applyHubBuild(target, parsed);
            } else {
                queueHubFetch(target);
            }
        }
        dequeueHubRead();
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

    function queueHubFetch(target) {
        if (root.hubNetTarget !== "") {
            root.hubPendingFetch = target;
            return;
        }
        root.hubNetTarget = target;
        if (target === "list")
            fetchHubListNetwork();
        else
            fetchHubBuildNetwork(target);
    }

    function kickHubPending() {
        if (root.hubPendingFetch === "" || root.hubNetTarget !== "")
            return;
        var t = root.hubPendingFetch;
        root.hubPendingFetch = "";
        root.hubNetTarget = t;
        if (t === "list")
            fetchHubListNetwork();
        else
            fetchHubBuildNetwork(t);
    }

    function refreshHubBuild(id) {
        // one live fetch is routed at a time (hubNetTarget); if one is in
        // flight this open keeps the cache and the next open revalidates
        if (root.hubNetTarget !== "")
            return;
        root.hubNetTarget = id;
        fetchHubBuildNetwork(id);
    }

    function onHubListHtml(raw) {
        root.hubNetTarget = "";
        root.hubLoading = false;
        var capped = String(raw || "");
        if (capped.length > root.maxDetailBytes)
            capped = capped.substring(0, root.maxDetailBytes);
        var builds = Hub.parseHubList(capped);
        if (builds.length > 0) {
            root.hubBuilds = builds;
            hubCacheView.path = root.hubCachePath("list");
            hubCacheView.setText(JSON.stringify({
                "v": Hub.CACHE_VERSION,
                "builds": builds
            }));
            builds.forEach(function (b) {
                requestIcon(b.iconId);
            });
        } else {
            root.hubListFailed = true;
            root.hubError = builds.length === 0 && root.hubBuilds.length === 0 ? "Offline — can't reach the loadout hub." : "";
        }
        kickHubPending();
    }

    function onHubBuildHtml(raw) {
        var id = root.hubNetTarget;
        root.hubNetTarget = "";
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
        } else if (root.hubBuild === null || root.hubBuildId !== id) {
            root.hubError = "Could not load this build — open it on the site instead.";
        }
        kickHubPending();
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
                // route by the fetch target — hubReadTarget tracks cache
                // reads and may already point at the next queued file
                if (root.hubNetTarget === "list")
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
    function learnIconNames(text) {
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

    // fast pass: learn what is on disk immediately so cached icons render
    // without waiting for the (much slower) mogrify migration below
    Process {
        id: iconListProc
        running: true
        command: ["sh", "-c", "mkdir -p \"$1\"; ls -1 \"$1\" || true", "sh", root.iconDir]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: learnIconNames(text)
        }
    }

    // slow pass: migrate any pre-normalization icons onto the uniform 96x96
    // square and whiten them (idempotent), then re-learn
    Process {
        id: iconScanProc
        running: true
        command: ["sh", "-c", "mogrify -trim +repage -alpha set -background none -gravity center -channel RGB -fill white -colorize 100% -resize '192x192>' -extent 192x192 \"$1\"/*.png 2>/dev/null || true; ls -1 \"$1\" || true", "sh", root.iconDir]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: learnIconNames(text)
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
        function open() {
            root.openSettings();
        }
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

    // One target per panel so scripts can drive the plugin directly:
    // omarchy-shell niziul.wardogs.<panel> <method> [args]
    IpcHandler {
        target: "niziul.wardogs.armory"
        function open() {
            root.showMain();
        }
    }

    IpcHandler {
        target: "niziul.wardogs.news"
        function open() {
            root.openNews();
        }
    }

    IpcHandler {
        target: "niziul.wardogs.compare"
        function open() {
            root.open();
            root.openCompare();
        }
        function mark() {
            // mark the armory item under the keyboard cursor
            root.markCompare();
        }
        function swap() {
            root.swapCompare();
        }
        function clear() {
            root.compareA = null;
            root.compareB = null;
        }
    }

    IpcHandler {
        target: "niziul.wardogs.hub"
        function open() {
            root.open();
            root.openHub();
        }
        function openBuild(id: string) {
            if (id === "")
                return;
            root.open();
            root.openHub();
            root.openHubBuild(id);
        }
        function back() {
            // build sheet → list (no-op when already on the list)
            root.closeHubBuild();
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
            if (!visible)
                root.mapChooserVisible = false;
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
                if (root.mapChooserVisible) {
                    root.mapChooserVisible = false;
                    return;
                }
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
                    // h/l join j/k — the hub cursor is a flat list, so they
                    // simply mirror down/up
                    if (event.key === Qt.Key_J || event.text === "j" || event.text === "l" || event.text === "L")
                        root.hubMove(1);
                    else if (event.key === Qt.Key_K || event.text === "k" || event.text === "h" || event.text === "H")
                        root.hubMove(-1);
                    else if (event.text === "c" || event.text === "C") {
                        if (root.hubBuildId === "")
                            root.markHubBuild();
                        else
                            root.markHubSlot();
                    } else if (event.text === "v" || event.text === "V")
                        root.openCompare();
                    else if (event.text === "/" && root.hubBuildId === "") {
                        hubSearchInput.forceActiveFocus();
                        hubSearchInput.cursorPosition = hubSearchInput.text.length;
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
                else if (event.text === "b" || event.text === "B")
                    root.openHub();
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
                                    if (String(url).indexOf("https://wardogs.zone/maps") === 0) {
                                        root.mapChooserVisible = true;
                                    } else {
                                        root.openItem(url);
                                    }
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
                                visible: !root.settingsMode && !root.newsMode && !root.compareMode && !root.hubMode
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
                            visible: !root.settingsMode && !root.newsMode && !root.compareMode && !root.hubMode
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
                            visible: !root.settingsMode && !root.newsMode && !root.compareMode && !root.hubMode
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
                                visible: !root.settingsMode && !root.newsMode && !root.compareMode && !root.hubMode
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

                    // Pinned hub search + filters: lives outside the
                    // scroller so it stays on screen while the build list
                    // scrolls beneath it.
                    RowLayout {
                        visible: root.hubMode && root.hubBuildId === ""
                        Layout.fillWidth: true
                        spacing: Style.space(6)

                        TextField {
                            id: hubSearchInput
                            Layout.fillWidth: true
                            placeholderText: "Search builds by name, author, weapon…"
                            foreground: root.fg
                            accent: Color.accent
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            text: root.hubQuery
                            onTextEdited: root.hubQuery = hubSearchInput.text
                            Keys.onEscapePressed: {
                                root.hubQuery = "";
                                hubSearchInput.text = "";
                                winKeys.forceActiveFocus();
                            }
                            Keys.onUpPressed: {
                                hubSearchInput.focus = false;
                                root.hubMove(-1);
                            }
                            Keys.onDownPressed: {
                                hubSearchInput.focus = false;
                                root.hubMove(1);
                            }
                            Keys.onReturnPressed: {
                                hubSearchInput.focus = false;
                                root.hubActivate();
                            }
                            Keys.onEnterPressed: {
                                hubSearchInput.focus = false;
                                root.hubActivate();
                            }
                        }

                        Button {
                            visible: root.hubQuery !== ""
                            radius: root.cornerRadius
                            text: "\u2715"
                            tooltipText: "Clear hub search"
                            foreground: root.fg
                            fontFamily: root.fontFamily
                            fontSize: Style.font.caption
                            horizontalPadding: Style.space(8)
                            verticalPadding: Style.space(2)
                            onClicked: {
                                root.hubQuery = "";
                                hubSearchInput.text = "";
                                hubSearchInput.forceActiveFocus();
                            }
                        }

                        Button {
                            text: "Hot"
                            tooltipText: "Score blended with recency"
                            radius: root.cornerRadius
                            active: root.hubSort === "hot"
                            foreground: root.fg
                            fontFamily: root.fontFamily
                            fontSize: Style.font.caption
                            horizontalPadding: Style.space(8)
                            verticalPadding: Style.space(2)
                            onClicked: root.hubSort = "hot"
                        }

                        Button {
                            text: "New"
                            tooltipText: "Newest published first"
                            radius: root.cornerRadius
                            active: root.hubSort === "new"
                            foreground: root.fg
                            fontFamily: root.fontFamily
                            fontSize: Style.font.caption
                            horizontalPadding: Style.space(8)
                            verticalPadding: Style.space(2)
                            onClicked: root.hubSort = "new"
                        }

                        Button {
                            text: "Top"
                            tooltipText: "Highest scored first"
                            radius: root.cornerRadius
                            active: root.hubSort === "top"
                            foreground: root.fg
                            fontFamily: root.fontFamily
                            fontSize: Style.font.caption
                            horizontalPadding: Style.space(8)
                            verticalPadding: Style.space(2)
                            onClicked: root.hubSort = "top"
                        }

                        Button {
                            text: "All"
                            tooltipText: "Every role"
                            radius: root.cornerRadius
                            active: root.hubRole === ""
                            foreground: root.fg
                            fontFamily: root.fontFamily
                            fontSize: Style.font.caption
                            horizontalPadding: Style.space(8)
                            verticalPadding: Style.space(2)
                            onClicked: root.hubRole = ""
                        }

                        Repeater {
                            model: root.hubRoleOptions

                            delegate: Button {
                                required property string modelData
                                text: modelData
                                tooltipText: modelData + " builds"
                                radius: root.cornerRadius
                                active: root.hubRole.toLowerCase() === modelData.toLowerCase()
                                foreground: root.fg
                                fontFamily: root.fontFamily
                                fontSize: Style.font.caption
                                horizontalPadding: Style.space(8)
                                verticalPadding: Style.space(2)
                                onClicked: root.hubRole = modelData
                            }
                        }

                        Text {
                            text: root.hubFiltered.length + " / " + root.hubBuilds.length + " builds"
                            color: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
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
                                        selected: index === root.winCursor
                                        onHoveredChanged: {
                                            // hover and keyboard share the one
                                            // cursor, so an input lights exactly
                                            // one tile
                                            if (hovered) {
                                                root.winCursor = index;
                                                root.keyboardMode = false;
                                            }
                                        }
                                        name: modelData.name
                                        typeText: modelData.type
                                        caliberText: modelData.caliber
                                        // price shows once the item's stats are cached (prefetch or compare)
                                        price: {
                                            var d = root.compareCache[modelData.id];
                                            return d && d.price !== undefined ? Compare.formatPrice(d.price) : "";
                                        }
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
                                visible: root.compareMode
                                Layout.fillWidth: true
                                Layout.preferredHeight: Math.max(Style.space(300), winScroller.height - Style.space(50))
                                leftItem: root.compareA
                                rightItem: root.compareB
                                leftDetail: root.compareDetailOf(root.compareA)
                                rightDetail: root.compareDetailOf(root.compareB)
                                // per-side state derives from the cache: no
                                // entry yet = loading, false = failed resolve
                                leftLoading: root.compareA !== null && root.compareCache[root.compareA.id] === undefined
                                rightLoading: root.compareB !== null && root.compareCache[root.compareB.id] === undefined
                                leftError: root.compareA !== null && root.compareCache[root.compareA.id] === false
                                rightError: root.compareB !== null && root.compareCache[root.compareB.id] === false
                                fg: root.fg
                                dim: root.dim
                                fontFamily: root.fontFamily
                            }

                            // ---------- loadout hub ----------
                            HubPanel {
                                id: hubPanel
                                visible: root.hubMode
                                scrollContent: winScroller.contentItem
                                onReveal: function (y, height) {
                                    var target = -1;
                                    if (y < winScroller.contentY + Style.space(4))
                                        target = Math.max(0, y - Style.space(36));
                                    else if (y + height > winScroller.contentY + winScroller.height - Style.space(4))
                                        target = y + height - winScroller.height + Style.space(8);
                                    if (target >= 0) {
                                        // never scroll past the content ends
                                        var max = Math.max(0, winScroller.contentHeight - winScroller.height);
                                        scrollRevealAnim.to = Math.max(0, Math.min(target, max));
                                        scrollRevealAnim.restart();
                                    }
                                }
                                Layout.fillWidth: true
                                listMode: root.hubBuildId === ""
                                builds: root.hubFiltered
                                build: root.hubBuild
                                cursor: root.hubBuildId === "" ? root.hubCursor : root.hubSlotCursor
                                loading: root.hubLoading
                                error: root.hubError
                                fg: root.fg
                                dim: root.dim
                                fontFamily: root.fontFamily
                                iconUrlOf: root.iconFileUrl
                                badgeOf: function (id) {
                                    return root.compareA && root.compareA.id === id ? "A" : root.compareB && root.compareB.id === id ? "B" : "";
                                }
                                onOpenBuild: function (id) {
                                    openHubBuild(id);
                                }
                                onOpenItem: function (url) {
                                    root.openItem(url);
                                }
                                onMarkSlot: function (index) {
                                    root.markHubSlotAt(index);
                                }
                                onMarkBuild: function (index) {
                                    root.hubCursor = index;
                                    root.markHubBuild();
                                }
                                onHoverCard: function (index) {
                                    root.hubCursor = index;
                                }
                                onHoverSlot: function (index) {
                                    root.hubSlotCursor = index;
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
                        text: root.settingsMode ? "j/k or ↑↓ select · enter toggle · s save · esc back" : root.newsMode ? "click an article to open it · r refresh · esc back" : root.compareMode ? "x swap sides · v or esc back to the armory" : root.hubMode ? (root.hubBuildId !== "" ? "click open · r-click or c mark for compare · esc back to builds" : "↑↓ or jk select · enter open build · r-click or c mark · / search · esc back") : "←→ ↑↓ · jk select · enter open · c mark for compare · v compare · / search · r refresh · n news ·  s settings · esc close"
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }
        }

        // Map chooser: the toolbar's maps icon opens this instead of a URL,
        // so the map region is a real choice (scrim click or esc cancels).
        Rectangle {
            anchors.fill: parent
            visible: root.mapChooserVisible
            color: Qt.rgba(0, 0, 0, 0.55)

            MouseArea {
                anchors.fill: parent
                onClicked: root.mapChooserVisible = false
            }

            Rectangle {
                width: Style.space(280)
                height: mapCol.implicitHeight + Style.space(24)
                anchors.centerIn: parent
                color: Color.popups.background
                border.width: 1
                border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.3)

                ColumnLayout {
                    id: mapCol
                    anchors.fill: parent
                    anchors.margins: Style.space(12)
                    spacing: Style.space(6)

                    Text {
                        Layout.fillWidth: true
                        text: "CHOOSE A MAP"
                        color: root.fg
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        font.letterSpacing: 1
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Repeater {
                        model: Model.maps()

                        delegate: Rectangle {
                            id: mapRow
                            required property var modelData

                            Layout.fillWidth: true
                            implicitHeight: Style.space(32)
                            radius: 0
                            color: mapRow.hovered ? Style.hoverFillFor(root.fg, root.accentColor) : "transparent"
                            border.width: 1
                            border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, mapRow.hovered ? 0.4 : 0.15)

                            property bool hovered: false

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: Style.space(10)
                                anchors.verticalCenter: parent.verticalCenter
                                text: mapRow.modelData.label
                                color: root.fg
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                            }

                            Text {
                                anchors.right: parent.right
                                anchors.rightMargin: Style.space(10)
                                anchors.verticalCenter: parent.verticalCenter
                                text: "\uF14C"
                                color: root.dim
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.mapChooserVisible = false;
                                    root.openItem("https://wardogs.zone/maps/" + mapRow.modelData.id);
                                }
                                hoverEnabled: true
                                onContainsMouseChanged: mapRow.hovered = containsMouse
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "esc to cancel"
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
