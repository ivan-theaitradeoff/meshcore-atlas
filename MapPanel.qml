pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtLocation
import QtPositioning
import QtCore
import "MapClusters.js" as Clusters

Rectangle {
    id: root
    property var theme
    required property var client
    signal openContact(string target)
    property string tileUrl: "https://tile.openstreetmap.org/"
    property var selected: null
    property var selectedGroup: []
    ListModel { id: clusterModel; objectName: "mapClusters" }
    property bool restoringView: true
    property bool autoFitPending: saved.latitude === 0 && saved.longitude === 0
    function recluster() {
        if (!map.mapReady) return
        const points = []
        for (const node of located) {
            const p = map.fromCoordinate(QtPositioning.coordinate(node.latitude,node.longitude), false)
            if (isFinite(p.x) && isFinite(p.y) && p.x >= -80 && p.y >= -80 && p.x <= map.width+80 && p.y <= map.height+80)
                points.push({node:node,x:p.x,y:p.y})
        }
        const groups = Clusters.build(points, map.zoomLevel).map(function(group) {
            // Screen positions change while panning; marker identity does not.
            return {
                clusterKey: JSON.stringify(group.members.map(n => n.id).sort()),
                payload: JSON.stringify({members: group.members, latitude: group.latitude,
                                        longitude: group.longitude, label: group.label})
            }
        })
        const wanted = new Set(groups.map(g => g.clusterKey))
        for (let i = clusterModel.count - 1; i >= 0; --i)
            if (!wanted.has(clusterModel.get(i).clusterKey)) clusterModel.remove(i)
        for (let i = 0; i < groups.length; ++i) {
            const group = groups[i]
            let existing = -1
            for (let j = i; j < clusterModel.count; ++j)
                if (clusterModel.get(j).clusterKey === group.clusterKey) { existing = j; break }
            if (existing === -1) clusterModel.insert(i, group)
            else {
                if (existing !== i) clusterModel.move(existing, i, 1)
                if (clusterModel.get(i).payload !== group.payload)
                    clusterModel.setProperty(i, "payload", group.payload)
            }
        }
    }
    onLocatedChanged: {
        clusterTimer.restart()
        if (autoFitPending && located.length) initialFitTimer.restart()
    }
    Timer { id: clusterTimer; interval: 80; onTriggered: root.recluster() }
    Timer {
        id: initialFitTimer
        interval: 150
        onTriggered: {
            if (root.autoFitPending && map.mapReady && root.located.length) {
                root.fitNodes()
                root.autoFitPending = false
            }
        }
    }
    property int now: Math.floor(Date.now()/1000)
    readonly property var filtered: (client.mapNodes || []).filter(function(n) {
        return n.name.toLowerCase().indexOf(search.text.toLowerCase()) >= 0 && (kind.currentIndex !== 1 || n.type === 2)
    })
    readonly property var located: filtered.filter(n => n.latitude !== null && n.longitude !== null)
    readonly property int unknown: filtered.length - located.length
    Component.onCompleted: {
        const initialCenter = QtPositioning.coordinate(saved.latitude, saved.longitude)
        const initialZoom = saved.zoom
        map.center = initialCenter
        map.zoomLevel = initialZoom
        restoringView = false
        if (autoFitPending && located.length) initialFitTimer.restart()
    }
    color: root.theme.background
    Settings { id: saved; location: StandardPaths.writableLocation(StandardPaths.GenericConfigLocation) + "/mesh-atlas-map.ini"; category: "MeshAtlasMap"; property real latitude: 0; property real longitude: 0; property real zoom: 2 }
    Timer { interval: 60000; running: root.visible; repeat: true; onTriggered: root.now = Math.floor(Date.now()/1000) }
    function age(stamp) { if (!stamp) return "unknown age"; const minutes = Math.max(0, Math.floor((now-stamp)/60)); return minutes < 60 ? minutes+"m" : Math.floor(minutes/60)+"h" }
    function fitNodes() {
        if (!located.length) return
        let minLat=90,maxLat=-90,minLon=180,maxLon=-180
        for (const n of located) { minLat=Math.min(minLat,n.latitude); maxLat=Math.max(maxLat,n.latitude); minLon=Math.min(minLon,n.longitude); maxLon=Math.max(maxLon,n.longitude) }
        if (located.length===1 || (maxLat-minLat < 0.02 && maxLon-minLon < 0.02)) { map.center=QtPositioning.coordinate((minLat+maxLat)/2,(minLon+maxLon)/2); map.zoomLevel=12 }
        else map.visibleRegion=QtPositioning.rectangle(QtPositioning.coordinate(maxLat+0.02,minLon-0.02),QtPositioning.coordinate(minLat-0.02,maxLon+0.02))
    }
    Plugin {
        id: osm; name: "osm"
        PluginParameter { name: "osm.useragent"; value: "MeshAtlas-Omarchy/0.1 (Qt desktop MeshCore viewer)" }
        PluginParameter { name: "osm.mapping.custom.host"; value: root.tileUrl }
        PluginParameter { name: "osm.mapping.providersrepository.disabled"; value: true }
        PluginParameter { name: "osm.mapping.prefetching_style"; value: "NoPrefetching" }
        PluginParameter { name: "osm.mapping.custom.mapcopyright"; value: "© OpenStreetMap contributors" }
        PluginParameter { name: "osm.mapping.cache.disk.size"; value: 100000000 }
    }
    ColumnLayout {
        anchors.fill: parent; spacing: 8
        RowLayout {
            TextField { id: search; placeholderText: "Search nodes…"; Layout.fillWidth: true }
            ComboBox { id: kind; model: ["All nodes", "Repeaters"] }
            Button { text: "Fit nodes"; onClicked: root.fitNodes() }
        }
        Label { text: root.located.length + " mapped · " + root.unknown + " without location"; color: root.theme.muted }
        Map {
            id: map
            objectName: "mapCanvas"
            Layout.fillWidth: true; Layout.fillHeight: true
            plugin: osm
            color: root.theme.surface
            activeMapType: supportedMapTypes.length ? supportedMapTypes[supportedMapTypes.length-1] : null
            onCenterChanged: {
                if (!root.restoringView) {
                    const latitude = center.latitude
                    const longitude = center.longitude
                    saved.latitude = latitude
                    saved.longitude = longitude
                }
                clusterTimer.restart()
            }
            onZoomLevelChanged: function() { if (!root.restoringView) saved.zoom=zoomLevel; clusterTimer.restart() }
            onMapReadyChanged: {
                clusterTimer.restart()
                if (root.autoFitPending && root.located.length) initialFitTimer.restart()
            }
            onWidthChanged: clusterTimer.restart()
            onHeightChanged: clusterTimer.restart()
            DragHandler { target: null; onTranslationChanged: function(delta) { map.pan(-delta.x,-delta.y) } }
            WheelHandler { onWheel: function(event) { map.zoomLevel=Math.max(2,Math.min(19,map.zoomLevel+(event.angleDelta.y>0 ? 0.5 : -0.5))); event.accepted=true } }
            MapItemView {
                model: clusterModel
                add: null
                remove: null
                delegate: MapQuickItem {
                    id: marker
                    required property string clusterKey
                    required property string payload
                    readonly property var modelData: JSON.parse(payload)
                    objectName: "mapMarker:" + clusterKey
                    readonly property bool grouped: modelData.members.length > 1
                    readonly property var node: modelData.members[0]
                    coordinate: QtPositioning.coordinate(modelData.latitude,modelData.longitude)
                    anchorPoint.x: 24; anchorPoint.y: 24
                    z: pointer.containsMouse ? 10 : 1
                    sourceItem: Item {
                        width: 48; height: 48
                        Rectangle {
                            anchors.centerIn: parent
                            width: marker.grouped ? 44 : 36; height: width; radius: width/2
                            color: "#e53935"
                            border.width: 2.5; border.color: "#ffffff"
                            Text { anchors.centerIn: parent; text: marker.grouped ? marker.modelData.members.length : marker.node.type===2 ? "♜" : "●"; color: "#ffffff"; font.pixelSize: 17; font.bold: true }
                        }
                        Rectangle {
                            visible: !marker.grouped && (marker.modelData.label || pointer.containsMouse)
                            anchors.top: parent.bottom; anchors.topMargin: 3; anchors.horizontalCenter: parent.horizontalCenter
                            width: 220; height: 26; radius: 4; color: root.theme.surface
                            Text { anchors.fill: parent; anchors.margins: 5; text: marker.node.name+" · "+root.age(marker.node.last_advert); textFormat: Text.PlainText; elide: Text.ElideRight; color: root.theme.foreground; font.pixelSize: 12 }
                        }
                        MouseArea {
                            id: pointer; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (!marker.grouped) { root.selectedGroup=[]; root.selected=marker.node }
                                else if (map.zoomLevel < 19) { map.center=marker.coordinate; map.zoomLevel=Math.min(19,map.zoomLevel+2) }
                                else { root.selected=null; root.selectedGroup=marker.modelData.members }
                            }
                        }
                    }
                }
            }
            Column {
                anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 10
                Button { text: "+"; onClicked: map.zoomLevel=Math.min(19,map.zoomLevel+1) }
                Button { text: "−"; onClicked: map.zoomLevel=Math.max(2,map.zoomLevel-1) }
            }
            Rectangle {
                visible: root.selected !== null || root.selectedGroup.length > 0
                anchors.left: parent.left; anchors.top: parent.top; anchors.margins: 12
                width: Math.min(330,parent.width-90); height: details.implicitHeight+24
                color: root.theme.surface; radius: 6
                ColumnLayout {
                    id: details; anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                    Label { text: root.selected ? root.selected.name : root.selectedGroup.length + " nodes at this location"; textFormat: Text.PlainText; color: root.theme.foreground; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    Label { text: root.selected ? "Last advert: "+root.age(root.selected.last_advert)+" ago" : ""; color: root.theme.muted }
                    Button { visible: root.selected !== null; text: "Open contact"; onClicked: root.openContact(root.selected.id) }
                    ScrollView {
                        visible: root.selectedGroup.length > 0
                        Layout.fillWidth: true; Layout.preferredHeight: Math.min(220, root.selectedGroup.length*40)
                        Column { Repeater { model: root.selectedGroup; delegate: Button { required property var modelData; text: modelData.name; onClicked: { root.selected=modelData; root.selectedGroup=[] } } } }
                    }
                    Button { text: "Close"; onClicked: { root.selected=null; root.selectedGroup=[] } }
                }
            }
            Label { anchors.centerIn: parent; visible: map.errorString.length > 0; text: map.errorString; color: root.theme.warning; width: parent.width-40; wrapMode: Text.Wrap }
        }
        Label { text: "© OpenStreetMap contributors"; color: root.theme.muted; MouseArea { anchors.fill: parent; onClicked: Qt.openUrlExternally("https://www.openstreetmap.org/copyright") } }
    }
}
