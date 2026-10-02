#ifndef RUNNER_KWIN_PANEL_STACKING_SCRIPT_H_
#define RUNNER_KWIN_PANEL_STACKING_SCRIPT_H_

// GTK's Wayland keep-above request is a no-op; KWin owns this policy instead.
inline constexpr char kKWinPanelStackingScript[] = R"script(
(function () {
    "use strict";
    var applicationId = "com.divertedriver.HotkeyGrammarCorrector".toLowerCase();

    function isPanel(window) {
        return window.normalWindow &&
            (String(window.resourceClass).toLowerCase() === applicationId ||
             String(window.desktopFileName).toLowerCase() === applicationId);
    }

    function activate(window) {
        if (window.minimized || window.hidden) {
            return;
        }
        window.keepAbove = true;
        if (workspace.activeWindow !== undefined) {
            workspace.activeWindow = window;
        } else {
            workspace.activeClient = window;
        }
        window.demandsAttention = false;
    }

    function manage(window) {
        if (!isPanel(window)) {
            return;
        }
        window.keepAbove = true;
        window.demandsAttentionChanged.connect(function () {
            if (window.demandsAttention) {
                activate(window);
            }
        });
        window.minimizedChanged.connect(function () {
            if (!window.minimized) {
                activate(window);
            }
        });
        window.hiddenChanged.connect(function () {
            if (!window.hidden) {
                activate(window);
            }
        });
        // Focus loss belongs to CAP-14. Never reactivate from activeChanged.
        activate(window);
    }

    // Plasma 6 renamed the workspace API; Plasma 5 remains supported.
    var added = workspace.windowAdded || workspace.clientAdded;
    added.connect(manage);
    var windows = typeof workspace.windowList === "function" ?
        workspace.windowList() : workspace.clientList();
    windows.forEach(manage);
}());
)script";

#endif  // RUNNER_KWIN_PANEL_STACKING_SCRIPT_H_
