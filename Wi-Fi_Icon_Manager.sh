#!/bin/bash

# ==============================================================================
# Wi-Fi Icon Manager for EmulationStation themes on ArkOS
# ==============================================================================

# --- Root Privilege Check ---
if [ "$(id -u)" -ne 0 ]; then
    exec sudo -- "$0" "$@"
fi

set -euo pipefail

# --- Global Variables ---
THEMES_DIR="/roms/themes"
CURR_TTY="/dev/tty1"
PATCH_MARKER=".wifi_icon_patched"
MAINXML_MARKER=".wifi_icon_patched_mainxml"

WIFI_ICON_POS_X="0.16"
WIFI_ICON_POS_Y="0.025"
WIFI_ICON_SIZE="0.07"

UPDATER_PATH="/usr/local/bin/wifi_icon_state_updater.sh"
SERVICE_PATH="/etc/systemd/system/wifi-icon-updater.service"

UPDATE_INTERVAL=5  # seconds

printf "\033c" > "$CURR_TTY"
printf "\e[?25l" > "$CURR_TTY" # Hide cursor
dialog --clear
export TERM=linux
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
if [[ ! -e "/dev/input/by-path/platform-odroidgo2-joypad-event-joystick" ]]; then
    setfont /usr/share/consolefonts/Lat7-TerminusBold22x11.psf.gz
else
    setfont /usr/share/consolefonts/Lat7-Terminus16.psf.gz
fi

pkill -9 -f gptokeyb || true
pkill -9 -f osk.py || true

printf "\033c" > "$CURR_TTY"
printf "Starting Wi-Fi Icon Manager. Please wait..." > "$CURR_TTY"
sleep 1

# --- UI + Cleanup ---
exit_script() {
    printf "\033c" > "$CURR_TTY"
    printf "\e[?25h" > "$CURR_TTY"
    pkill -f "gptokeyb -1 Wifi_icon_manager.sh" || true
    exit 0
}

restart_es_and_exit() {
    dialog --title "Restarting" --infobox "\nEmulationStation will now restart to apply changes..." 4 55 > "$CURR_TTY"
    sleep 2
    systemctl restart emulationstation &
    exit_script
}

