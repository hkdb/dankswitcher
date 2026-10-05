// Pure logic for Dank Switcher. No Quickshell imports so it stays testable.
.pragma library

// Cycle order for freshly fetched `hyprctl -j clients`:
// - drop unmapped/hidden windows and (optionally) special-workspace windows
// - the currently focused window (focusHistoryID 0) goes LAST so the first
//   Tab lands on the previously used window, GNOME/macOS style
// - everything else ascending by focusHistoryID (most recent first)
function orderClients(clients, includeSpecial) {
    const rest = [];
    let active = null;

    for (const c of clients) {
        if (!c || c.mapped === false || c.hidden === true) continue;
        if (c.pinned) continue;
        const ws = c.workspace || {};
        if (!includeSpecial && typeof ws.id === "number" && ws.id < 0) continue;

        const fhid = c.focusHistoryID === undefined ? 0 : c.focusHistoryID;
        if (fhid === 0) {
            active = c;
            continue;
        }
        rest.push(c);
    }

    rest.sort((a, b) => a.focusHistoryID - b.focusHistoryID);
    if (active) rest.push(active);
    return rest;
}

// Icon cascade: desktop entry by id variants -> StartupWMClass -> app name
// contained in the window title (PWAs) -> icon theme by class -> generic.
function iconPathFor(DesktopEntries, Quickshell, cls, title) {
    const c = String(cls || "");
    const clsLower = c.toLowerCase();

    for (const v of [c, clsLower, c.replace(/-/g, ""), c.split(".")[0], c.split(".").pop()]) {
        if (!v) continue;
        const e = DesktopEntries.byId(v);
        if (e && e.icon) return Quickshell.iconPath(e.icon, "application-x-executable");
    }

    const all = (DesktopEntries.applications && DesktopEntries.applications.values) || [];
    for (const e of all) {
        if (e.startupClass && String(e.startupClass).toLowerCase() === clsLower && e.icon)
            return Quickshell.iconPath(e.icon, "application-x-executable");
    }

    const titleLower = String(title || "").toLowerCase();
    if (titleLower) {
        for (const e of all) {
            const n = String(e.name || "").toLowerCase();
            if (n && n.length > 2 && titleLower.includes(n) && e.icon)
                return Quickshell.iconPath(e.icon, "application-x-executable");
        }
    }

    for (const v of [c, clsLower, c.split("-")[0], c.split(".").pop()]) {
        // The class is client-chosen; never let it read as a file path.
        if (!v || v.includes("/") || v.startsWith(".")) continue;
        const p = Quickshell.iconPath(v, true);
        if (p) return p;
    }

    return Quickshell.iconPath("application-x-executable");
}

// Window addresses are spliced into a Lua dispatch string, so only accept
// the hex form hyprctl emits.
function isSafeAddress(a) {
    return typeof a === "string" && /^0x[0-9a-fA-F]+$/.test(a);
}

// Integer setting with a range and a fallback for junk values.
function clampInt(v, lo, hi, def) {
    const n = parseInt(v);
    if (isNaN(n)) return def;
    return Math.min(hi, Math.max(lo, n));
}
