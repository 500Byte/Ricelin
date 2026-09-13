pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import QtMultimedia
import "Singletons"

/**
 * Wallpaper surface: a filmstrip over the wallpaper directory, rendered as one
 * of the pill's surfaces. Thumbs come from the Walls singleton snapshot, newest
 * first. The focused thumb is large and fully lit; neighbours shrink, dim and
 * desaturate as they slide under it, so the strip reads as depth. Arrow keys
 * and wheel move focus, clicking a neighbour glides to it, Enter or a tap on
 * the focused thumb applies it via wallpaper.sh (strip stays open so you can
 * keep trying picks). Hold the focused thumb for the heat duration to trash the
 * file (press-and-hold confirm, same as the clipboard wipe); progress sweeps
 * along the thumb's lower edge and drains on early release.
 *
 * Typing any printable character while the strip is open drops it into a
 * remote image search (Wallhaven or MoeWalls, depending on searchMode):
 * a search field reveals at the top, the strip swaps
 * its model from local files to remote results (debounced fetch through
 * wallpaper-search.sh), and selecting a result downloads it, applies it and
 * returns to the local strip. Escape, an emptied query or a finished pick all
 * fall back to the local view.
 */
PillSurface {
    id: root

    property int focusIndex: 0

    /**
     * Search mode. While off the strip browses local files and bare keys are
     * watched for the first printable character; while on the search field is
     * shown, holds focus and the strip renders remote results for `query`.
     */
    property string searchMode: "wallhaven" // "wallhaven" or "moewalls"

    property bool searching: false
    onSearchingChanged: {
        if (searching) {
            triggerSearch();
        } else {
            currentPage = 1;
            totalPages = 0;
            totalResults = 0;
            loadingMore = false;
            searchCache = ({});
        }
    }
    property string query: ""
    property var ddgResults: []
    property bool pendingSearch: false
    property var activeSearchProcess: null

    property string filterSort: "relevance"
    property string filterRange: "1M"
    property string filterPurity: "100"
    property string filterCategories: "111"
    property string filterRatio: ""

    property string moeResolution: "2560x1440"
    property string moeOrder: "most_upvotes"

    property int currentPage: 1
    property int totalPages: 0
    property int totalResults: 0
    property bool loadingMore: false
    property var searchCache: ({})
    property bool searchErrorShown: false


    function filterSortLabel(s) {
        if (s === "relevance") return "Relevance";
        if (s === "toplist") return "Top List";
        if (s === "views") return "Most Viewed";
        if (s === "random") return "Random";
        if (s === "date_added") return "Date Added";
        return s;
    }

    function filterRangeLabel(r) {
        if (r === "1d") return "1 Day";
        if (r === "1w") return "1 Week";
        if (r === "1M") return "1 Month";
        if (r === "3M") return "3 Months";
        if (r === "6M") return "6 Months";
        if (r === "1y") return "1 Year";
        return r;
    }

    function filterCategoriesLabel(c) {
        if (c === "100") return "General";
        if (c === "010") return "Anime";
        if (c === "001") return "People";
        if (c === "111") return "All";
        if (c === "110") return "Gen+Anime";
        if (c === "101") return "Gen+People";
        if (c === "011") return "Ani+People";
        return c;
    }

    function filterRatioLabel(r) {
        if (r === "") return "Any";
        if (r === "16x9") return "16:9";
        if (r === "21x9") return "21:9";
        if (r === "16x10") return "16:10";
        if (r === "4x3") return "4:3";
        if (r === "9x16") return "9:16";
        return r;
    }

    function cycleSort() {
        const list = ["relevance", "toplist", "views", "random", "date_added"];
        var idx = list.indexOf(filterSort);
        filterSort = list[(idx + 1) % list.length];
        currentPage = 1;
        loadingMore = false;
        debouncedSearch.restart();
    }

    function cycleRange() {
        const list = ["1d", "1w", "1M", "3M", "6M", "1y"];
        var idx = list.indexOf(filterRange);
        filterRange = list[(idx + 1) % list.length];
        currentPage = 1;
        loadingMore = false;
        debouncedSearch.restart();
    }

    function cyclePurity() {
        const list = ["100", "010", "111"];
        var idx = list.indexOf(filterPurity);
        filterPurity = list[(idx + 1) % list.length];
        currentPage = 1;
        loadingMore = false;
        debouncedSearch.restart();
    }

    function cycleCategories() {
        const list = ["111", "100", "010", "001", "110", "101", "011"];
        var idx = list.indexOf(filterCategories);
        filterCategories = list[(idx + 1) % list.length];
        currentPage = 1;
        loadingMore = false;
        debouncedSearch.restart();
    }

    function cycleRatio() {
        const list = ["", "16x9", "21x9", "16x10", "4x3", "9x16"];
        var idx = list.indexOf(filterRatio);
        filterRatio = list[(idx + 1) % list.length];
        currentPage = 1;
        loadingMore = false;
        debouncedSearch.restart();
    }

    function moeOrderLabel(o) {
        const labels = {
            "most_upvotes": "Top Voted",
            "most_views": "Most Views",
            "newest": "Newest",
            "random": "Random"
        };
        return labels[o] || o;
    }

    function cycleMoeOrder() {
        const list = ["most_upvotes", "most_views", "newest", "random"];
        var idx = list.indexOf(moeOrder);
        moeOrder = list[(idx + 1) % list.length];
        currentPage = 1;
        loadingMore = false;
        triggerSearch();
    }

    Timer {
        id: debouncedSearch
        interval: root.query.length < 3 ? 800 : 400
        repeat: false
        onTriggered: root.triggerSearch()
    }

    function triggerSearch() {
        if (!searching) return;

        var sanitizedQuery = root.query.replace(/[;&|`$]/g, "");

        var isFirstPage = root.currentPage === 1;
        var cacheKey = root.searchMode + "|" + sanitizedQuery + "|" +
                       root.currentPage + "|" +
                       (root.searchMode === "moewalls"
                           ? root.moeResolution + "|" + root.moeOrder
                           : root.filterSort + "|" + root.filterRange + "|" +
                             root.filterPurity + "|" + root.filterCategories + "|" +
                             root.filterRatio);

        if (isFirstPage && root.searchCache[cacheKey]) {
            var cached = root.searchCache[cacheKey];
            root.ddgResults = cached.results;
            root.totalPages = cached.totalPages;
            root.totalResults = cached.totalResults;
            root.loadingMore = false;
            return;
        }

        if (activeSearchProcess) {
            var oldProc = activeSearchProcess;
            activeSearchProcess = null;
            oldProc.running = false;
            Qt.callLater(() => oldProc.destroy());
        }

        var cmdLine = root.searchMode === "moewalls"
            ? ["bash", root.searchScript, "search_moewalls", sanitizedQuery, root.moeResolution, root.moeOrder, root.currentPage]
            : ["bash", root.searchScript, "search", sanitizedQuery, root.filterSort, root.filterRange, root.filterPurity, root.filterCategories, root.filterRatio, root.currentPage];

        console.log("wallpaper cmd:", cmdLine.join(" "));

        var proc = processComponent.createObject(root, {
            command: cmdLine,
            callback: (text) => {
                try {
                    var parsed = JSON.parse(text);
                    if (parsed.error) {
                        console.error("wallpaper script error:", parsed.error);
                        if (isFirstPage) {
                            root.ddgResults = [];
                            root.searchErrorShown = true;
                        }
                        root.loadingMore = false;
                        return;
                    }
                    if (root.searchMode === "moewalls") {
                        root.totalPages = 1;
                        root.totalResults = parsed.length;
                        root.ddgResults = parsed;
                        root.focusIndex = 0;
                        root.pos = 0;
                    } else {
                        var resultItems = parsed.items || [];
                        root.totalPages = parsed.totalPages || 0;
                        root.totalResults = parsed.total || 0;
                        if (isFirstPage) {
                            root.ddgResults = resultItems;
                            root.focusIndex = 0;
                            root.pos = 0;
                        } else {
                            root.ddgResults = root.ddgResults.concat(resultItems);
                        }
                    }
                    if (isFirstPage) {
                        root.searchCache[cacheKey] = {
                            results: root.ddgResults.slice(),
                            totalPages: root.totalPages,
                            totalResults: root.totalResults
                        };
                    }
                } catch (e) {
                    console.error("Search parse error:", e, "Response:", text);
                    if (isFirstPage) {
                        root.ddgResults = [];
                        root.searchErrorShown = true;
                    }
                }
                root.loadingMore = false;
            }
        });

        activeSearchProcess = proc;
        proc.running = true;
    }

    function loadMore() {
        if (root.searchMode === "moewalls") return;
        if (loadingMore || currentPage >= totalPages) return;
        loadingMore = true;
        currentPage++;
        triggerSearch();
    }

    /**
     * Active model and its select handler. The strip, navigation and empty
     * states all read these so the local and search views share one code path:
     * a populated query in search mode shows remote results, anything else the
     * local snapshot.
     *
     * When in search mode with more pages available, a sentinel object
     * {__loadMore: true} is appended so the Repeater can render a "+"
     * button as the final tile.
     */
    readonly property var items: {
        if (searching) {
            if (searchMode === "wallhaven" && currentPage < totalPages) {
                return ddgResults.concat([{__loadMore: true}]);
            }
            return ddgResults;
        }
        return Walls.entries;
    }
    readonly property int itemCount: searching ? ddgResults.length : Walls.entries.length

    /**
     * Gesture hint visibility. Hidden while the focus is moving so paging
     * through wallpapers stays clean; the dwell timer reveals it only once the
     * pick has been held still, so it reads as a quiet caption, not a nag.
     */
    property bool hintShown: false

    onFocusIndexChanged: {
        hintShown = false;
        hintDwell.restart();
    }

    onItemsChanged: if (focusIndex >= itemCount) focusIndex = Math.max(0, itemCount - 1);

    Timer {
        id: hintDwell
        interval: 600
        onTriggered: root.hintShown = true
    }

    /**
     * Continuous view position chasing focusIndex. The strip renders from this
     * single value, so any input rate (40Hz key autorepeat, wheel bursts) stays
     * coherent: lag is bounded by the chase time constant, not piled up across
     * per-tile retargeting animations.
     */
    property real pos: 0

    clip: true
    focus: true

    Keys.enabled: root.active
    Keys.onLeftPressed: (event) => { root.move(-1); event.accepted = true; }
    Keys.onRightPressed: (event) => { root.move(1); event.accepted = true; }
    Keys.onReturnPressed: (event) => { root.activate(); event.accepted = true; }
    Keys.onEscapePressed: (event) => { root.exitSearch(); event.accepted = true; }

    readonly property var slotW:      [196, 126, 104, 88, 74]
    readonly property var slotH:      [110, 71, 59, 50, 42]
    readonly property var slotCX:     [0, 143, 244, 326, 393]
    readonly property var slotBright: [1, 0.56, 0.42, 0.30, 0.22]
    readonly property var slotSat:    [1, 0.65, 0.55, 0.45, 0.40]

    function slotLerp(arr, ao) {
        if (ao >= 4)
            return arr[4];
        var i = Math.floor(ao);
        var f = ao - i;
        return arr[i] + (arr[i + 1] - arr[i]) * f;
    }

    function offsetX(off) {
        var ao = Math.abs(off);
        var cx = ao <= 4 ? slotLerp(slotCX, ao) : slotCX[4] + (ao - 4) * 60;
        return (off < 0 ? -cx : cx) * s;
    }

    function move(delta) {
        if (itemCount === 0)
            return;
        focusIndex = Math.max(0, Math.min(itemCount - 1, focusIndex + delta));
    }

    FrameAnimation {
        running: root.active && root.pos !== root.focusIndex
        onTriggered: {
            var k = 1 - Math.exp(-frameTime / 0.07);
            var next = root.pos + (root.focusIndex - root.pos) * k;
            root.pos = Math.abs(next - root.focusIndex) < 0.001 ? root.focusIndex : next;
        }
    }

    function activate() {
        if (focusIndex < 0 || focusIndex >= itemCount)
            return;
        var entry = items[focusIndex];
        if (entry.image !== undefined) {
            if (dlProc.running)
                return;
            dlProc.target = entry.image;
            dlProc.command = ["bash", root.searchScript, "download", entry.image];
            dlProc.running = true;
        } else {
            Walls.apply(entry.path);
        }
    }

    function centerOnCurrent() {
        var idx = 0;
        for (var i = 0; i < Walls.entries.length; i++)
            if (Walls.entries[i].path === Walls.current) {
                idx = i;
                break;
            }
        focusIndex = idx;
        pos = idx;
    }

    /**
     * Leave search mode and fall back to the local strip, re-centring on the
     * wallpaper currently on screen. Used by Escape, an emptied query and a
     * completed download.
     */
    function exitSearch() {
        searching = false;
        query = "";
        ddgResults = [];
        centerOnCurrent();
    }

    function startSearch(ch) {}

    onActiveChanged: if (active) {
        searching = false;
        query = "";
        ddgResults = [];
        Walls.refresh();
        centerOnCurrent();
        hintShown = false;
        hintDwell.restart();
    }

    Connections {
        target: Walls
        function onEntriesChanged() {
            if (!root.searching && root.focusIndex >= Walls.count)
                root.focusIndex = Math.max(0, Walls.count - 1);
        }
    }

    readonly property string searchScript: Quickshell.env("HOME") + "/.config/hypr/scripts/wallpaper-search.sh"

    Component {
        id: processComponent
        Process {
            id: procObj
            property var callback
            stdout: StdioCollector {
                onStreamFinished: {
                    if (procObj.callback) procObj.callback(this.text);
                }
            }
            onExited: function(exitCode) {
                root.loadingMore = false;
                if (root.activeSearchProcess === procObj) {
                    root.activeSearchProcess = null;
                }
            }
        }
    }

    Process {
        id: dlProc
        property string target: ""
        property string failed: ""
        property string savedPath: ""
        stdout: StdioCollector {
            onStreamFinished: dlProc.savedPath = this.text.trim()
        }
        onExited: function(exitCode) {
            if (exitCode === 0 && savedPath.length) {
                failed = "";
                Walls.refresh();
                Walls.apply(savedPath);
                root.exitSearch();
            } else {
                failed = target;
            }
            savedPath = "";
        }
    }

    Row {
        id: modeSelector
        anchors.top: parent.top
        anchors.topMargin: 8 * root.s
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 12 * root.s
        z: 35

        Rectangle {
            id: localTab
            width: 82 * root.s
            height: 22 * root.s
            radius: 11 * root.s
            color: !root.searching ? Theme.tileBg : "transparent"
            border.width: 1
            border.color: !root.searching ? Theme.border : "transparent"

            Text {
                anchors.centerIn: parent
                text: "Local"
                color: !root.searching ? Theme.cream : Theme.subtle
                font.family: Theme.font
                font.pixelSize: 10.5 * root.s
                font.weight: !root.searching ? Font.Bold : Font.Normal
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.searching = false;
                }
            }
        }

        Rectangle {
            id: onlineTab
            width: 82 * root.s
            height: 22 * root.s
            radius: 11 * root.s
            color: (root.searching && root.searchMode === "wallhaven") ? Theme.tileBg : "transparent"
            border.width: 1
            border.color: (root.searching && root.searchMode === "wallhaven") ? Theme.border : "transparent"

            Text {
                anchors.centerIn: parent
                text: "Wallhaven"
                color: (root.searching && root.searchMode === "wallhaven") ? Theme.cream : Theme.subtle
                font.family: Theme.font
                font.pixelSize: 10.5 * root.s
                font.weight: (root.searching && root.searchMode === "wallhaven") ? Font.Bold : Font.Normal
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.searchMode = "wallhaven";
                    root.searching = true;
                    root.triggerSearch();
                }
            }
        }

        Rectangle {
            id: moeTab
            width: 82 * root.s
            height: 22 * root.s
            radius: 11 * root.s
            color: (root.searching && root.searchMode === "moewalls") ? Theme.tileBg : "transparent"
            border.width: 1
            border.color: (root.searching && root.searchMode === "moewalls") ? Theme.border : "transparent"

            Text {
                anchors.centerIn: parent
                text: "MoeWalls"
                color: (root.searching && root.searchMode === "moewalls") ? Theme.cream : Theme.subtle
                font.family: Theme.font
                font.pixelSize: 10.5 * root.s
                font.weight: (root.searching && root.searchMode === "moewalls") ? Font.Bold : Font.Normal
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.searchMode = "moewalls";
                    root.moeOrder = "newest";
                    root.searching = true;
                }
            }
        }
    }

    Row {
        id: moeBarRow
        anchors.top: modeSelector.bottom
        anchors.topMargin: 8 * root.s
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 6 * root.s
        visible: root.searching && root.searchMode === "moewalls"
        opacity: visible ? 1 : 0
        z: 30
        Behavior on opacity { NumberAnimation { duration: Motion.standard } }

        Rectangle {
            id: moeSearchBox
            width: 180 * root.s
            height: 22 * root.s
            radius: 11 * root.s
            color: Theme.tileBg
            border.width: 1
            border.color: moeBarInput.activeFocus ? Theme.cream : Theme.border

            TextInput {
                id: moeBarInput
                anchors.fill: parent
                anchors.leftMargin: 12 * root.s
                anchors.rightMargin: 12 * root.s
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: 10.5 * root.s
                selectByMouse: true
                clip: true

                Text {
                    text: "Search MoeWalls..."
                    color: Theme.subtle
                    font.family: Theme.font
                    font.pixelSize: 10.5 * root.s
                    visible: !parent.text && !parent.activeFocus
                    anchors.verticalCenter: parent.verticalCenter
                }

                onTextChanged: {
                    root.query = text;
                    root.currentPage = 1;
                    root.loadingMore = false;
                    if (text.trim().length === 0) {
                        root.ddgResults = [];
                    }
                }

                onAccepted: root.triggerSearch()

                Connections {
                    target: root
                    function onSearchingChanged() {
                        if (root.searching) {
                            moeBarInput.text = root.query;
                            moeBarInput.forceActiveFocus();
                        } else {
                            moeBarInput.text = "";
                        }
                    }
                    function onSearchModeChanged() {
                        if (root.searching) {
                            moeBarInput.text = root.query;
                            moeBarInput.forceActiveFocus();
                        } else {
                            moeBarInput.text = "";
                        }
                    }
                }
            }
        }

        Rectangle {
            id: moeSearchBtn
            width: 50 * root.s
            height: 22 * root.s
            radius: 11 * root.s
            color: moeBtnMouse.containsMouse ? Theme.tileBg : Theme.frameBg
            border.width: 1
            border.color: Theme.border

            Text {
                anchors.centerIn: parent
                text: "Search"
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: 9.5 * root.s
                font.weight: Font.Medium
            }
            MouseArea {
                id: moeBtnMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.triggerSearch()
            }
        }

        Rectangle {
            id: moeOrderChip
            width: moeOrderText.implicitWidth + 16 * root.s
            height: 22 * root.s
            radius: 11 * root.s
            color: moeOrderMouse.containsMouse ? Theme.frameBg : "transparent"
            border.width: 1
            border.color: Theme.border

            Text {
                id: moeOrderText
                anchors.centerIn: parent
                text: root.moeOrderLabel(root.moeOrder)
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: 9.5 * root.s
                font.weight: Font.Medium
            }
            MouseArea {
                id: moeOrderMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.cycleMoeOrder()
            }
        }
    }

    // Progress bar for search loading
    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        height: 2 * root.s
        color: Theme.cream
        visible: root.loadingMore

        SequentialAnimation on width {
            running: root.loadingMore
            loops: Animation.Infinite
            NumberAnimation { to: parent.width * 0.7; duration: 1000 }
            NumberAnimation { to: parent.width * 0.3; duration: 1000 }
        }
    }

    Row {
        id: filterRow
        anchors.top: modeSelector.bottom
        anchors.topMargin: 8 * root.s
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 8 * root.s
        visible: root.searching && root.searchMode === "wallhaven"
        opacity: (root.searching && root.searchMode === "wallhaven") ? 1 : 0
        z: 30
        Behavior on opacity { NumberAnimation { duration: Motion.standard } }

        Rectangle {
            id: sortChip
            width: sortText.implicitWidth + 16 * root.s
            height: 20 * root.s
            radius: 10 * root.s
            color: sortMouse.containsMouse ? Theme.frameBg : "transparent"
            border.width: 1
            border.color: Theme.border

            Text {
                id: sortText
                anchors.centerIn: parent
                text: "Sort: " + root.filterSortLabel(root.filterSort)
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: 9.5 * root.s
                font.weight: Font.Medium
            }
            MouseArea {
                id: sortMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.cycleSort()
            }
        }

        Rectangle {
            id: rangeChip
            visible: root.filterSort === "toplist"
            width: rangeText.implicitWidth + 16 * root.s
            height: 20 * root.s
            radius: 10 * root.s
            color: rangeMouse.containsMouse ? Theme.frameBg : "transparent"
            border.width: 1
            border.color: Theme.border

            Text {
                id: rangeText
                anchors.centerIn: parent
                text: "Range: " + root.filterRangeLabel(root.filterRange)
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: 9.5 * root.s
                font.weight: Font.Medium
            }
            MouseArea {
                id: rangeMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.cycleRange()
            }
        }

        Rectangle {
            id: purityChip
            width: purityText.implicitWidth + 16 * root.s
            height: 20 * root.s
            radius: 10 * root.s
            color: purityMouse.containsMouse ? Theme.frameBg : "transparent"
            border.width: 1
            border.color: Theme.border

            Text {
                id: purityText
                anchors.centerIn: parent
                text: "Purity: " + (root.filterPurity === "100" ? "SFW" : (root.filterPurity === "010" ? "Sketchy" : "All"))
                color: root.filterPurity === "100" ? Theme.cream : (root.filterPurity === "010" ? Theme.subtle : Theme.vermLit)
                font.family: Theme.font
                font.pixelSize: 9.5 * root.s
                font.weight: Font.Bold
            }
            MouseArea {
                id: purityMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.cyclePurity()
            }
        }

        Rectangle {
            id: categoriesChip
            width: categoriesText.implicitWidth + 16 * root.s
            height: 20 * root.s
            radius: 10 * root.s
            color: categoriesMouse.containsMouse ? Theme.frameBg : "transparent"
            border.width: 1
            border.color: Theme.border

            Text {
                id: categoriesText
                anchors.centerIn: parent
                text: "Cat: " + root.filterCategoriesLabel(root.filterCategories)
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: 9.5 * root.s
                font.weight: Font.Medium
            }
            MouseArea {
                id: categoriesMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.cycleCategories()
            }
        }

        Rectangle {
            id: ratioChip
            width: ratioText.implicitWidth + 16 * root.s
            height: 20 * root.s
            radius: 10 * root.s
            color: ratioMouse.containsMouse ? Theme.frameBg : "transparent"
            border.width: 1
            border.color: Theme.border

            Text {
                id: ratioText
                anchors.centerIn: parent
                text: "Ratio: " + root.filterRatioLabel(root.filterRatio)
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: 9.5 * root.s
                font.weight: Font.Medium
            }
            MouseArea {
                id: ratioMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.cycleRatio()
            }
        }
    }

    Text {
        anchors.left: parent.left
        anchors.leftMargin: 20 * root.s
        anchors.verticalCenter: parent.verticalCenter
        z: 0
        visible: Flags.showGlyphs && !root.searching
        text: "壁"
        color: Theme.ghost
        opacity: 0.55
        font.family: Theme.fontJp
        font.weight: Font.Medium
        font.pixelSize: 30 * root.s
    }

    Repeater {
        model: root.items

        delegate: Item {
            id: tile

            required property int index
            required property var modelData

            readonly property bool isLoadMore: modelData && modelData.__loadMore === true

            // Load-more sentinel: render a "+" button
            visible: isLoadMore ? ao <= 5 : true
            width: isLoadMore ? (60 * root.s) : root.slotLerp(root.slotW, ao) * root.s
            height: isLoadMore ? (60 * root.s) : root.slotLerp(root.slotH, ao) * root.s
            x: root.width / 2 + root.offsetX(off) - width / 2
            y: ((root.height - height) / 2) + (root.searching ? 32 * root.s : 0)
            z: 10 - ao
            opacity: isLoadMore ? (edgeFade * (ao <= 4 ? 1 : Math.max(0, 5 - ao))) : (edgeFade * (ao <= 4 ? 1 : Math.max(0, 5 - ao)))

            readonly property real off: index - root.pos
            readonly property real ao: Math.abs(off)
            readonly property bool focused: index === root.focusIndex
            readonly property real bright: root.slotLerp(root.slotBright, ao)
            readonly property real sat: root.slotLerp(root.slotSat, ao)
            readonly property real corner: isLoadMore ? (30 * root.s) : (8 + 2 * Math.max(0, 1 - ao)) * root.s

            readonly property real hold: trashHeat.hold
            readonly property bool committing: !isLoadMore && trashHeat.hold >= trashHeat.tapThreshold
            readonly property real commitProgress: !isLoadMore ? Math.max(0, (trashHeat.hold - trashHeat.tapThreshold) / (1 - trashHeat.tapThreshold)) : 0

            readonly property string thumb: modelData.thumb !== undefined ? modelData.thumb : ""
            readonly property bool remote: modelData.image !== undefined
            readonly property string thumbSource: remote ? thumb : ("file://" + thumb)
            readonly property bool isVideo: modelData.preview !== undefined
            readonly property string videoSource: isVideo ? modelData.preview : ""

            readonly property real edgeFade: {
                var soft = 70 * root.s;
                var gap = Math.min(x, root.width - (x + width));
                return Math.max(0, Math.min(1, gap / soft));
            }

            onFocusedChanged: if (!focused && !isLoadMore) trashHeat.cancel()

            // Load-more tile: circle with "+"
            ClippingRectangle {
                id: loadMoreCard
                anchors.fill: parent
                radius: tile.corner
                color: loadMoreMouse.containsMouse ? Theme.tileBg : Theme.frameBg
                border.width: 1
                border.color: Theme.border
                visible: tile.isLoadMore

                Text {
                    anchors.centerIn: parent
                    text: root.loadingMore ? "..." : "+"
                    color: loadMoreMouse.containsMouse ? Theme.ghost : Theme.cream
                    font.family: Theme.font
                    font.pixelSize: 22 * root.s
                    font.weight: Font.Light

                    SequentialAnimation on opacity {
                        running: root.loadingMore
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.3; duration: 600 }
                        NumberAnimation { to: 1.0; duration: 600 }
                    }
                }
                MouseArea {
                    id: loadMoreMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: root.loadingMore ? Qt.WaitCursor : Qt.PointingHandCursor
                    enabled: !root.loadingMore
                    onClicked: root.loadMore()
                }
            }

            // Normal wallpaper tile
            ClippingRectangle {
                id: card
                anchors.fill: parent
                radius: tile.corner
                color: Theme.tileBg
                visible: !tile.isLoadMore

                layer.enabled: tile.ao <= 1.5
                layer.effect: MultiEffect {
                    saturation: tile.sat - 1
                    shadowEnabled: tile.focused
                    shadowColor: Qt.rgba(0, 0, 0, Theme.shadowOpacity)
                    shadowBlur: 0.7
                    shadowVerticalOffset: 4 * root.s
                }

                Image {
                    id: thumbImage
                    anchors.fill: parent
                    source: tile.ao <= 6 ? tile.thumbSource : ""
                    sourceSize.width: 512
                    sourceSize.height: 220
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    smooth: true
                    cache: true
                }

                Video {
                    id: videoThumb
                    anchors.fill: parent
                    source: tile.isVideo && tile.focused ? tile.videoSource : ""
                    visible: tile.isVideo && tile.focused
                    fillMode: Video.PreserveAspectCrop
                    muted: true
                    loops: MediaPlayer.Infinite
                    autoPlay: tile.focused
                }

                Rectangle {
                    anchors.fill: parent
                    color: Theme.tileBg
                    visible: thumbImage.status === Image.Error && !tile.isVideo
                }

                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(0, 0, 0, 1)
                    opacity: 1 - tile.bright
                }

                Rectangle {
                    id: consume
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: card.height * tile.commitProgress
                    visible: tile.committing
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.alpha(Theme.vermBurn, 0.66) }
                        GradientStop { position: 0.74; color: Qt.alpha(Theme.vermLit, 0.30) }
                        GradientStop { position: 1.0; color: Qt.alpha(Theme.flameGlow, 0.0) }
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        height: 2 * root.s
                        opacity: Math.min(1, tile.commitProgress * 3)
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: Qt.alpha(Theme.flameGlow, 0.0) }
                            GradientStop { position: 0.5; color: Theme.flameGlow }
                            GradientStop { position: 1.0; color: Qt.alpha(Theme.flameGlow, 0.0) }
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: tile.focused && tile.remote && dlProc.running && dlProc.target === tile.modelData.image
                    text: "saving…"
                    color: Theme.cream
                    font.family: Theme.font
                    font.pixelSize: 11 * root.s
                }

                Rectangle {
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 4 * root.s
                    width: votesText.implicitWidth + 8 * root.s
                    height: votesText.implicitHeight + 4 * root.s
                    radius: 4 * root.s
                    color: Qt.rgba(0, 0, 0, 0.7)
                    visible: tile.focused && tile.modelData.votes > 0

                    Text {
                        id: votesText
                        anchors.centerIn: parent
                        text: "★ " + tile.modelData.votes
                        color: Theme.bright
                        font.family: Theme.font
                        font.pixelSize: 8 * root.s
                    }
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottomMargin: 6 * root.s
                    visible: tile.focused && tile.remote && tile.modelData.w > 0 && !(dlProc.running && dlProc.target === tile.modelData.image)
                    width: resText.implicitWidth + 12 * root.s
                    height: resText.implicitHeight + 5 * root.s
                    radius: height / 2
                    color: Qt.rgba(0, 0, 0, 0.55)
                    Text {
                        id: resText
                        anchors.centerIn: parent
                        text: tile.modelData.w + "×" + tile.modelData.h
                        color: Theme.bright
                        font.family: Theme.font
                        font.pixelSize: 9.5 * root.s
                        font.features: { "tnum": 1 }
                    }
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: tile.corner
                color: "transparent"
                border.width: 1
                border.color: {
                    if (tile.remote && dlProc.failed.length && dlProc.failed === tile.modelData.image)
                        return Theme.vermLit;
                    return tile.committing ? Theme.vermLit : Theme.border;
                }
                Behavior on border.color { ColorAnimation { duration: Motion.fast } }
            }

            HeatHold {
                id: trashHeat
                tapThreshold: 0.25
                enabled: !tile.remote
                onConfirmed: if (!tile.remote) Walls.trash(tile.modelData.path)
                onTapped: root.activate()
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                enabled: !tile.isLoadMore
                cursorShape: tile.isLoadMore ? Qt.ArrowCursor : Qt.PointingHandCursor
                onPressed: {
                    if (!tile.focused)
                        return;
                    if (tile.remote)
                        root.activate();
                    else
                        trashHeat.press();
                }
                onReleased: if (tile.focused && !tile.remote) trashHeat.release()
                onExited: trashHeat.cancel()
                onClicked: if (!tile.focused) root.focusIndex = tile.index
            }
        }
    }

    Text {
        anchors.centerIn: parent
        visible: root.itemCount === 0 && (!root.activeSearchProcess || !root.activeSearchProcess.running)
        text: {
            if (!root.searching)
                return "No wallpapers in ~/Pictures/Wallpapers";
            if (root.searchErrorShown)
                return "search error";
            return "no results";
        }
        color: Theme.faint
        font.family: Theme.font
        font.pixelSize: 10.5 * root.s
    }

    Text {
        anchors.centerIn: parent
        visible: root.activeSearchProcess && root.activeSearchProcess.running
        text: "searching…"
        color: Theme.faint
        font.family: Theme.font
        font.pixelSize: 10.5 * root.s
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 11 * root.s
        visible: root.itemCount > 0 && !root.searching
        opacity: root.hintShown ? 1 : 0
        text: "tap to set · hold to delete"
        color: Theme.subtle
        font.family: Theme.font
        font.pixelSize: 10 * root.s
        font.weight: Font.Medium
        font.letterSpacing: 0.4 * root.s
        Behavior on opacity { NumberAnimation { duration: Motion.standard } }
    }

    MouseArea {
        id: wheelArea
        anchors.fill: parent
        z: 20
        acceptedButtons: Qt.NoButton
        property real acc: 0
        onWheel: (event) => {
            acc += event.angleDelta.y / 120;
            const notches = Math.trunc(acc);
            if (notches !== 0) {
                root.move(-notches);
                acc -= notches;
            }
            event.accepted = true;
        }
    }
}
