import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtCore
import QtLocation
import QtPositioning
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

PlasmoidItem {
    id: root

    // ── WMS Configuration ──
    readonly property string wmsBase: "https://maps.dwd.de/geoserver/ows"
    readonly property string wmsLayer: "dwd:Niederschlagsradar"
    readonly property int pastFrames: 36
    readonly property int futureFrames: 24
    readonly property int maxFrames: pastFrames + futureFrames
    readonly property int stepMinutes: 5

    // ── State ──
    property int frameIndex: 0
    property int currentBaseTime: 0
    property var loadingStates: ({})
    property bool loading: {
        if (frameTimes.length === 0) return false
        for (var i = 0; i < frameTimes.length; i++) {
            var s = loadingStates[i]
            if (s !== "Ready" && s !== "Error") {
                return true
            }
        }
        return false
    }
    property bool initialLoading: {
        if (frameTimes.length === 0) return true
        var readyCount = 0
        for (var i = 0; i < frameTimes.length; i++) {
            var s = loadingStates[i]
            if (s === "Ready" || s === "Error") {
                readyCount++
            }
        }
        // Show loading screen only if we have less than half of the frames loaded (initial fetch)
        return readyCount < 30
    }
    property var frameTimes: []        // Array of JS Date objects
    property int radarGeneration: 0    // bumped to force Image reload

    // ── GPS/Location Service ──
    PositionSource {
        id: positionSource
        updateInterval: 10000 // every 10 seconds
        active: true
    }

    // ── Fallback IP Geolocation ──
    property real ipLatitude: 0
    property real ipLongitude: 0
    property bool ipLocationValid: false

    readonly property var rawUserCoordinate: (positionSource && positionSource.position && positionSource.position.coordinate && positionSource.position.coordinate.isValid)
        ? positionSource.position.coordinate
        : (ipLocationValid ? QtPositioning.coordinate(ipLatitude, ipLongitude) : null)

    readonly property var userCoordinate: {
        var coord = rawUserCoordinate
        if (coord && coord.isValid && 
            coord.latitude >= 45.0 && coord.latitude <= 56.576107 && 
            coord.longitude >= 2.0 && coord.longitude <= 19.0) {
            return coord
        }
        return null
    }

    // ── Viewport state (set by the Map when visible) ──
    property real vpLatMin: 47.0
    property real vpLatMax: 55.5
    property real vpLonMin: 5.5
    property real vpLonMax: 15.5
    property int vpWidth: 550
    property int vpHeight: 420

    // ── Bounding box of the currently displayed WMS image ──
    property real imgLatMin: 47.0
    property real imgLatMax: 55.5
    property real imgLonMin: 5.5
    property real imgLonMax: 15.5

    Plasmoid.icon: Qt.resolvedUrl("../images/plasma-rain-radar.svg").toString()
    Plasmoid.title: "DWD Regenradar"
    compactRepresentation: compact
    fullRepresentation: full

    // ── Helpers ──

    function roundEpoch(epoch) {
        var step = stepMinutes * 60
        return Math.floor(epoch / step) * step
    }

    function buildFrameTimes(forceReload) {
        if (forceReload === undefined) {
            forceReload = true
        }
        // Subtract a safety margin of 10 minutes (600 seconds) to account for DWD server-side processing delays.
        // This prevents requesting the very latest frame before it is actually published on the server.
        var now = Math.floor(Date.now() / 1000) - 600
        var base = roundEpoch(now)
        root.currentBaseTime = base
        console.log("[RadarDebug] buildFrameTimes: forceReload =", forceReload, "base =", base, "local =", localTimeStr(new Date(base * 1000)))
        var arr = []
        for (var i = 0; i < maxFrames; i++) {
            var ts
            if (i < pastFrames) {
                ts = base - (pastFrames - i) * stepMinutes * 60
            } else {
                ts = base + (i - pastFrames) * stepMinutes * 60
            }
            arr.push(new Date(ts * 1000))
        }
        var oldIndex = frameIndex
        frameTimes = arr
        
        if (forceReload) {
            frameIndex = pastFrames // Start at the "Jetzt" frame (index 36)
            playback.running = false
            loadingStates = {}
            radarGeneration++
        } else {
            // Shift the index to keep showing the same physical time if possible
            frameIndex = Math.max(0, oldIndex - 1)
        }
    }

    function isoTime(d) {
        if (!d) return ""
        return d.toISOString().replace(/\.\d+Z$/, "Z")
    }

    function localTimeStr(d) {
        if (!d) return "–"
        var days = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"]
        var day = days[d.getDay()]
        var dd = ("0" + d.getDate()).slice(-2)
        var mm = ("0" + (d.getMonth() + 1)).slice(-2)
        var hh = ("0" + d.getHours()).slice(-2)
        var min = ("0" + d.getMinutes()).slice(-2)
        return day + ", " + dd + "." + mm + ". " + hh + ":" + min
    }


    function legendUrl() {
        return wmsBase
            + "?SERVICE=WMS&VERSION=1.3.0&REQUEST=GetLegendGraphic"
            + "&FORMAT=image/png&WIDTH=20&HEIGHT=20"
            + "&LAYER=" + wmsLayer
    }

    function fetchIpLocation() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "https://freeipapi.com/api/json")
        xhr.onreadystatechange = function() {
            if (xhr.readyState === 4) {
                if (xhr.status === 200) {
                    try {
                        var res = JSON.parse(xhr.responseText)
                        var lat = res.latitude
                        var lon = res.longitude
                        if (typeof lat === "number" && typeof lon === "number") {
                            root.ipLatitude = lat
                            root.ipLongitude = lon
                            root.ipLocationValid = true
                            return
                        }
                    } catch (e) {
                        console.log("Error parsing freeipapi:", e)
                    }
                }
                
                // Fallback to ipapi.co if freeipapi fails or returns invalid coordinates
                fetchIpLocationFallback()
            }
        }
        xhr.send()
    }

    function fetchIpLocationFallback() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "https://ipapi.co/json/")
        xhr.onreadystatechange = function() {
            if (xhr.readyState === 4) {
                if (xhr.status === 200) {
                    try {
                        var res = JSON.parse(xhr.responseText)
                        var lat = res.latitude
                        var lon = res.longitude
                        if (typeof lat === "number" && typeof lon === "number") {
                            root.ipLatitude = lat
                            root.ipLongitude = lon
                            root.ipLocationValid = true
                        }
                    } catch (e) {
                        console.log("Error parsing ipapi.co:", e)
                    }
                }
            }
        }
        xhr.send()
    }

    Component.onCompleted: {
        buildFrameTimes()
        fetchIpLocation()
    }

    onExpandedChanged: {
        if (root.expanded) {
            buildFrameTimes(false) // Smoothly update time window when expanded using cache
            // Reset map to full radar frame view when opening
            if (radarMap) {
                radarMap.zoomLevel = radarMap.minimumZoomLevel
                radarMap.center = QtPositioning.coordinate(51.1657, 10.4515)
            }
        } else {
            playback.running = false
        }
    }

    Timer {
        id: autoRefresh
        interval: 30 * 1000 // Check every 30 seconds
        running: true
        repeat: true
        onTriggered: {
            var now = Math.floor(Date.now() / 1000) - 600
            var newBase = roundEpoch(now)
            if (newBase !== root.currentBaseTime) {
                buildFrameTimes(false)
            }
        }
    }

    Timer {
        id: playback
        interval: 700
        running: false
        repeat: true
        onTriggered: {
            if (frameTimes.length > 0) {
                frameIndex = (frameIndex + 1) % frameTimes.length
            }
        }
    }

    // ── Compact representation ──
    Component {
        id: compact

        Kirigami.Icon {
            source: Qt.resolvedUrl("../images/plasma-rain-radar.svg")
            opacity: compactMouse.containsMouse ? 1.0 : 0.9

            MouseArea {
                id: compactMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.expanded = !root.expanded
            }
        }
    }

    // ── Full representation ──
    Component {
        id: full

        Item {
            id: fullRoot
            Layout.minimumWidth: 550
            Layout.minimumHeight: 480
            Layout.preferredWidth: 600
            Layout.preferredHeight: 520

            property int displayIndex: root.frameIndex

            function updateDisplayIndex() {
                var target = root.frameIndex
                if (isImageReady(target)) {
                    displayIndex = target
                    return
                }
                // Search backwards for the nearest ready frame
                for (var i = target - 1; i >= 0; i--) {
                    if (isImageReady(i)) {
                        displayIndex = i
                        return
                    }
                }
                // If none found backwards, search forwards
                for (var j = target + 1; j < root.frameTimes.length; j++) {
                    if (isImageReady(j)) {
                        displayIndex = j
                        return
                    }
                }
                displayIndex = target
            }

            function isImageReady(idx) {
                if (!imgRepeater) return false
                var item = imgRepeater.itemAt(idx)
                return item && item.status === Image.Ready
            }

            Connections {
                target: root
                function onFrameIndexChanged() {
                    fullRoot.updateDisplayIndex()
                }
                function onFrameTimesChanged() {
                    fullRoot.updateDisplayIndex()
                }
            }

            // Sync viewport from map to root properties
            function syncViewport() {
                if (!radarMap || radarMap.width < 10 || radarMap.height < 10) return

                var tl = radarMap.toCoordinate(Qt.point(0, 0))
                var br = radarMap.toCoordinate(Qt.point(radarMap.width, radarMap.height))

                if (!tl.isValid || !br.isValid) return

                root.vpLatMin = Math.min(tl.latitude, br.latitude)
                root.vpLatMax = Math.max(tl.latitude, br.latitude)
                root.vpLonMin = Math.min(tl.longitude, br.longitude)
                root.vpLonMax = Math.max(tl.longitude, br.longitude)
                root.vpWidth = Math.round(radarMap.width)
                root.vpHeight = Math.round(radarMap.height)
            }

            // Clamp map center so the visible viewport stays within radar BBOX
            // Radar coverage: lat 45.0–56.576107, lon 2.0–19.0
            function clampCenter() {
                if (!radarMap || radarMap.width < 10 || radarMap.height < 10) return

                var tl = radarMap.toCoordinate(Qt.point(0, 0))
                var br = radarMap.toCoordinate(Qt.point(radarMap.width, radarMap.height))
                if (!tl.isValid || !br.isValid) return

                var visLatN = Math.max(tl.latitude, br.latitude)
                var visLatS = Math.min(tl.latitude, br.latitude)
                var visLonW = Math.min(tl.longitude, br.longitude)
                var visLonE = Math.max(tl.longitude, br.longitude)

                var c = radarMap.center
                var lat = c.latitude
                var lon = c.longitude

                // Clamp: if viewport edge exceeds radar boundary, pull center back
                if (visLatN > 56.576107) lat -= (visLatN - 56.576107)
                if (visLatS < 45.0)      lat += (45.0 - visLatS)
                if (visLonE > 19.0)      lon -= (visLonE - 19.0)
                if (visLonW < 2.0)       lon += (2.0 - visLonW)

                if (lat !== c.latitude || lon !== c.longitude) {
                    radarMap.center = QtPositioning.coordinate(lat, lon)
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 6

                // ── Header ──
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Label {
                        text: "DWD Regenradar"
                        font.bold: true
                        font.pixelSize: 15
                    }

                    Item { Layout.fillWidth: true }

                    Button {
                        text: "📍 Jetzt"
                        flat: true
                        onClicked: {
                            root.frameIndex = root.pastFrames
                        }
                        ToolTip.visible: hovered
                        ToolTip.text: "Zur Gegenwart springen"
                    }

                    Button {
                        icon.name: "view-refresh"
                        flat: true
                        onClicked: root.buildFrameTimes(true) // Force full reload
                        ToolTip.visible: hovered
                        ToolTip.text: "Daten aktualisieren"
                    }
                }

                // ── Map area ──
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: "#101620"
                    radius: 8
                    border.color: "#2b3b52"
                    border.width: 1
                    clip: true

                    Map {
                        id: radarMap
                        anchors.fill: parent
                        anchors.margins: 1

                        plugin: Plugin {
                            name: "osm"
                            PluginParameter {
                                name: "osm.mapping.providersrepository.disabled"
                                value: true
                            }
                        }

                        center: QtPositioning.coordinate(51.1657, 10.4515)
                        zoomLevel: 6
                        // Dynamically compute minimum zoom so the radar frame always
                        // covers the entire visible map area (no zooming beyond radar BBOX)
                        minimumZoomLevel: {
                            var w = radarMap.width
                            var h = radarMap.height
                            if (w < 10 || h < 10) return 6

                            // Radar coverage: lon 2.0–19.0, lat 45.0–56.576107
                            var lonSpan = 17.0 // 19.0 - 2.0

                            // Mercator Y fractions for lat bounds
                            var latNRad = 56.576107 * Math.PI / 180
                            var latSRad = 45.0 * Math.PI / 180
                            var yN = (1 - Math.log(Math.tan(latNRad) + 1 / Math.cos(latNRad)) / Math.PI) / 2
                            var yS = (1 - Math.log(Math.tan(latSRad) + 1 / Math.cos(latSRad)) / Math.PI) / 2
                            var latFracSpan = Math.abs(yS - yN)

                            // Zoom where radar fills width: w = lonSpan/360 * 256 * 2^z
                            var zW = Math.log(w * 360 / (lonSpan * 256)) / Math.LN2
                            // Zoom where radar fills height: h = latFracSpan * 256 * 2^z
                            var zH = Math.log(h / (latFracSpan * 256)) / Math.LN2

                            // Take the larger (more zoomed in) to ensure both dimensions are covered
                            return Math.ceil(Math.max(zW, zH) * 10) / 10
                        }
                        maximumZoomLevel: 12

                        Component.onCompleted: {
                            radarMap.zoomLevel = radarMap.minimumZoomLevel
                            radarMap.center = QtPositioning.coordinate(51.1657, 10.4515)
                            // Initial viewport sync after map is rendered
                            Qt.callLater(syncViewport)
                        }

                        // Drag/Pan interaction
                        MouseArea {
                            id: mapDragArea
                            anchors.fill: parent
                            property int lastX: 0
                            property int lastY: 0

                            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor

                            onPressed: function(mouse) {
                                lastX = mouse.x
                                lastY = mouse.y
                            }

                            onPositionChanged: function(mouse) {
                                if (pressed) {
                                    var dx = mouse.x - lastX
                                    var dy = mouse.y - lastY
                                    radarMap.pan(-dx, -dy)
                                    clampCenter()
                                    lastX = mouse.x
                                    lastY = mouse.y
                                }
                            }

                            onDoubleClicked: function(mouse) {
                                var coord = radarMap.toCoordinate(Qt.point(mouse.x, mouse.y))
                                if (coord.isValid) {
                                    radarMap.center = coord
                                    radarMap.zoomLevel = Math.min(radarMap.maximumZoomLevel, radarMap.zoomLevel + 1)
                                    clampCenter()
                                }
                            }

                            onWheel: function(wheel) {
                                var delta = wheel.angleDelta.y / 120
                                radarMap.zoomLevel = Math.max(
                                    radarMap.minimumZoomLevel,
                                    Math.min(radarMap.maximumZoomLevel,
                                             radarMap.zoomLevel + delta * 0.5))
                                clampCenter()
                                wheel.accepted = true
                            }
                        }

                        // User Location Marker
                        MapQuickItem {
                            id: userLocationMarker
                            coordinate: root.userCoordinate !== null ? root.userCoordinate : QtPositioning.coordinate(0, 0)
                            visible: root.userCoordinate !== null && root.userCoordinate.isValid
                            
                            sourceItem: Rectangle {
                                width: 14
                                height: 14
                                color: "#3b82f6" // Vibrant blue
                                radius: 7
                                border.color: "white"
                                border.width: 2
                                
                                SequentialAnimation on scale {
                                    loops: Animation.Infinite
                                    PropertyAnimation { to: 1.4; duration: 1200; easing.type: Easing.InOutQuad }
                                    PropertyAnimation { to: 1.0; duration: 1200; easing.type: Easing.InOutQuad }
                                }
                            }
                            
                            anchorPoint: Qt.point(7, 7)
                        }

                        // Natively lock the WMS image geographically to the map (perfect Web Mercator alignment)
                        // The WMS BBOX in EPSG:3857 corresponds to these exact lat/lon corners:
                        // NW corner: lat 56.576107, lon 2.0   SE corner: lat 45.0, lon 19.0
                        MapQuickItem {
                            id: radarOverlayItem
                            // Pin to NW corner of the radar coverage area
                            coordinate: QtPositioning.coordinate(56.576107, 2.0)
                            anchorPoint: Qt.point(0, 0)
                            // Bind to current map zoom so internal scaling is 1:1
                            // (our fromCoordinate() already computes correct pixel sizes)
                            zoomLevel: radarMap.zoomLevel
                            z: 10

                            sourceItem: Item {
                                // Compute overlay size dynamically from the map's pixel projection
                                // so it always aligns perfectly regardless of window size or zoom level
                                // We reference radarMap properties to create reactive QML dependencies
                                width: {
                                    // Reactive dependencies: re-evaluate when these change
                                    void(radarMap.zoomLevel); void(radarMap.width); void(radarMap.height)
                                    void(radarMap.center)
                                    var nw = radarMap.fromCoordinate(QtPositioning.coordinate(56.576107, 2.0), false)
                                    var se = radarMap.fromCoordinate(QtPositioning.coordinate(45.0, 19.0), false)
                                    return Math.max(1, se.x - nw.x)
                                }
                                height: {
                                    // Reactive dependencies: re-evaluate when these change
                                    void(radarMap.zoomLevel); void(radarMap.width); void(radarMap.height)
                                    void(radarMap.center)
                                    var nw = radarMap.fromCoordinate(QtPositioning.coordinate(56.576107, 2.0), false)
                                    var se = radarMap.fromCoordinate(QtPositioning.coordinate(45.0, 19.0), false)
                                    return Math.max(1, se.y - nw.y)
                                }

                                Repeater {
                                    id: imgRepeater
                                    model: root.frameTimes.length

                                    Image {
                                        id: overlayImg
                                        anchors.fill: parent
                                        fillMode: Image.Stretch
                                        opacity: index === fullRoot.displayIndex ? 0.75 : 0.001
                                        cache: true
                                        asynchronous: true
                                        source: {
                                            if (root.frameTimes.length === 0) return ""
                                            var t = root.frameTimes[index]
                                            if (!t) return ""

                                            return root.wmsBase
                                                + "?SERVICE=WMS&VERSION=1.3.0&REQUEST=GetMap"
                                                + "&LAYERS=" + root.wmsLayer
                                                + "&STYLES=&CRS=EPSG:3857"
                                                + "&BBOX=222638.98,5621521.49,2115070.32,7673967.65"
                                                + "&WIDTH=800&HEIGHT=868"
                                                + "&FORMAT=image/png&TRANSPARENT=TRUE"
                                                + "&TIME=" + root.isoTime(t)
                                                + "&_g=" + root.radarGeneration
                                        }

                                        onStatusChanged: {
                                            var states = Object.assign({}, root.loadingStates)
                                            if (status === Image.Ready) {
                                                states[index] = "Ready"
                                            } else if (status === Image.Error) {
                                                states[index] = "Error"
                                            } else {
                                                states[index] = "Loading"
                                            }
                                            root.loadingStates = states
                                            fullRoot.updateDisplayIndex()
                                        }
                                    }
                                }
                            }
                        }
                    }


                    // ── Time display (top-left) ──
                    Rectangle {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.margins: 12
                        color: "#cc1a1a2e"
                        radius: 6
                        width: timeLabel.implicitWidth + 16
                        height: timeLabel.implicitHeight + 10
                        z: 20

                        Label {
                            id: timeLabel
                            anchors.centerIn: parent
                            text: root.frameTimes.length > 0
                                  ? root.localTimeStr(root.frameTimes[root.frameIndex])
                                  : "–"
                            color: "#e8eaed"
                            font.pixelSize: 13
                            font.bold: true
                        }
                    }

                    // ── Mode badge (top-right) ──
                    Rectangle {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 12
                        color: root.frameIndex >= root.pastFrames ? "#cc3b82f6" : "#cc22c55e"
                        radius: 6
                        width: modeBadge.implicitWidth + 14
                        height: modeBadge.implicitHeight + 8
                        z: 20

                        Label {
                            id: modeBadge
                            anchors.centerIn: parent
                            text: root.frameIndex >= root.pastFrames ? "Vorhersage" : "Verlauf"
                            color: "white"
                            font.pixelSize: 11
                            font.bold: true
                        }
                    }

                    // ── Legend (bottom-right) ──
                    Rectangle {
                        id: legendContainer
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right
                        anchors.margins: Math.round(10 * legendScale)
                        color: "#cc1a1a2e"
                        radius: Math.round(6 * legendScale)
                        width: legendCol.implicitWidth + Math.round(12 * legendScale)
                        height: legendCol.implicitHeight + Math.round(12 * legendScale)
                        z: 20

                        readonly property real legendScale: Math.max(2.0, Math.min(3.5, (parent.height / 520.0) * 2.0))

                        Column {
                            id: legendCol
                            anchors.centerIn: parent
                            spacing: Math.round(4 * legendContainer.legendScale)

                            Label {
                                text: "mm/h"
                                color: "#b0b8c4"
                                font.pixelSize: Math.round(10 * legendContainer.legendScale)
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                                anchors.horizontalCenter: parent.horizontalCenter
                            }

                            Image {
                                source: root.legendUrl()
                                width: Math.round(28 * legendContainer.legendScale)
                                fillMode: Image.PreserveAspectFit
                                cache: true
                                asynchronous: true
                            }
                        }
                    }

                    // ── Zoom controls (bottom-left) ──
                    Column {
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.margins: 10
                        spacing: 4
                        z: 20

                        Button {
                            width: 32; height: 32
                            text: "+"
                            font.pixelSize: 16
                            font.bold: true
                            onClicked: {
                                radarMap.zoomLevel = Math.min(
                                    radarMap.maximumZoomLevel, radarMap.zoomLevel + 1)
                                clampCenter()
                            }
                        }

                        Button {
                            width: 32; height: 32
                            text: "−"
                            font.pixelSize: 16
                            font.bold: true
                            onClicked: {
                                radarMap.zoomLevel = Math.max(
                                    radarMap.minimumZoomLevel, radarMap.zoomLevel - 1)
                                clampCenter()
                            }
                        }

                        Button {
                            width: 32; height: 32
                            icon.name: "mark-location"
                            property bool hasLocation: root.userCoordinate !== null && root.userCoordinate.isValid
                            opacity: hasLocation ? 1.0 : 0.5
                            ToolTip.visible: hovered
                            ToolTip.text: hasLocation 
                                ? "Zum eigenen Standort springen" 
                                : "Suche eigenen Standort..."
                            onClicked: {
                                if (hasLocation) {
                                    radarMap.center = root.userCoordinate
                                    radarMap.zoomLevel = 9
                                    clampCenter()
                                }
                            }
                        }
                    }

                    // ── Loading overlay (grayed-out background + large loading indicator) ──
                    Rectangle {
                        anchors.fill: parent
                        color: "#cc0c101a" // Beautiful semi-transparent dark blue/gray
                        opacity: (root.initialLoading && !playback.running) ? 1.0 : 0.0
                        visible: opacity > 0.0
                        z: 30

                        Behavior on opacity {
                            NumberAnimation { duration: 250; easing.type: Easing.InOutQuad }
                        }

                        MouseArea {
                            anchors.fill: parent
                            preventStealing: true
                            onPressed: function(mouse) {}
                            onClicked: function(mouse) {}
                        }

                        Column {
                            anchors.centerIn: parent
                            spacing: 14

                            BusyIndicator {
                                implicitWidth: 64
                                implicitHeight: 64
                                running: parent.parent.visible
                                anchors.horizontalCenter: parent.horizontalCenter
                            }

                            Label {
                                text: "Wetterdaten werden geladen..."
                                color: "#e8eaed"
                                font.bold: true
                                font.pixelSize: 14
                                anchors.horizontalCenter: parent.horizontalCenter
                            }

                            Label {
                                text: {
                                    var readyCount = 0
                                    for (var i = 0; i < root.frameTimes.length; i++) {
                                        var s = root.loadingStates[i]
                                        if (s === "Ready" || s === "Error") {
                                            readyCount++
                                        }
                                    }
                                    return readyCount + " von " + root.frameTimes.length + " Bildern geladen"
                                }
                                color: "#b0b8c4"
                                font.pixelSize: 11
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                        }
                    }
                }

                // ── Playback controls ──
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Button {
                        text: playback.running ? "⏸" : "▶"
                        font.pixelSize: 16
                        implicitWidth: 40
                        enabled: root.frameTimes.length > 0
                        onClicked: playback.running = !playback.running
                        ToolTip.visible: hovered
                        ToolTip.text: playback.running ? "Pause" : "Abspielen"
                    }

                    Slider {
                        id: frameSlider
                        Layout.fillWidth: true
                        from: 0
                        to: Math.max(0, root.frameTimes.length - 1)
                        stepSize: 1
                        enabled: root.frameTimes.length > 0
                        value: root.frameIndex
                        onMoved: root.frameIndex = Math.round(value)

                        background: Rectangle {
                            x: frameSlider.leftPadding
                            y: frameSlider.topPadding + frameSlider.availableHeight / 2 - height / 2
                            implicitWidth: 200
                            implicitHeight: 6
                            width: frameSlider.availableWidth
                            height: implicitHeight
                            radius: 3
                            color: "transparent"

                            // Ratio of the "Jetzt" position (index 36)
                            readonly property real nowRatio: root.pastFrames / Math.max(1, root.maxFrames - 1)
                            
                            // Ratio of the current handle position
                            readonly property real handleRatio: frameSlider.visualPosition

                            // ── PAST TRACK (Verlauf, Left Half) ──
                            // Muted past background (Dark Green)
                            Rectangle {
                                width: parent.width * parent.nowRatio
                                height: parent.height
                                color: "#14532d" // Dark green
                                radius: 3
                            }

                            // Active past progress (Vibrant Green)
                            Rectangle {
                                width: parent.width * Math.min(parent.nowRatio, parent.handleRatio)
                                height: parent.height
                                color: "#22c55e" // Vibrant green
                                radius: 3
                            }

                            // ── FUTURE TRACK (Vorhersage, Right Half) ──
                            // Muted future background (Dark Blue)
                            Rectangle {
                                x: parent.width * parent.nowRatio
                                width: parent.width * (1 - parent.nowRatio)
                                height: parent.height
                                color: "#172554" // Dark blue
                                radius: 3
                            }

                            // Active future progress (Vibrant Blue)
                            Rectangle {
                                x: parent.width * parent.nowRatio
                                width: parent.width * Math.max(0, parent.handleRatio - parent.nowRatio)
                                height: parent.height
                                color: "#3b82f6" // Vibrant blue
                                radius: 3
                            }

                            // "Jetzt" marker (thick vertical line at the present time)
                            Rectangle {
                                x: parent.width * parent.nowRatio - width / 2
                                y: -4 // Slightly taller
                                width: 4
                                height: parent.height + 8
                                color: "#ffffff" // White marker
                                radius: 2
                                border.color: "#1e293b"
                                border.width: 1

                                ToolTip.visible: markerMouse.containsMouse
                                ToolTip.text: "Gegenwart (" + (root.frameTimes.length > root.pastFrames ? root.localTimeStr(root.frameTimes[root.pastFrames]) : "") + ")"

                                MouseArea {
                                    id: markerMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: root.frameIndex = root.pastFrames
                                }
                            }
                        }

                        handle: Rectangle {
                            x: frameSlider.leftPadding + frameSlider.visualPosition * (frameSlider.availableWidth - width)
                            y: frameSlider.topPadding + frameSlider.availableHeight / 2 - height / 2
                            implicitWidth: 16
                            implicitHeight: 16
                            radius: 8
                            color: frameSlider.pressed ? "#e2e8f0" : "#ffffff"
                            border.color: "#1e293b"
                            border.width: 2

                            // Center indicator dot matching the current time context (green = past, blue = future)
                            Rectangle {
                                anchors.centerIn: parent
                                width: 6
                                height: 6
                                radius: 3
                                color: frameSlider.value >= root.pastFrames ? "#3b82f6" : "#22c55e"
                            }
                        }
                    }

                    Label {
                        text: root.frameTimes.length > 0
                              ? root.localTimeStr(root.frameTimes[root.frameIndex])
                              : "–"
                        font.pixelSize: 12
                        opacity: 0.85
                        Layout.minimumWidth: 120
                        horizontalAlignment: Text.AlignRight
                    }
                }

                // ── Attribution ──
                Label {
                    Layout.fillWidth: true
                    text: "© OpenStreetMap | DWD Niederschlagsradar (CC BY 4.0)"
                    font.pixelSize: 10
                    opacity: 0.5
                    horizontalAlignment: Text.AlignRight
                }
            }
        }
    }
}
