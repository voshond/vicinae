import QtQuick

Item {
    id: root

    required property string text
    property real leftPadding: 16

    height: 30

    Text {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: root.leftPadding
        anchors.rightMargin: root.leftPadding
        anchors.verticalCenter: parent.verticalCenter
        text: root.text
        color: Theme.textMuted
        font.pointSize: Theme.smallerFontSize
        font.weight: Font.DemiBold
        elide: Text.ElideRight
    }

}