check_dependencies() {
    local missing_pkgs=()
    for pkg in dialog nmcli awk; do
        if ! command -v "$pkg" &> /dev/null; then
            missing_pkgs+=("$pkg")
        fi
    done

    if [ ${#missing_pkgs[@]} -gt 0 ]; then
        dialog --title "Missing Dependencies" --msgbox "Missing packages: ${missing_pkgs[*]}.\nPlease install them." 6 60 > "$CURR_TTY"
        exit_script
    fi
}

create_updater_script() {
    cat > "$UPDATER_PATH" << 'EOF'
#!/bin/bash
THEMES_DIR="/roms/themes"
UPDATE_INTERVAL=5

prev_wifi_enabled=""

while true; do
    wifi_enabled=$(nmcli radio wifi)

    if [[ "$wifi_enabled" != "$prev_wifi_enabled" ]]; then
        for theme_path in "$THEMES_DIR"/*; do
            [ -d "$theme_path" ] || continue
            art_dir="$theme_path/_art"
            [ -d "$art_dir" ] || art_dir="$theme_path/art"
            [ -d "$art_dir" ] || continue

            icon_file="$art_dir/wifi.svg"
            on_bak="$art_dir/wifi_on.bak.svg"
            off_bak="$art_dir/wifi_off.bak.svg"

            if [[ "$wifi_enabled" == enabled* ]]; then
                [[ -f "$on_bak" ]] && cp "$on_bak" "$icon_file"
            else
                [[ -f "$off_bak" ]] && cp "$off_bak" "$icon_file"
            fi
        done

        systemctl restart emulationstation
        prev_wifi_enabled="$wifi_enabled"
    fi

    sleep "$UPDATE_INTERVAL"
done
EOF
    chmod +x "$UPDATER_PATH"
}

create_systemd_service() {
    cat > "$SERVICE_PATH" << EOF
[Unit]
Description=Wi-Fi Icon State Updater
After=network.target

[Service]
ExecStart=$UPDATER_PATH
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reexec
    systemctl daemon-reload
    systemctl enable --now wifi-icon-updater.service
}

themes_already_patched() {
    local all_patched=true
    for theme_path in "$THEMES_DIR"/*; do
        [ -d "$theme_path" ] || continue
        theme_xml_file="$theme_path/theme.xml"
        [ ! -f "$theme_xml_file" ] && continue
        if [ ! -f "$theme_path/$PATCH_MARKER" ]; then
            all_patched=false
            break
        fi
    done

    # Vérifie aussi NES-box
    NESBOX_PATH="$THEMES_DIR/es-theme-nes-box"
    if [ -d "$NESBOX_PATH" ] && [ ! -f "$NESBOX_PATH/$MAINXML_MARKER" ]; then
        all_patched=false
    fi

    $all_patched
}

install_icons() {
    dialog --title "Installing Icons" --infobox "Installing Wi-Fi icons in themes.\nBackups will be created." 5 55 > "$CURR_TTY"
    sleep 2
    
        if themes_already_patched; then
        dialog --title "Already Patched" --msgbox "All themes are already patched.\nNo changes necessary." 6 50 > "$CURR_TTY"
        return
    fi

    local progress_text=""

    # Patch for all theme.xml themes
    for theme_path in "$THEMES_DIR"/*; do
        [ -d "$theme_path" ] || continue
        theme_xml_file="$theme_path/theme.xml"
        [ ! -f "$theme_xml_file" ] && continue
        [ -f "$theme_path/$PATCH_MARKER" ] && continue

        cp "$theme_xml_file" "${theme_xml_file}.bak"

        art_dir="$theme_path/_art"
        [ -d "$art_dir" ] || art_dir="$theme_path/art"
        mkdir -p "$art_dir"
        icon_path_prefix=$(realpath --relative-to="$theme_path" "$art_dir")

        # Crée les fichiers SVG
        cat > "$art_dir/wifi_on.bak.svg" << 'EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 36 36" stroke="#28a745" fill="none" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
  <path d="M4 16 C12 8, 24 8, 32 16" />
  <path d="M8 20 C14 14, 22 14, 28 20" />
  <path d="M12 24 C16 20, 20 20, 24 24" />
  <circle cx="18" cy="28" r="1.5" fill="#28a745" />
</svg>
EOF

        cat > "$art_dir/wifi_off.bak.svg" << 'EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 36 36" stroke="#dc3545" fill="none" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
  <path d="M4 16 C12 8, 24 8, 32 16" />
  <path d="M8 20 C14 14, 22 14, 28 20" />
  <path d="M12 24 C16 20, 20 20, 24 24" />
  <circle cx="18" cy="28" r="1.5" fill="#dc3545" />
  <line x1="6" y1="6" x2="30" y2="30" stroke="#dc3545" />
</svg>
EOF

        # Par défaut, active l'icône "on"
        cp "$art_dir/wifi_on.bak.svg" "$art_dir/wifi.svg"

        xml_block="
    <image name=\"wifi_icon\" extra=\"true\">
        <path>./$icon_path_prefix/wifi.svg</path>
        <pos>${WIFI_ICON_POS_X} ${WIFI_ICON_POS_Y}</pos>
        <origin>0.5 0.5</origin>
        <maxSize>${WIFI_ICON_SIZE} ${WIFI_ICON_SIZE}</maxSize>
        <zIndex>150</zIndex>
        <visible>true</visible>
    </image>"

        awk -v block="$xml_block" '/<view / { print; print block; next } { print }' "$theme_xml_file" > "${theme_xml_file}.tmp" && mv "${theme_xml_file}.tmp" "$theme_xml_file"
        touch "$theme_path/$PATCH_MARKER"
        progress_text+="Patched: $(basename "$theme_path")\n"
    done

    # Patch spécifique pour es-theme-nes-box/main.xml
    NESBOX_PATH="$THEMES_DIR/es-theme-nes-box"
    if [ -d "$NESBOX_PATH" ] && [ ! -f "$NESBOX_PATH/$MAINXML_MARKER" ]; then
        nesbox_xml="$NESBOX_PATH/main.xml"
        [ -f "$nesbox_xml" ] || return

        cp "$nesbox_xml" "${nesbox_xml}.bak"
        art_dir="$NESBOX_PATH/_art"
        mkdir -p "$art_dir"
        icon_path_prefix=$(realpath --relative-to="$NESBOX_PATH" "$art_dir")

        cp "$art_dir/wifi_on.bak.svg" "$art_dir/wifi.svg"

        xml_block="
    <image name=\"wifi_icon\" extra=\"true\">
        <path>./$icon_path_prefix/wifi.svg</path>
        <pos>${WIFI_ICON_POS_X} ${WIFI_ICON_POS_Y}</pos>
        <origin>0.5 0.5</origin>
        <maxSize>${WIFI_ICON_SIZE} ${WIFI_ICON_SIZE}</maxSize>
        <zIndex>150</zIndex>
        <visible>true</visible>
    </image>"

        awk -v block="$xml_block" '
            /<view name="system">/ || /<view name="detailed,video">/ || /<view name="basic">/ {
                print;
                print block;
                next;
            }
            { print }
        ' "$nesbox_xml" > "${nesbox_xml}.tmp" && mv "${nesbox_xml}.tmp" "$nesbox_xml"

        touch "$NESBOX_PATH/$MAINXML_MARKER"
        progress_text+="Patched: es-theme-nes-box\n"
    fi

    dialog --title "Done" --msgbox "Installation complete.\n\n$progress_text" 0 0 > "$CURR_TTY"
    create_updater_script
    create_systemd_service
    restart_es_and_exit
}

uninstall_icons() {
    dialog --title "Uninstalling Icons" --infobox "Restoring themes..." 4 45 > "$CURR_TTY"
    sleep 2
    local progress_text=""

    for theme_path in "$THEMES_DIR"/*; do
        [ -d "$theme_path" ] || continue

        xml="$theme_path/theme.xml"
        [ -f "$theme_path/$PATCH_MARKER" ] && [ -f "$xml.bak" ] && mv "$xml.bak" "$xml" && rm -f "$theme_path/$PATCH_MARKER"

        xml="$theme_path/main.xml"
        [ -f "$theme_path/$MAINXML_MARKER" ] && [ -f "$xml.bak" ] && mv "$xml.bak" "$xml" && rm -f "$theme_path/$MAINXML_MARKER"

        rm -f "$theme_path"/{art,_art}/wifi_*.svg

        progress_text+="Cleaned: $(basename "$theme_path")\n"
    done

    rm -f "$UPDATER_PATH"
    rm -f "$SERVICE_PATH"
    systemctl daemon-reload

    dialog --title "Uninstall Complete" --msgbox "$progress_text" 0 0 > "$CURR_TTY"
    restart_es_and_exit
}

ExitMenu() {
    printf "\033c" > "$CURR_TTY"
    printf "\e[?25h" > "$CURR_TTY" # Show cursor
    pkill -f "gptokeyb -1 Wi-Fi_Icon_Manager.sh" || true
    if [[ ! -e "/dev/input/by-path/platform-odroidgo2-joypad-event-joystick" ]]; then
        setfont /usr/share/consolefonts/Lat7-Terminus20x10.psf.gz # Restore a common font
    fi
    exit 0
}

main_menu() {
    while true; do
        CHOICE=$(dialog --output-fd 1 \
            --backtitle "Wi-Fi Icon Manager for EmulationStation by Jason" \
            --title "Main Menu" \
            --cancel-label "Exit" \
            --menu "Choose an action:" 12 50 4 \
            1 "Install Wi-Fi icons" \
            2 "Uninstall Wi-Fi icons" \
         2>"$CURR_TTY")

        case $CHOICE in
            1) install_icons ;;
            2) uninstall_icons ;;
            *) ExitMenu ;;
        esac
    done
}

trap ExitMenu EXIT SIGINT SIGTERM

if command -v /opt/inttools/gptokeyb &> /dev/null; then
    if [[ -e /dev/uinput ]]; then
        chmod 666 /dev/uinput 2>/dev/null || true
    fi
    export SDL_GAMECONTROLLERCONFIG_FILE="/opt/inttools/gamecontrollerdb.txt"
    pkill -f "gptokeyb -1 Wi-Fi_Icon_Manager.sh" || true
    /opt/inttools/gptokeyb -1 "Wi-Fi_Icon_Manager.sh" -c "/opt/inttools/keys.gptk" >/dev/null 2>&1 &
else
    dialog --infobox "gptokeyb not found. Joystick control disabled." 3 50 > "$CURR_TTY"
    sleep 2
fi

printf "\033c" > "$CURR_TTY"

check_dependencies
main_menu
