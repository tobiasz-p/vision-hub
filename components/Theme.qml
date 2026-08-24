pragma Singleton
import QtQuick
import qs.Commons
import qs.Ui

// VisionHub Design System (Tailwind-like Design Tokens & Theme Configuration)
QtObject {
  // ---- Colors & Palette ----------------------------------------------------
  readonly property var colors: QtObject {
    // Brand & Status
    readonly property color emerald500: "#10b981"
    readonly property color emerald400: "#34d399"
    readonly property color red500: "#ef4444"
    readonly property color red400: "#f87171"

    // Semantic mappings
    readonly property color healthy: emerald500
    readonly property color healthyText: emerald400
    readonly property color urgent: Color.urgent

    // Alpha Tint Helpers (Tailwind bg-accent/20 etc)
    function tint(c, alpha) {
      return Qt.rgba(c.r, c.g, c.b, alpha)
    }

    readonly property color accentSubtle: tint(Color.accent, 0.16)
    readonly property color accentMuted: tint(Color.accent, 0.22)
    readonly property color accentStrong: tint(Color.accent, 0.25)
    readonly property color healthySubtle: tint(emerald500, 0.14)
    readonly property color healthyMuted: tint(emerald500, 0.18)
    readonly property color urgentSubtle: tint(Color.urgent, 0.15)
    readonly property color urgentMuted: tint(Color.urgent, 0.18)
    readonly property color surfaceMuted: tint(Color.foreground, 0.05)
    readonly property color surfaceHover: tint(Color.foreground, 0.10)
    readonly property color surfaceGlass: tint(Color.background, 0.65)
    readonly property color hairline: tint(Color.foreground, 0.10)
    readonly property color divider: tint(Color.foreground, 0.20)
  }

  // ---- Typography (Font sizes, weights, tracking) --------------------------
  readonly property var font: QtObject {
    readonly property int xs: 10
    readonly property int sm: 11
    readonly property int base: 12
    readonly property int md: 13
    readonly property int lg: 14
    readonly property int xl: 18
    readonly property int xxl: 20
    readonly property int iconSm: 12
    readonly property int iconBase: 14
    readonly property int iconLg: 18
    readonly property int iconXl: 24
    readonly property int iconHero: 32

    // Letter Spacing (Tracking)
    readonly property real trackingTight: 0.4
    readonly property real trackingNormal: 0.5
    readonly property real trackingWide: 0.8
    readonly property real trackingWidest: 1.2
  }

  // ---- Spacing & Geometry --------------------------------------------------
  readonly property var spacing: QtObject {
    readonly property int xs: 4
    readonly property int sm: 6
    readonly property int md: 8
    readonly property int lg: 12
    readonly property int xl: 16
    readonly property int xxl: 24
  }

  // ---- Radii / Rounded Corners ---------------------------------------------
  readonly property var radius: QtObject {
    readonly property int sm: 10
    readonly property int md: 12
    readonly property int badge: 13
    readonly property int tab: 14
    readonly property int pill: 16
    readonly property int switcher: 17
    readonly property int action: 19
    readonly property int circle: 24
    readonly property int dock: 26
  }

  // ---- Component Sizing (Design System Tokens) -----------------------------
  readonly property var components: QtObject {
    readonly property int headerHeight: 56
    readonly property int buttonHeight: 32
    readonly property int badgeHeight: 26
    readonly property int dockHeight: 52
    readonly property int navCircleSize: 48
    readonly property int dotDiameter: 7
    readonly property int logoBoxSize: 36
  }

  // ---- Responsive Breakpoints (Tailwind-like sm, md, lg) -------------------
  readonly property var screens: QtObject {
    readonly property int sm: 680
    readonly property int md: 820
    readonly property int lg: 900
    readonly property int minWindowWidth: 680
    readonly property int minWindowHeight: 480
    readonly property int defaultWindowWidth: 1120
    readonly property int defaultWindowHeight: 740
  }

  // ---- Animation & Timers --------------------------------------------------
  readonly property var animation: QtObject {
    readonly property int pulseDurationMs: 900
    readonly property int patrolIntervalMs: 6000
    readonly property int minFrameIntervalMs: 30
  }

  // ---- App / Plugin Identity -----------------------------------------------
  readonly property string pluginId: "tobiasz-p.vision-hub"
}
