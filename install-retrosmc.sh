#!/bin/bash
# Installer for retropie on OSMC
#
# Used environment:
#   Files and Folder:
#     ~/Retropie             - Folder of the retrosmc repository.
#
#     ~/Retropie/var/version - currently installed version. Used for the
#                              upgrade process
#
# written by tvannahl

# set dialog default values
: ${DIALOG_OK=0}
: ${DIALOG_CANCEL=1}
: ${DIALOG_HELP=2}
: ${DIALOG_EXTRA=3}
: ${DIALOG_ITEM_HELP=4}
: ${DIALOG_ESC=255}

DEPENDENCIES=(
  "dialog"
  "git"
  "pv"
  "bzip2"
  "psmisc"
  "libusb-1.0"
  "alsa-utils"
)
SCRIPT_VERSION=1
SCRIPT=$(realpath -s $0)
SCRIPTPATH=$(dirname "${SCRIPT}")

function usage(){
  cat << __USAGE__
$(basename $0) [--install-retropie] [--install-plugin] [--help]

This is a script by mcobit to install retrosmc to OSMC.  I am not responsible
for any harm done to your system.  Using this is on your own risk.

Arguments:
  --install-retropie    Start retropie installer directly without menu
                        ahead.

  --install-plugin      Install retropie integartion plugin for kodi
                        without menu ahead.

  -h or --help          This dialog.
__USAGE__
}

#######################################
# Write stdin to log.
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
function log(){
  cat - | tee ~/retrosmc.log | logger -t retrosmc
}

#######################################
# Starts joystick to keyboard mapping
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
function start_joy2key() {
  JOY2KEY_DEV="/dev/input/jsX"
  # call joy2key.py: arguments are curses capability names or hex values
  # starting with '0x'
  # see: http://pubs.opengroup.org/onlinepubs/7908799/xcurses/terminfo.html
  systemd-run --user --unit=joy2key \
    python ~/RetroPie/scripts/joy2key.py /dev/input/jsX \
      kcub1 kcuf1 kcuu1 kcud1 0x0a 0x09
}

#######################################
# Stops joystick to keyboard mapping
#
# After the joy2key has been stopped the user can not use a controller to input
# keyboard events.
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
function stop_joy2key() {
  systemctl --user stop joy2key.service 2>&1 | log
}
trap stop_joy2key EXIT

#######################################
# Change into retrosmc folder.
#
# It does clone the repository if this file is not placed inside one.
# Globals:
#   PWD
# Arguments:
#   None
# Returns:
#   None
#######################################
function cd_retrosmc(){
  cd "${SCRIPTPATH}"
  if git status 2>&1 > /dev/null; then
    # standalone install script means that the rest of the repo needs to be
    # cloned. The fact that this is a fallback makes it possible for other
    # developers to test their modifications to the installer outside of this
    # branch.
    PREVPWD="${OLDPWD}"
    git clone https://github.com/mcobit/retrosmc.git ~/Retropie
    cd ~/Retropie
    OLDPWD="${PREVPWD}"
  fi
}


#######################################
# Start retropie installer
#
# Starts the retropie installer and installs the OSMC integration afterwards.
# Globals:
#   DEPENDENCIES
# Arguments:
#   $1 - Display command on which the current state gets displayed to the user.
#        This command is expected to accept one string argument.
# Returns:
#   None
#######################################
function install_retropie(){
  if [[ -f ~/Retropie/var/version ]]; then
    "${1}" "Retropie already installed. If you want to enforce a reinstall \
    delete the file ~/Retropie/var/version. But in most cases an upgrade should \
    be sufficient."
    return 1
  fi

  "${1}" "Installing dependencies"
  sudo apt-get update 2>&1 | log
  sudo apt-get install "${DEPENDENCIES[@]}" 2>&1 | log
  git clone https://github.com/RetroPie/RetroPie-Setup.git ~/RetroPie-Setup 2>&1 | log

  cd_retrosmc
  mkdir ~/Retropie/var/
  echo "${SCRIPT_VERSION}" > ~/Retropie/var/version
  sudo cp scripts/retropie.service /etc/systemd/system/
  sudo systemctl daemon-reload
  cd -
  cd ~/RetroPie-Setup
  stop_joy2key
  cat > ~/.emulationstation/es_input.cfg <<EOF
<?xml version="1.0"?>
<inputList>
  <inputAction type="onfinish">
    <command>/opt/retropie/supplementary/emulationstation/scripts/inputconfiguration.sh</command>
  </inputAction>
</inputList>
EOF
  # If something should be executed after the retropie_setup the path should be
  # manipulated to catch the call of `reboot`.
  sudo ./retropie_setup.sh
  cd -
}

#######################################
# Install retropie starter in kodi
# Globals:
#   None
# Arguments:
#   $1 - Display command on which the current state gets displayed to the user.
#        This command is expected to accept one string argument.
# Returns:
#   None
#######################################
function install_plugin(){
  "${1}" "installing plugin"
  cd_retrosmc
  cp -r plugin.program.retrosmc-launcher ~/.kodi/addons/
  cd -
}

#######################################
# Remove retropie starter from kodi
# Globals:
#   None
# Arguments:
#   $1 - Display command on which the current state gets displayed to the user.
#        This command is expected to accept one string argument.
# Returns:
#   None
#######################################
function remove_plugin(){
  $1 "removing plugin"
  rm -r ~/.kodi/addons/plugin.program.retrosmc-launcher
  # Small delay to visualize the action.
  sleep 1s
}

#######################################
# Remove retropie starter from kodi
# Globals:
#   None
# Arguments:
#   $1 - Display command on which the current state gets displayed to the user.
#        This command is expected to accept one string argument.
# Returns:
#   None
#######################################
function update_retrosmc(){
  "${1}" "Updating retrosmc"
  cd_retrosmc
  git pull 2>&1 | log
  ./install-retrosmc.sh --upgrade-retrosmc
  cd -
}

