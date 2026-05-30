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
    readonly property int maxFrames: 24
    readonly property int stepMinutes: 5

    // ── State ──
    property int frameIndex: 0
    property bool loading: false
    property bool showForecast: false  // false = past, true = future
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

    readonly property var userCoordinate: (positionSource && positionSource.position && positionSource.position.coordinate && positionSource.position.coordinate.isValid)
        ? positionSource.position.coordinate
        : (ipLocationValid ? QtPositioning.coordinate(ipLatitude, ipLongitude) : null)

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

    Plasmoid.icon: "weather-showers-scattered"
    Plasmoid.title: "DWD Regenradar"
    compactRepresentation: compact
    fullRepresentation: full

    // ── Helpers ──

    function roundEpoch(epoch) {
        var step = stepMinutes * 60
        return Math.floor(epoch / step) * step
    }

    function buildFrameTimes() {
        var now = Math.floor(Date.now() / 1000)
        var base = roundEpoch(now)
        var arr = []
        for (var i = 0; i < maxFrames; i++) {
            var ts
            if (showForecast) {
                ts = base + i * stepMinutes * 60
            } else {
                ts = base - (maxFrames - 1 - i) * stepMinutes * 60
            }
            arr.push(new Date(ts * 1000))
        }
        frameTimes = arr
        frameIndex = showForecast ? 0 : maxFrames - 1
        radarGeneration++
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

    // Build WMS GetMap URL for the fixed Germany bounding box (Web Mercator EPSG:3857)
    function radarUrl() {
        if (frameTimes.length === 0) return ""
        var t = frameTimes[frameIndex]
        if (!t) return ""

        var url = wmsBase
            + "?SERVICE=WMS&VERSION=1.3.0&REQUEST=GetMap"
            + "&LAYERS=" + wmsLayer
            + "&STYLES=&CRS=EPSG:3857"
            + "&BBOX=222638.98,5621521.49,2115070.32,7673967.65"
            + "&WIDTH=800&HEIGHT=868"
            + "&FORMAT=image/png&TRANSPARENT=TRUE"
            + "&TIME=" + isoTime(t)
            + "&_g=" + radarGeneration

        return url
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
        if (!expanded) {
            playback.running = false
        }
    }

    Timer {
        id: autoRefresh
        interval: 5 * 60 * 1000
        running: true
        repeat: true
        onTriggered: buildFrameTimes()
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
            source: "weather-showers-scattered"
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
            Layout.minimumWidth: 550
            Layout.minimumHeight: 480
            Layout.preferredWidth: 600
            Layout.preferredHeight: 520

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

                root.radarGeneration++
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
                        text: root.showForecast ? "🔮 Vorhersage" : "⏪ Verlauf"
                        flat: true
                        onClicked: {
                            root.showForecast = !root.showForecast
                            root.buildFrameTimes()
                        }
                        ToolTip.visible: hovered
                        ToolTip.text: root.showForecast
                            ? "Zeigt Niederschlagsvorhersage"
                            : "Zeigt vergangene Daten"
                    }

                    Button {
                        text: "⟳"
                        flat: true
                        onClicked: root.buildFrameTimes()
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
                        minimumZoomLevel: 5
                        maximumZoomLevel: 12

                        Component.onCompleted: {
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
                                    lastX = mouse.x
                                    lastY = mouse.y
                                }
                            }

                            onDoubleClicked: function(mouse) {
                                var coord = radarMap.toCoordinate(Qt.point(mouse.x, mouse.y))
                                if (coord.isValid) {
                                    radarMap.center = coord
                                    radarMap.zoomLevel = Math.min(radarMap.maximumZoomLevel, radarMap.zoomLevel + 1)
                                }
                            }

                            onWheel: function(wheel) {
                                var delta = wheel.angleDelta.y / 120
                                radarMap.zoomLevel = Math.max(
                                    radarMap.minimumZoomLevel,
                                    Math.min(radarMap.maximumZoomLevel,
                                             radarMap.zoomLevel + delta * 0.5))
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
                        MapQuickItem {
                            id: radarOverlayItem
                            coordinate: QtPositioning.coordinate(51.18, 10.5)
                            zoomLevel: 6
                            anchorPoint: Qt.point(387, 420)
                            z: 10

                            sourceItem: Image {
                                id: radarOverlay
                                width: 774
                                height: 840
                                fillMode: Image.Stretch
                                opacity: 0.75
                                source: root.radarUrl()
                                cache: true
                                asynchronous: true

                                onStatusChanged: {
                                    root.loading = (status === Image.Loading)
                                }
                            }
                        }
                    }

                    // ── Frame Preloader (loads all frames in the background for instant sliding/play) ──
                    Repeater {
                        model: root.frameTimes.length

                        Image {
                            width: 1; height: 1
                            visible: false
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
                        color: root.showForecast ? "#cc3b82f6" : "#cc22c55e"
                        radius: 6
                        width: modeBadge.implicitWidth + 14
                        height: modeBadge.implicitHeight + 8
                        z: 20

                        Label {
                            id: modeBadge
                            anchors.centerIn: parent
                            text: root.showForecast ? "Vorhersage" : "Verlauf"
                            color: "white"
                            font.pixelSize: 11
                            font.bold: true
                        }
                    }

                    // ── Legend (bottom-right) ──
                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right
                        anchors.margins: 10
                        color: "#cc1a1a2e"
                        radius: 6
                        width: legendCol.implicitWidth + 12
                        height: legendCol.implicitHeight + 12
                        z: 20

                        Column {
                            id: legendCol
                            anchors.centerIn: parent
                            spacing: 4

                            Label {
                                text: "mm/h"
                                color: "#b0b8c4"
                                font.pixelSize: 10
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                                anchors.horizontalCenter: parent.horizontalCenter
                            }

                            Image {
                                source: root.legendUrl()
                                width: 28
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
                            onClicked: radarMap.zoomLevel = Math.min(
                                radarMap.maximumZoomLevel, radarMap.zoomLevel + 1)
                        }

                        Button {
                            width: 32; height: 32
                            text: "−"
                            font.pixelSize: 16
                            font.bold: true
                            onClicked: radarMap.zoomLevel = Math.max(
                                radarMap.minimumZoomLevel, radarMap.zoomLevel - 1)
                        }

                        Button {
                            width: 32; height: 32
                            text: "🎯"
                            font.pixelSize: 14
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
                                }
                            }
                        }
                    }

                    // ── Loading indicator ──
                    BusyIndicator {
                        anchors.centerIn: parent
                        running: root.loading && !playback.running
                        visible: running
                        z: 30
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
