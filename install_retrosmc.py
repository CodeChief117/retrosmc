#!/usr/bin/env python3
"""Retropie installation script for osmc."""
import argparse
import locale
import os
import shutil
import subprocess
import sys
from os import path

locale.setlocale(locale.LC_ALL, '')

deps = (
    "dialog",
    "git",
    "pv",
    "bzip2",
    "psmisc",
    "libusb-1.0",
    "alsa-utils",
)

installer_path = path.expanduser("~/Retropie")
installer_repo = "https://github.com/mcobit/retrosmc.git"
retropie_setup = path.expanduser("~/Retropie-Setup")
plugin_folder = path.expanduser("~/.kodi/addons/plugin.program.retrosmc-launcher")

es_input_cfg = """
<?xml version="1.0"?>
<inputList>
  <inputAction type="onfinish">
    <command>/opt/retropie/supplementary/emulationstation/scripts/inputconfiguration.sh</command>
  </inputAction>
</inputList>
"""


def _silent_check_call(cmd):
    """Executes cmd and returns exit code."""
    return subprocess.check_call(cmd,
                                 stdout=subprocess.DEVNULL,
                                 stderr=subprocess.DEVNULL)


def _silent_call(cmd):
    """Executes cmd and returns exit code."""
    return subprocess.call(cmd,
                           stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL)


def grep(file, search: str):
    """Simple slow single line search."""
    with open(file, "r") as f:
        for l in f:
            if search in l:
                return True
    return False


def _install_retropie():
    try:
        _silent_check_call(
            ["git", "clone", "https://github.com/RetroPie/RetroPie-Setup.git",
             retropie_setup]
        )

        os.chdir(retropie_setup)
        _silent_check_call(["./retropie_setup.sh"])

        es_input = path.expanduser("~/.emulationstation/es_input.cfg")
        with open(es_input, "a") as f:
            f.write(es_input_cfg)
    except subprocess.CalledProcessError:
        pass
    except OSError:  # config cannot be written
        pass


def _install_integration():
    if _silent_call(["git", "status"]) > 0:
        try:
            _silent_check_call(
                ["git", "clone", installer_repo, installer_path]
            )
        except subprocess.CalledProcessError:
            pass


def install(signal):
    """Install retropie on current machine.

    .. todo::

        Append "dtparam=audio=on" if nessesary during the installation process.
        After that set the audio to 100% via::

            $ amixer set PCM 100

    Args:
        signal: Function with one string parameter. The string can be used to
        notify the user what the current action is.

        installer_repo: Repository URI from where the installer and related
        files should be cloned using git. This repository does not get used if
        this script is already part of a git repository.
    """
    signal("Installing dependencies")
    try:
        _silent_check_call(["sudo", "apt-get", "update"])
        _silent_check_call(["sudo", "apt-get", "install", *deps])
    except subprocess.CalledProcessError:
        pass

    _install_retropie()
    _install_integration(installer_repo)

    try:
        signal("Starting mediacenter again")
        _silent_check_call(["sudo",
                            "systemctl", "start", "mediacenter.service"])
    except subprocess.CalledProcessError:
        pass


def install_plugin(signal):
    if path.isdir(plugin_folder):
        remove_plugin(signal)

    os.chdir(retropie_setup)
    shutil.copy("plugin.program.retrosmc-launcher", plugin_folder)


def remove_plugin(signal):
    shutil.rmtree(plugin_folder)


def quit_for_good(signal):
    exit(0)


def menu():
    """Builder for menu and menu handler."""
    choice_action = [
        ("Install Retropie", install),
        ("Install Kodi plugin", install_plugin),
    ]
    if path.isdir(plugin_folder):
        choice_action.append(("Remove Kodi plugin", remove_plugin))
    choice_action.append("Quit", quit_for_good)

    choices = []
    actions = {}
    for idx, (label, action) in enumerate(choice_action):
        choices.append((str(idx), label))
        actions[str(idx)] = action

    return choices, actions


def main():
    """Main function with basic checks and UI."""
    parser = argparse.ArgumentParser()
    parser.add_argument("--install-plugin",
                        type="store_true",
                        help="Install kodi plugin.")
    parser.add_argument("--install-retropie",
                        type="store_true",
                        help="Install retropie")

    if os.getuid() > 0:
        print("This script should be started as user instead of root.",
              file=sys.stderr)
        exit(1)

    args = parser.parse_args()

    if args.install_plugin:
        install_plugin(print)
    if args.install_retropie:
        install(print)

    if not (args.install_plugin or args.install_retropie):
        # joy2key support
        d = dialog.Dialog()
        choices, actions = menu()
        code, tag = d.menu(
            "Select action",
            choices=choices,
        )
        if code == d.CANCEL:
            quit_for_good(d.infobox)
        actions[tag](d.infobox)


if __name__ == "__main__":
    main()
