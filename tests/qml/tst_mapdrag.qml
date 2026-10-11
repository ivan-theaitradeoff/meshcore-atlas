import QtQuick
import QtTest
import QtPositioning
import "../.." as App

TestCase {
    name: "MapDragging"
    visible: true
    when: windowShown
    width: 800; height: 600
    App.MapPanel {
        id: panel
        anchors.fill: parent
        client: QtObject { id: fakeClient; property var mapNodes: [] }
        theme: QtObject {
            property color background: "#171e26"
            property color surface: "#202a36"
            property color foreground: "white"
            property color muted: "gray"
            property color warning: "orange"
        }
        tileUrl: "http://127.0.0.1:9/"
    }
    function drag(map, dx, dy) {
        mousePress(map, 300, 200, Qt.LeftButton)
        for (let i = 1; i <= 10; ++i) mouseMove(map, 300 + dx*i/10, 200 + dy*i/10, 20)
        mouseRelease(map, 300 + dx, 200 + dy, Qt.LeftButton)
        wait(50)
    }
    function test_markers_survive_pan_and_neighbour_removal() {
        const map = findChild(panel, "mapCanvas")
        tryCompare(map, "mapReady", true, 10000)
        map.center = QtPositioning.coordinate(47, -122)
        map.zoomLevel = 12
        fakeClient.mapNodes = [
            {id: "a", name: "Test A", latitude: 47, longitude: -122, type: 2, last_advert: 0},
            {id: "b", name: "Test B", latitude: 47.04, longitude: -122.04, type: 2, last_advert: 0}
        ]
        panel.recluster()
        const model = findChild(panel, "mapClusters")
        tryCompare(model, "count", 2)
        wait(100)
        const first = findChild(panel, 'mapMarker:["a"]')
        verify(first !== null)
        map.pan(12, 8)
        panel.recluster()
        wait(100)
        compare(findChild(panel, 'mapMarker:["a"]'), first, "Panning must retain the same marker object")
        fakeClient.mapNodes = [fakeClient.mapNodes[0]]
        panel.recluster()
        wait(100)
        compare(model.count, 1)
        compare(findChild(panel, 'mapMarker:["a"]'), first, "Removing another marker must not recreate survivors")
        fakeClient.mapNodes = []
        panel.recluster()
    }
    function test_drag_both_axes() {
        const map = findChild(panel, "mapCanvas")
        verify(map !== null)
        tryCompare(map, "mapReady", true, 10000)
        map.center = QtPositioning.coordinate(47, -122)
        map.zoomLevel = 10
        let before = {latitude: map.center.latitude, longitude: map.center.longitude}
        drag(map, 120, 0)
        verify(Math.abs(map.center.longitude - before.longitude) > 0.01, "Horizontal drag must change longitude")
        before = {latitude: map.center.latitude, longitude: map.center.longitude}
        drag(map, 0, 100)
        verify(Math.abs(map.center.latitude - before.latitude) > 0.01, "Vertical drag must change latitude")
        before = {latitude: map.center.latitude, longitude: map.center.longitude}
        drag(map, 100, 100)
        verify(Math.abs(map.center.longitude - before.longitude) > 0.01, "Diagonal drag must retain horizontal movement")
        verify(Math.abs(map.center.latitude - before.latitude) > 0.01, "Diagonal drag must retain vertical movement")
    }
}
