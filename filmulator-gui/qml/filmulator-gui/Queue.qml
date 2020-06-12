import QtQuick 2.12
import QtQuick.Layouts 1.12
import QtQml.Models 2.12
import "gui_components"
import "getRoot.js" as GetRootObject
import "colors.js" as Colors

Item {
    id: root
    property real uiScale: 1

    //The url gives us the resource name of the most recently produced image.
    property string url: ""

    property real thirdWidth: width/3

    property bool dragging: false
    property bool wasDragScrolling: false

    property real oldX
    property real newX

    onDraggingChanged: {
        //Always reset it back to off when the state changes.
        wasDragScrolling = false
    }

    onNewXChanged: {
        //Only do this if we were already dragScrolling.
        //This is to prevent the initial drag activation from initiating scrolling.

        //We want it to ramp up slowly, so that even towards the edges, you can swap two adjacent images without trouble.
        // Hence, the (-velocity/10 +-430)/uiScale term.

        //We cap the speed at the flick strength, which gets stronger from 1/3 from the edge towards the edge.

        //Additionally, the bigger the window, the faster we can go without the empty gap flying off the edge, so
        // flickStrength is multiplied by the square root of the window size relative to the 720p window size.
        var velocity = listView.horizontalVelocity
        var flickStrength
        if (newX >= oldX && newX >= 2*thirdWidth && wasDragScrolling) {
            flickStrength = Math.sqrt(width/(1280*uiScale))*(newX-2*thirdWidth)/thirdWidth
            listView.flick(uiScale*Math.max((-velocity/10 -430)/uiScale, -3000*flickStrength),0)
        }
        else if (newX <= oldX && newX <= thirdWidth && wasDragScrolling) {
            flickStrength = Math.sqrt(width/(1280*uiScale))*(thirdWidth-newX)/thirdWidth
            listView.flick(uiScale*Math.min((-velocity/10 +430)/uiScale, 3000*flickStrength),0)
        }
        else {
            listView.flick(0,0)
        }
        oldX = newX
        wasDragScrolling = true
    }

    signal tooltipWanted(string text, int x, int y)

    GridView { //There is a bug in ListView that makes scrolling not smooth.
        id: listView
        anchors.fill: parent
        flow: GridView.FlowTopToBottom
        layoutDirection: Qt.LeftToRight
        cacheBuffer: 10
        cellWidth: root.height
        cellHeight: root.height

        boundsBehavior: Flickable.StopAtBounds
        flickDeceleration: 6000 * uiScale
        maximumFlickVelocity: 10000 * Math.sqrt(uiScale)

        displaced: Transition {
            NumberAnimation {
                properties: "x"
                easing.type: Easing.OutQuad
                duration: 200
            }
        }
        add: Transition {
            NumberAnimation {
                property: "widthScale"
                from: 0
                to: 1
                easing.type: Easing.OutQuad
                duration: 100
            }
        }
        remove: Transition {
            NumberAnimation {
                property: "widthScale"
                from: 1
                to: 0
                easing.type: Easing.OutQuad
                duration: 100
            }
        }

        model: DelegateModel {
            id: visualModel
            model: queueModel

            delegate: MouseArea {
                id: delegateRoot
                width: root.height
                height: root.height

                property int visualIndex: DelegateModel.itemsIndex
                property int oldVisualIndex

                /*DEBUG for QUEUE DRAG&DROP
                Text {
                    color: "white"
                    text: visualIndex
                }
                Text {
                    color: "white"
                    y: 10
                    text: QTsearchID
                }*/

                z: (held || queueDelegate.rightClicked) ? 1 : 0

                property bool held: false

                property alias widthScale: queueDelegate.widthScale

                //Tell it to move the queueDelegate
                drag.target: held ? queueDelegate : undefined
                drag.axis: Drag.XAxis

                acceptedButtons: Qt.LeftButton
                onPressAndHold: {
                    held = true
                    oldVisualIndex = visualIndex
                    root.dragging = true
                }
                onReleased: {
                    held = false
                    queueModel.move(queueDelegate.searchID, delegateRoot.visualIndex)
                    root.dragging = false
                }

                onDoubleClicked: {
                    console.log("New image: " + QTsearchID)
                    paramManager.selectImage(QTsearchID)
                }

                QueueDelegate {
                    id: queueDelegate
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: delegateRoot.verticalCenter
                    dim: root.height
                    rootDir: organizeModel.thumbDir()

                    selectedID: paramManager.imageIndex
                    searchID: QTsearchID
                    processed: QTprocessed
                    exported: QTexported
                    markedForOutput: QToutput
                    rating: STrating

                    queueIndex: QTindex

                    //This is the location of the latest image from the film image provider.
                    freshURL: root.url

                    onRefresh: {
                        console.log('refreshing queue')
                        queueModel.updateAll()
                    }


                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.RightButton
                        onClicked: {
                            loadMenu.sourceComponent = rightClickMenu
                            queueDelegate.rightClicked = true
                        }
                    }

                    Loader {
                        id: loadMenu
                    }

                    Component {
                        id: rightClickMenu
                        Item {
                            anchors.fill: parent
                            Item {
                                id: sizer
                                parent: GetRootObject.getDocRoot(root)
                                anchors.fill: parent
                            }

                            MouseArea {
                                id: clickCatcher
                                x: -queueDelegate.mapToItem(null,0,0).x - sizer.width
                                y: -queueDelegate.mapToItem(null,0,0).y - sizer.height
                                width: sizer.width * 3
                                height: sizer.height * 3
                                z: 1
                                acceptedButtons: Qt.AllButtons
                                onClicked: {
                                    queueDelegate.rightClicked = false
                                    loadMenu.sourceComponent = undefined
                                }
                                onWheel: {
                                    queueDelegate.rightClicked = false
                                    loadMenu.sourceComponent = undefined
                                    queueModel.updateAll();
                                }
                            }
                            ColumnLayout {
                                id: menuLayout
                                spacing: 0 * root.uiScale
                                x: Math.min(Math.max(0,-queueDelegate.mapToItem(null,0,0).x), sizer.mapToItem(queueDelegate,sizer.width,0).x - width)
                                anchors.bottom: parent.top
                                z: 2
                                width: 200 * root.uiScale

                                ToolButton {
                                    id: forgetButton
                                    property bool active: false
                                    text: active ? qsTr("Are you sure?") : qsTr("...Wait a moment...")
                                    width: parent.width
                                    z: 2
                                    uiScale: root.uiScale

                                    onTriggered: {
                                        if (forgetButton.active) {
                                            queueModel.batchForget()
                                            forgetButton.active = false
                                            queueDelegate.rightClicked = false
                                            loadMenu.sourceComponent = undefined
                                        }
                                        else {
                                            forgetCover.visible = true
                                            forgetButton.active = false
                                            forgetDelay.stop()
                                        }
                                    }

                                    Timer {
                                        id: forgetDelay
                                        interval: 1000
                                        onTriggered: {
                                            forgetButton.active = true
                                            forgetTimeout.start()
                                        }
                                    }
                                    Timer {
                                        id: forgetTimeout
                                        interval: 5000
                                        onTriggered: {
                                            forgetCover.visible = true
                                            forgetButton.active = false
                                        }
                                    }

                                    ToolButton {
                                        id: forgetCover
                                        text: qsTr("Forget photos")
                                        tooltipText: qsTr("Remove marked photos that are in the queue from the database. The files will not be deleted.")
                                        anchors.fill: parent
                                        uiScale: root.uiScale
                                        onTriggered: {
                                            forgetButton.active = false
                                            forgetCover.visible = false
                                            forgetDelay.start()
                                        }
                                        Component.onCompleted: {
                                            forgetCover.tooltipWanted.connect(root.tooltipWanted)
                                        }
                                    }
                                }
                                ToolButton {
                                    id: clearQueue
                                    property bool active: false
                                    text: active ? qsTr("Are you sure?") : qsTr("...Wait a moment...")
                                    width: parent.width
                                    z: 2
                                    uiScale: root.uiScale

                                    onTriggered: {
                                        if (clearQueue.active) {
                                            queueModel.clearQueue()
                                            clearQueue.active = false
                                            queueDelegate.rightClicked = false
                                            loadMenu.sourceComponent = undefined
                                        }
                                        else {
                                            clearQueueCover.visible = true
                                            clearQueue.active = false
                                            clearQueueDelay.stop()
                                        }
                                    }
                                    onPressedChanged: {
                                        if (clearQueue.pressed && !clearQueue.active) {
                                            clearQueue.active = false
                                            clearQueueCover.visible = true
                                            clearQueueDelay.stop()
                                        }
                                    }

                                    Timer {
                                        id: clearQueueDelay
                                        interval: 1000
                                        onTriggered: {
                                            clearQueue.active = true
                                            clearQueueTimeout.start()
                                        }
                                    }
                                    Timer {
                                        id: clearQueueTimeout
                                        interval: 5000
                                        onTriggered: {
                                            clearQueueCover.visible = true
                                            clearQueue.active = false
                                        }
                                    }

                                    ToolButton {
                                        id: clearQueueCover
                                        text: qsTr("Clear entire queue")
                                        anchors.fill: parent
                                        uiScale: root.uiScale
                                        onTriggered: {
                                            clearQueue.active = false//just in case
                                            clearQueueCover.visible = false
                                            clearQueueDelay.start()
                                        }
                                    }
                                }
                                ToolButton {
                                    id: removeFromQueue
                                    text: qsTr("Remove from queue")
                                    width: parent.width
                                    z: 2
                                    onTriggered: {
                                        queueModel.deQueue(QTsearchID)
                                        queueDelegate.rightClicked = false
                                        loadMenu.sourceComponent = undefined
                                    }
                                    uiScale: root.uiScale
                                }
                                ToolButton {
                                    id: copyAll
                                    text: qsTr("Copy all settings")
                                    width: parent.width
                                    z: 2
                                    onTriggered: {
                                        paramManager.copyAll(QTsearchID)
                                        queueDelegate.rightClicked = false
                                        loadMenu.sourceComponent = undefined
                                    }
                                    uiScale: root.uiScale
                                }
                                ToolButton {
                                    id: paste
                                    text: qsTr("Paste settings")
                                    width: parent.width
                                    z: 2
                                    notDisabled: paramManager.pasteable
                                    onTriggered: {
                                        paramManager.paste(QTsearchID)
                                        queueDelegate.rightClicked = false
                                        loadMenu.sourceComponent = undefined
                                    }
                                    uiScale: root.uiScale
                                }
                                Item {
                                    //row layouts have rounding issues at high item counts if you specify size
                                    //if you use Layouts.fillWidth then the gaps are too big
                                    id: rateRow
                                    width: parent.width
                                    height: 30 * root.uiScale
                                    z: 2

                                    property int buttonCount: 7
                                    property real buttonWidth: parent.width/buttonCount

                                    ToolButton {
                                        id: rateNegative
                                        width: parent.buttonWidth
                                        x: 0 * parent.buttonWidth
                                        text: qsTr("X")
                                        tooltipText: qsTr("Mark this photo for forgetting or for deletion")
                                        notDisabled: STrating >= 0 //-6 through -1 should be deletion, mapped to 5 through 0 rating, to preserve rating when swapping between deletion and non-deletion
                                        uiScale: root.uiScale
                                        onTriggered: {
                                            organizeModel.setRating(QTsearchID, -1)
                                            queueDelegate.rightClicked = false
                                            loadMenu.sourceComponent = undefined
                                        }
                                        Component.onCompleted: {
                                            rateNegative.tooltipWanted.connect(root.tooltipWanted)
                                        }
                                    }
                                    ToolButton {
                                        id: rate0
                                        width: parent.buttonWidth
                                        x: 1 * parent.buttonWidth
                                        text: qsTr("0")
                                        tooltipText: qsTr("Rate this 0 stars")
                                        notDisabled: 0 != STrating
                                        uiScale: root.uiScale
                                        onTriggered: {
                                            organizeModel.setRating(QTsearchID, 0)
                                            queueDelegate.rightClicked = false
                                            loadMenu.sourceComponent = undefined
                                        }
                                        Component.onCompleted: {
                                            rate0.tooltipWanted.connect(root.tooltipWanted)
                                        }
                                    }
                                    ToolButton {
                                        id: rate1
                                        width: parent.buttonWidth
                                        x: 2 * parent.buttonWidth
                                        text: qsTr("1")
                                        tooltipText: qsTr("Rate this 1 star")
                                        notDisabled: 1 != STrating
                                        uiScale: root.uiScale
                                        onTriggered: {
                                            organizeModel.setRating(QTsearchID, 1)
                                            queueDelegate.rightClicked = false
                                            loadMenu.sourceComponent = undefined
                                        }
                                        Component.onCompleted: {
                                            rate1.tooltipWanted.connect(root.tooltipWanted)
                                        }
                                    }
                                    ToolButton {
                                        id: rate2
                                        width: parent.buttonWidth
                                        x: 3 * parent.buttonWidth
                                        text: qsTr("2")
                                        tooltipText: qsTr("Rate this 2 stars")
                                        notDisabled: 2 != STrating
                                        uiScale: root.uiScale
                                        onTriggered: {
                                            organizeModel.setRating(QTsearchID, 2)
                                            queueDelegate.rightClicked = false
                                            loadMenu.sourceComponent = undefined
                                        }
                                        Component.onCompleted: {
                                            rate2.tooltipWanted.connect(root.tooltipWanted)
                                        }
                                    }
                                    ToolButton {
                                        id: rate3
                                        width: parent.buttonWidth
                                        x: 4 * parent.buttonWidth
                                        text: qsTr("3")
                                        tooltipText: qsTr("Rate this 3 stars")
                                        notDisabled: 3 != STrating
                                        uiScale: root.uiScale
                                        onTriggered: {
                                            organizeModel.setRating(QTsearchID, 3)
                                            queueDelegate.rightClicked = false
                                            loadMenu.sourceComponent = undefined
                                        }
                                        Component.onCompleted: {
                                            rate3.tooltipWanted.connect(root.tooltipWanted)
                                        }
                                    }
                                    ToolButton {
                                        id: rate4
                                        width: parent.buttonWidth
                                        x: 5 * parent.buttonWidth
                                        text: qsTr("4")
                                        tooltipText: qsTr("Rate this 4 stars")
                                        notDisabled: 4 != STrating
                                        uiScale: root.uiScale
                                        onTriggered: {
                                            organizeModel.setRating(QTsearchID, 4)
                                            queueDelegate.rightClicked = false
                                            loadMenu.sourceComponent = undefined
                                        }
                                        Component.onCompleted: {
                                            rate4.tooltipWanted.connect(root.tooltipWanted)
                                        }
                                    }
                                    ToolButton {
                                        id: rate5
                                        width: parent.buttonWidth
                                        x: 6 * parent.buttonWidth
                                        text: qsTr("5")
                                        tooltipText: qsTr("Rate this 5 stars")
                                        notDisabled: 5 != STrating
                                        uiScale: root.uiScale
                                        onTriggered: {
                                            organizeModel.setRating(QTsearchID, 5)
                                            queueDelegate.rightClicked = false
                                            loadMenu.sourceComponent = undefined
                                        }
                                        Component.onCompleted: {
                                            rate5.tooltipWanted.connect(root.tooltipWanted)
                                        }
                                    }
                                }
                                Item {
                                    id: rightClickBottomSpacer
                                    implicitHeight: 2*uiScale
                                }
                            }
                        }
                    }

                    held: delegateRoot.held
                    Drag.active: held
                    Drag.source: delegateRoot
                    Drag.hotSpot.x: width/2
                    Drag.hotSpot.y: height/2
                    onHeldChanged: {
                        if (held === false) {
                            Drag.drop()
                        }
                    }

                    states: [
                        State {
                            when: delegateRoot.held
                            ParentChange {
                                target: queueDelegate
                                parent: listView
                            }
                            AnchorChanges {
                                target: queueDelegate
                                anchors.horizontalCenter: undefined
                            }
                        }
                    ]
                }

                DropArea {
                    id: dropArea
                    anchors.fill: parent

                    onEntered: {
                        var source = drag.source.visualIndex
                        var dest = delegateRoot.visualIndex
                        //Tell the root that the cursor has moved to initiate scrolling.
                        root.newX = mapToItem(root,drag.x,drag.y).x
                        visualModel.items.move(source, dest)
                    }

                    onPositionChanged: {
                        //Tell the root that the cursor has moved to initiate scrolling.
                        root.newX = mapToItem(root,drag.x,drag.y).x
                    }
                }
            }
        }

        //Once we get incremental updates, this should also probably go away.
        Connections {
            target: queueModel
            function onQueueChanged() {
                var xPos = listView.contentX
                queueModel.setQueueQuery()
                listView.contentX = xPos
            }
        }

        //This one will have to go away when we get proper updates.
        Connections {
            target: importModel
            function onImportChanged() {
                var xPos = listView.contentX
                queueModel.setQueueQuery()
                listView.contentX = xPos
            }
        }
    }

    //Custom scrolling implementation.
    //It's disabled while you drag an image.
    MouseArea {
        id: wheelstealer
        anchors.fill: listView
        acceptedButtons: Qt.NoButton
        onWheel: {
            var velocity = listView.horizontalVelocity
            if (wheel.angleDelta.y > 0 && !listView.atXBeginning && !root.dragging) {
                //Leftward; up on the scroll wheel.

                //This formula makes each click of the wheel advance the 'target' a fixed distance.
                //We use the angle delta to handle multi-size scrolling like smooth scrolling touchpads.
                //We scale by uiScale.
                listView.flick(uiScale*(velocity < 0 ? Math.sqrt(velocity*velocity/(uiScale*uiScale) + 2000000*wheel.angleDelta.y/120) : (velocity == 0 ? 500 : 0)), 0)
            }
            if (wheel.angleDelta.y < 0 && !listView.atXEnd && !root.dragging) {
                //Rightward; down on the scroll wheel.
                listView.flick(uiScale*(velocity > 0 ? -Math.sqrt(velocity*velocity/(uiScale*uiScale) + 2000000*wheel.angleDelta.y/(-120)): (velocity == 0 ? -500 : 0)), 0)
            }
        }
    }
}
