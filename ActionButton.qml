import QtQuick
import QtQuick.Controls

Button {
    id: control
    property var theme
    implicitWidth: Math.max(78, contentItem.implicitWidth + 20)
    implicitHeight: Math.max(26, contentItem.implicitHeight + 8)
    padding: 4
    horizontalPadding: 10
    contentItem: Text {
        text: control.text
        font: control.font
        color: control.enabled ? control.theme.foreground : control.theme.muted
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    background: Rectangle {
        radius: 2
        border.color: control.visualFocus ? control.theme.accent : control.theme.border
        border.width: control.visualFocus ? 2 : 1
        gradient: Gradient {
            GradientStop { position: 0; color: control.down ? control.theme.selected : control.hovered ? control.theme.hover : control.theme.surface }
            GradientStop { position: 1; color: control.down ? control.theme.hover : control.hovered ? control.theme.selected : control.theme.sidebar }
        }
    }
}