#######################################
# Push command to a stack. If this command has been previously stacked every
# older occurence will not be executed. This function is used as a helping
# function for upgrading so that the same command will not be executed multiple
# times.
#
# Globals:
#   None
# Arguments:
#   $1 - Text to be displayed
# Returns:
#   None
#######################################
function push_upgrade_stack(){
  [[ ! -d ~/Retropie/tmp ]] && mkdir ~/Retropie/tmp
  [[ ! -f ~/Retropie/tmp/upgrade_stack ]] && touch ~/Retropie/tmp/upgrade_stack

  tmpfile=$(mktemp)
  # strip previous executions of given command.
  grep -v "^${*}\$" ~/Retropie/tmp/upgrade_stack > "${tmpfile}"
  echo "${@}" >> "${tmpfile}"
  rm ~/Retropie/tmp/upgrade_stack
  mv "${tmpfile}" ~/Retropie/tmp/upgrade_stack
}

#######################################
# Execute command stack.
#
# Globals:
#   None
# Arguments:
#   $1 - Text to be displayed
# Returns:
#   None
#######################################
function execute_upgrade_stack(){
  [[ ! -f ~/Retropie/tmp/upgrade_stack ]] && return

  source ~/Retropie/tmp/upgrade_stack
  rm ~/Retropie/tmp/upgrade_stack
}

#######################################
# Start upgrade to current script version.
#
# Globals:
#   None
# Arguments:
#   $1 - Text to be displayed
# Returns:
#   None
#######################################
function upgrade_retrosmc(){
  "${1}" "Upgrading retrosmc"

  # To bind a new version it is recommended to create a upgrade function for
  # that starting version. E.g.
  #
  # function upgrade_to_version_1(){
  #   ... upgrade stuff
  # }
  #
  # If the example version 1 is obsolete a new upgrade function should be
  # created an that function should be called by upgrade_to_version_1 like
  # that:
  #
  # function upgrade_to_version_1(){
  #   ... upgrade stuff
  #   upgrade_to_version_2
  # }
  # function upgrade_to_version_2(){
  #   ... upgrade stuff
  # }
  #
  # A function can always push the execution of a command to the upgrade_stack
  # using `push_upgrade_stack`. This usage can be used to avoid redundant
  # execution of the same command.
  eval upgrade_to_version_"${SCRIPT_VERSION}" "${1}"
  execute_upgrade_stack
}
function upgrade_to_version_1(){
  if [[ -f ~/Retropie/var/version ]]; then
    "${1}" "Already on newest version"
  fi
  # TODO upgrade from previos retrosmc
}

#######################################
# Dialog infobox wrapper with only text argument.
#
# Globals:
#   None
# Arguments:
#   $1 - Text to be displayed
# Returns:
#   None
#######################################
function dialog_info(){
  dialog --infobox "${1}" 20 70
}

function main(){
  local INSTALL_RETROPIE=false
  local INSTALL_PLUGIN=false
  local CLI_USED=false

  if (( $(id -u) == 0 )); then
    echo This script should be used as user
    exit 1
  fi

  # execution without interface
  while (( $# > 0 )); do
    case $1 in
      --install-retropie)
        INSTALL_RETROPIE=true
        CLI_USED=true
        ;;
      --install-plugin)
        INSTALL_PLUGIN=true
        CLI_USED=true
        ;;
      --help|-h)
        usage
        exit 1
        ;;
      --upgrade-retrosmc)
        # undocumented function because it is mainly an internal function of
        # this script.
        upgrade_retrosmc dialog_info
        ;;
      *)
        echo Unknown option $1
        usage
        exit 1
    esac
    shift
  done

  if [[ $INSTALL_RETROPIE == true ]]; then
    install_retropie echo
  fi
  if [[ $INSTALL_PLUGIN == true ]]; then
    install_plugin echo
  fi
  if [[ $CLI_USED == true ]]; then
    exit 0
  fi

  dialog > /dev/null
  if [[ $? == 127 ]]; then
    echo Installing dialog framework first
    sudo apt-get install dialog -y
  fi

  dialog --msgbox "This is a script by mcobit to install retrosmc to OSMC.  I \
  am not responsible for any harm done to your system.  Using this is on your \
  own risk." 20 60

  start_joy2key

  while true; do
    options=(
      1 "Install retropie"
      2 "Install retropie plugin for kodi"
    )
    if [[ -d ~/.kodi/addons/plugin.program.retrosmc-launcher ]]; then
      options+=(3 "Remove retropie plugin for kodi")
    fi
    if [[ -f ~/Retropie/var/version ]]; then
      options+=(4 "Update retrosmc")
    fi
    menu_choice_f=$(mktemp)

    dialog \
      --backtitle "Retrosmc installation" \
      --title Menu \
      --cancel-label Exit \
      --menu "Please select:" 20 60 4 \
      "${options[@]}" 2> "${menu_choice_f}"

    if (( $? >= 1 )); then
      exit 0
    fi

    choice=$(<"${menu_choice_f}")
    case $choice in
      1)
        install_retropie dialog_info
        ;;
      2)
        install_plugin dialog_info
        ;;
      3)
        remove_plugin dialog_info
        ;;
      4)
        update_retrosmc dialog_info
        ;;
    esac
    rm "${menu_choice_f}"
  done

}

# Execute main if script not sourced. This leaves the option for other scripts
# to use this script as library and should make it more easy to test new
# functions outsite the required environment.
[[ "${BASH_SOURCE[0]}" != "${0}" ]] || main "$@"
