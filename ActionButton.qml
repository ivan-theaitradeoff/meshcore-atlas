import QtQuick
import QtQuick.Controls

Button {
    id: control
    implicitWidth: Math.max(78, contentItem.implicitWidth + 20)
    implicitHeight: Math.max(26, contentItem.implicitHeight + 8)
    padding: 4
    horizontalPadding: 10
    contentItem: Text {
        text: control.text
        font: control.font
        color: control.enabled ? "#e4e8ed" : "#a0a5ad"
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    background: Rectangle {
        radius: 2
        border.color: control.visualFocus ? "#bdd0e5" : "#696969"
        border.width: control.visualFocus ? 2 : 1
        gradient: Gradient {
            GradientStop { position: 0; color: control.down ? "#353535" : control.hovered ? "#565656" : "#494949" }
            GradientStop { position: 1; color: control.down ? "#303030" : control.hovered ? "#464646" : "#383838" }
        }
    }
}
