import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons as Commons

// Wraps the lock screen so it can leave the screen instead of blinking away.
// The compositor paints black under the lock surface, so the plain wallpaper
// underneath is what keeps the unlock from fading through black: the design
// dissolves into the background the desktop is about to show anyway.
Item {
  id: layer

  // "fade", "zoom", "rise" or "none", see `omarchy-shell lock unlockAnimation`.
  property string animation: "fade"
  property int duration: 400
  property bool active: false
  property string backgroundUrl: ""
  property bool solidOnly: false

  default property alias content: stage.data

  readonly property bool animated: animation !== "none" && duration > 0

  // The wallpaper is fitted and centered, the way the desktop draws it: at one
  // width shared by every screen (the narrowest), on a gradient of its own top
  // and bottom edge colors, so the unlock fades into the desktop without a jump.
  readonly property string backgroundFile: {
    var u = String(layer.backgroundUrl || "")
    var q = u.indexOf("?")
    if (q >= 0) u = u.substring(0, q)
    try { return decodeURIComponent(u.replace(/^file:\/\//, "")) } catch (e) { return "" }
  }
  readonly property real contentWidth: {
    var m = 0
    for (var i = 0; i < Quickshell.screens.length; i++) {
      var w = Quickshell.screens[i].width
      if (w > 0 && (m === 0 || w < m)) m = w
    }
    return m
  }
  readonly property real wallpaperZoom: {
    if (fitImage.paintedWidth <= 0 || layer.contentWidth <= 0) return 1.0
    return Math.min(1.0, layer.contentWidth / fitImage.paintedWidth)
  }
  readonly property real wallpaperTopFrac: {
    if (fitImage.paintedHeight <= 0 || height <= 0) return 0.5
    return Math.max(0, Math.min(0.5, (height - fitImage.paintedHeight * layer.wallpaperZoom) / 2 / height))
  }
  property color edgeTop: Commons.Color.background
  property color edgeBottom: Commons.Color.background

  function sampleEdges() {
    if (!layer.backgroundFile) return
    var base = [layer.backgroundFile, "-alpha", "off", "-gravity"]
    var tail = ["-crop", "100%x3%+0+0", "+repage", "-resize", "1x1!", "-format", "%[hex:p{0,0}]", "info:"]
    edgeTopProc.command = ["magick"].concat(base, ["north"], tail)
    edgeBottomProc.command = ["magick"].concat(base, ["south"], tail)
    edgeTopProc.running = true
    edgeBottomProc.running = true
  }

  onBackgroundFileChanged: sampleEdges()
  Component.onCompleted: sampleEdges()

  Process {
    id: edgeTopProc
    stdout: StdioCollector {
      id: edgeTopOut
      onStreamFinished: {
        var h = String(edgeTopOut.text || "").trim()
        if (/^[0-9A-Fa-f]{6}/.test(h)) layer.edgeTop = "#" + h.substring(0, 6)
      }
    }
  }

  Process {
    id: edgeBottomProc
    stdout: StdioCollector {
      id: edgeBottomOut
      onStreamFinished: {
        var h = String(edgeBottomOut.text || "").trim()
        if (/^[0-9A-Fa-f]{6}/.test(h)) layer.edgeBottom = "#" + h.substring(0, 6)
      }
    }
  }

  Item {
    anchors.fill: parent
    // Only needed once the design starts fading, but it loads with the lock so
    // it is decoded by then. Nothing sees it appear, the stage still covers it.
    visible: layer.animated && layer.active && (layer.solidOnly || fitImage.status === Image.Ready)

    Rectangle {
      anchors.fill: parent
      gradient: Gradient {
        GradientStop { position: layer.wallpaperTopFrac; color: layer.edgeTop }
        GradientStop { position: 1 - layer.wallpaperTopFrac; color: layer.solidOnly ? layer.edgeTop : layer.edgeBottom }
      }
    }

    Image {
      id: fitImage
      anchors.fill: parent
      visible: !layer.solidOnly
      source: layer.animated ? layer.backgroundUrl : ""
      fillMode: Image.PreserveAspectFit
      scale: layer.wallpaperZoom
      asynchronous: true
      cache: false
      sourceSize.width: width
      sourceSize.height: height
    }
  }

  Item {
    id: stage
    anchors.fill: parent

    readonly property bool leaving: layer.active && layer.animated
    property real zoom: leaving && layer.animation === "zoom" ? 1.06 : 1
    property real lift: leaving && layer.animation === "rise" ? -0.06 * height : 0

    opacity: leaving ? 0 : 1

    Behavior on opacity { NumberAnimation { duration: layer.duration; easing.type: Easing.OutCubic } }
    Behavior on zoom { NumberAnimation { duration: layer.duration; easing.type: Easing.OutCubic } }
    Behavior on lift { NumberAnimation { duration: layer.duration; easing.type: Easing.OutCubic } }

    transform: [
      Scale {
        origin.x: stage.width / 2
        origin.y: stage.height / 2
        xScale: stage.zoom
        yScale: stage.zoom
      },
      Translate { y: stage.lift }
    ]
  }
}
