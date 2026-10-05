#!/bin/bash

set -e

PURPLE='\e[38;5;141m'
CYAN='\033[0;36m'
GREEN='\033[1;32m'
NC='\033[0m' 

echo -e "${PURPLE}

|~\\ _ ._ |   (~    o_|_ _|_  _._
|_/(_|| ||<  _)\\/\\/| | (_| |}_| 
${NC}"
PLUGIN_DIR=~/.config/DankMaterialShell/plugins/dankswitcher

echo -e "${GREEN}******* START *******${NC}\n"
if [ -d "$PLUGIN_DIR" ]; then
    UPDATE=1
    echo -e "🔄️ Existing install found, updating..."
else
    UPDATE=0
    echo -e "🛸️ Making plugin directory..."
    mkdir -p "$PLUGIN_DIR"
fi
echo -e "\n📦️ Copying files to plugin directory..."
cd "$(dirname "$0")"
cp -r * "$PLUGIN_DIR/"
echo -e "\n${GREEN}***** COMPLETED *****${NC}"
echo ""
echo ""
if [ "$UPDATE" -eq 1 ]; then
    echo -e "Run the following command to load the update:"
    echo -e "\n   - ${CYAN}dms ipc call plugins reload dankswitcher${NC}"
    echo -e "\nIf dankswitcher.lua changed, also run ${CYAN}hyprctl reload${NC}."
    exit 0
fi
echo -e "Run the following commands to enable the plugin:"
echo -e "\n   - ${CYAN}dms ipc call plugin-scan scan${NC}"
echo -e "   - ${CYAN}dms ipc call plugins enable dankswitcher${NC}"
echo -e "\nThen, add the following line to your hyprland.lua file and restart dms-shell:\n"
echo -e "${CYAN}dofile(os.getenv(\"HOME\") .. \"/.config/DankMaterialShell/plugins/dankswitcher/dankswitcher.lua\")${NC}"
