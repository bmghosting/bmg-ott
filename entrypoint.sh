#!/bin/bash
cd /home/container

# Information output
echo "Running on Debian $(cat /etc/debian_version)"
echo "Current timezone: $(cat /etc/timezone)"
wine --version

# Make internal Docker IP address available to processes.
INTERNAL_IP=$(ip route get 1 | awk '{print $(NF-2);exit}')
export INTERNAL_IP

## just in case someone removed the defaults.
if [ "${STEAM_USER}" == "" ]; then
    echo -e "steam user is not set.\n"
    echo -e "Using anonymous user.\n"
    STEAM_USER=anonymous
    STEAM_PASS=""
    STEAM_AUTH=""
else
    echo -e "user set to ${STEAM_USER}"
fi

## if auto_update is not set or to 1 update
if [ -z ${AUTO_UPDATE} ] || [ "${AUTO_UPDATE}" == "1" ]; then 
    # Update Source Server
    if [ ! -z ${SRCDS_APPID} ]; then
	./steamcmd/steamcmd.sh +force_install_dir /home/container +login ${STEAM_USER} ${STEAM_PASS} ${STEAM_AUTH} $( [[ "${WINDOWS_INSTALL}" == "1" ]] && printf %s '+@sSteamCmdForcePlatformType windows' ) +app_update 1007 +app_update ${SRCDS_APPID} $( [[ -z ${SRCDS_BETAID} ]] || printf %s "-beta ${SRCDS_BETAID}" ) $( [[ -z ${SRCDS_BETAPASS} ]] || printf %s "-betapassword ${SRCDS_BETAPASS}" ) $( [[ -z ${HLDS_GAME} ]] || printf %s "+app_set_config 90 mod ${HLDS_GAME}" ) $( [[ -z ${VALIDATE} ]] || printf %s "validate" ) +quit
    else
        echo -e "No appid set. Starting Server"
    fi

else
    echo -e "Not updating game server as auto update was set to 0. Starting Server"
fi

if [[ $XVFB == 1 ]]; then
        Xvfb :0 -screen 0 ${DISPLAY_WIDTH}x${DISPLAY_HEIGHT}x${DISPLAY_DEPTH} &
fi

# Install necessary to run packages
echo "First launch will throw some errors. Ignore them"

mkdir -p $WINEPREFIX

# Check if wine-gecko required and install it if so
if [[ $WINETRICKS_RUN =~ gecko ]]; then
        echo "Installing Gecko"
        WINETRICKS_RUN=${WINETRICKS_RUN/gecko}

        if [ ! -f "$WINEPREFIX/gecko_x86.msi" ]; then
                wget -q -O $WINEPREFIX/gecko_x86.msi http://dl.winehq.org/wine/wine-gecko/2.47.4/wine_gecko-2.47.4-x86.msi
        fi

        if [ ! -f "$WINEPREFIX/gecko_x86_64.msi" ]; then
                wget -q -O $WINEPREFIX/gecko_x86_64.msi http://dl.winehq.org/wine/wine-gecko/2.47.4/wine_gecko-2.47.4-x86_64.msi
        fi

        wine msiexec /i $WINEPREFIX/gecko_x86.msi /qn /quiet /norestart /log $WINEPREFIX/gecko_x86_install.log
        wine msiexec /i $WINEPREFIX/gecko_x86_64.msi /qn /quiet /norestart /log $WINEPREFIX/gecko_x86_64_install.log
fi

# Check if wine-mono required and install it if so
if [[ $WINETRICKS_RUN =~ mono ]]; then
        echo "Installing mono"
        WINETRICKS_RUN=${WINETRICKS_RUN/mono}

        if [ ! -f "$WINEPREFIX/mono.msi" ]; then
                wget -q -O $WINEPREFIX/mono.msi https://dl.winehq.org/wine/wine-mono/9.1.0/wine-mono-9.1.0-x86.msi
        fi

        wine msiexec /i $WINEPREFIX/mono.msi /qn /quiet /norestart /log $WINEPREFIX/mono_install.log
fi

# List and install other packages
for trick in $WINETRICKS_RUN; do
        echo "Installing $trick"
        winetricks -q $trick
done

# Modify the configuration variables using sed
if [ -f "$SERVER_CONFIG_PATH" ]; then
    echo "Found configuration file - replacing variables"

    escape_for_sed() {
        printf '%s\n' "$1" | sed -e 's/\\/\\\\/g' -e 's/[\/&]/\\&/g'
    }

    [ -n "$SERVER_NAME" ]      && sed -i "s/^ServerName\s*=.*/ServerName = $(escape_for_sed "$SERVER_NAME")/" "$SERVER_CONFIG_PATH"
    [ -n "$PLAYERS" ]          && sed -i "s/^MaxPlayerCount\s*=.*/MaxPlayerCount = $(escape_for_sed "$PLAYERS")/" "$SERVER_CONFIG_PATH"
    [ -n "$MOTD" ]             && sed -i "s/^WelcomeMessage\s*=.*/WelcomeMessage = $(escape_for_sed "$MOTD")/" "$SERVER_CONFIG_PATH"
    [ -n "$PROBY_PASS" ]       && sed -i "s/^ProbyAdminPassword\s*=.*/ProbyAdminPassword = $(escape_for_sed "$PROBY_PASS")/" "$SERVER_CONFIG_PATH"
    [ -n "$SENIOR_PASS" ]      && sed -i "s/^SeniorAdminPassword\s*=.*/SeniorAdminPassword = $(escape_for_sed "$SENIOR_PASS")/" "$SERVER_CONFIG_PATH"
    [ -n "$ADMIN_PASS" ]       && sed -i "s/^AdminPassword\s*=.*/AdminPassword = $(escape_for_sed "$ADMIN_PASS")/" "$SERVER_CONFIG_PATH"
    [ -n "$WHITELIST" ]        && sed -i "s/^WhiteListIsEnabled\s*=.*/WhiteListIsEnabled = $(escape_for_sed "$WHITELIST")/" "$SERVER_CONFIG_PATH"
    [ -n "$SERVER_PASS" ]      && sed -i "s/^#\{0,1\}ServerPassword\s*=.*/ServerPassword = $(escape_for_sed "$SERVER_PASS")/" "$SERVER_CONFIG_PATH"
    [ -n "$SERVER_PORT" ]      && sed -i "s/^PortID\s*=.*/PortID = $(escape_for_sed "$SERVER_PORT")/" "$SERVER_CONFIG_PATH"
    [ -n "$STEAM_QUERY_PORT" ] && sed -i "s/^SteamQueryPortID\s*=.*/SteamQueryPortID = $(escape_for_sed "$STEAM_QUERY_PORT")/" "$SERVER_CONFIG_PATH"
else
    echo "Configuration file not found: $SERVER_CONFIG_PATH"
fi

# Replace Startup Variables
MODIFIED_STARTUP=$(echo ${STARTUP} | sed -e 's/{{/${/g' -e 's/}}/}/g')
echo ":/home/container$ ${MODIFIED_STARTUP}"

# Run the Server
eval ${MODIFIED_STARTUP}
