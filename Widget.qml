import QtQuick
import Quickshell
import qs.Ui

BarWidget {
    id: root
    moduleName: "meshcore.atlas"
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight
    WidgetButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        text: "\uf519"
        tooltipText: "Open Mesh Atlas · MeshCore"
        onPressed: function(mouseButton) {
            if (mouseButton === Qt.LeftButton)
                Quickshell.execDetached(["python3", Qt.resolvedUrl("launch.py").toString().replace("file://", "")])
        }
    }
}
