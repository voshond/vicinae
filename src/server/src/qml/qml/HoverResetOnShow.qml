import QtQuick

Connections {
    function onVisibleChanged() {
        if (target && target.visible)
            HoverActivation.reset();

    }

    ignoreUnknownSignals: true
    Component.onCompleted: {
        if (target && target.visible)
            HoverActivation.reset();

    }
}
