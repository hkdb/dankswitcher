import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    pluginId: "dankswitcher"

    StyledText {
        width: parent.width
        text: "Hold Super and tap Tab to cycle windows across all workspaces. Release Super to focus the selected one. Binds are set in hyprland.lua (see README)."
        font.pixelSize: Theme.fontSizeMedium
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    ToggleSetting {
        settingKey: "showTitle"
        label: "Show window title"
        description: "Display the selected window's title and workspace under the icon strip"
        defaultValue: true
    }

    SelectionSetting {
        settingKey: "iconSize"
        label: "Icon size"
        description: "Size of each app icon in the strip"
        options: [
            {label: "Small (40)", value: "40"},
            {label: "Medium (56)", value: "56"},
            {label: "Large (72)", value: "72"},
            {label: "Huge (96)", value: "96"}
        ]
        defaultValue: "56"
    }

    SelectionSetting {
        settingKey: "containerRadius"
        label: "Corner radius"
        description: "Rounding of the switcher container"
        options: [
            {label: "None", value: "0"},
            {label: "Small (12)", value: "12"},
            {label: "Medium (20)", value: "20"},
            {label: "Large (28)", value: "28"},
            {label: "Pill (40)", value: "40"}
        ]
        defaultValue: "20"
    }

    SelectionSetting {
        settingKey: "holdMs"
        label: "Sticky hold time"
        description: "How long to hold Super+Tab before releasing leaves the strip open. Quicker releases switch straight away"
        options: [
            {label: "Short (250 ms)", value: "250"},
            {label: "Medium (500 ms)", value: "500"},
            {label: "Long (750 ms)", value: "750"},
            {label: "Very long (1000 ms)", value: "1000"}
        ]
        defaultValue: "500"
    }

    ToggleSetting {
        settingKey: "includeSpecial"
        label: "Include scratchpad windows"
        description: "Also list windows on special (scratchpad) workspaces"
        defaultValue: false
    }
}
