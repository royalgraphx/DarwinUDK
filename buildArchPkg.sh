#!/bin/bash

###############################################################################
# This script is licensed under the BSD 3-Clause License.
# For details, see the LICENSE file in the root of this repository.
###############################################################################

clear

# Enable debug mode if needed
DEBUG="TRUE"

# Function to print debug messages with color
# Usage: debug "message" "color"
debug() {
    local message=$1
    local color=$2

    if [ "$DEBUG" == "TRUE" ]; then
        case $color in
            "green")
                echo -e "\e[32mDEBUG: $message\e[0m"
                ;;
            "yellow")
                echo -e "\e[33mDEBUG: $message\e[0m"
                ;;
            "red")
                echo -e "\e[31mDEBUG: $message\e[0m"
                ;;
            "blue")
                echo -e "\e[94mDEBUG: $message\e[0m"
                ;;
            *)
                echo -e "\e[32mDEBUG: $message\e[0m" # Default to green if no color is specified
                ;;
        esac
    fi
}

# Function to print info messages
info() {
    # Light lavender color for info messages
    echo -e "\e[38;5;183mINFO: $1\e[0m"
}

# Get the current directory
CURRENT_DIR=$(pwd)
debug "Current directory is $CURRENT_DIR" "green"

# Trim the path to end at 'DarwinUDK/'
DUDK_ROOT=$(echo "$CURRENT_DIR" | sed 's|\(.*DarwinUDK\)/.*|\1|')
debug "DUDK_ROOT is set to $DUDK_ROOT" "green"

# Define Pkg Root variables
PKG_ROOT="$DUDK_ROOT/Package/Arch"
debug "PKG_ROOT is set to $PKG_ROOT" "green"

# Define Build variables
BUILD_DIR="$DUDK_ROOT/Build/OvmfX64/RELEASE_GCC/FV"
debug "BUILD_DIR is set to $BUILD_DIR" "blue"

CODE_COMPILED="$BUILD_DIR/OVMF_CODE.fd"
VARS_COMPILED="$BUILD_DIR/OVMF_VARS.fd"
debug "CODE_COMPILED is set to $CODE_COMPILED" "blue"
debug "VARS_COMPILED is set to $VARS_COMPILED" "blue"

# Define Pkg variables
PKG_DIR="$DUDK_ROOT/Package/Arch/src/pkg/usr/share/DarwinUDK/x64"
debug "PKG_DIR is set to $PKG_DIR" "yellow"

CODE_PKG="$PKG_DIR/DUDK_CODE.fd"
VARS_PKG="$PKG_DIR/DUDK_VARS.fd"
debug "CODE_PKG is set to $CODE_PKG" "yellow"
debug "VARS_PKG is set to $VARS_PKG" "yellow"

# Check if the necessary environment variables are set
if env | grep -q -E '^CONF_PATH=.*DarwinUDK.*$'; then
    # If the CONF_PATH variable with DarwinUDK in it is found, print a message indicating that the configuration is already loaded
    debug "Configuration is already loaded"
else
    # If the CONF_PATH variable is not found or doesn't contain DarwinUDK, print a message and run the command to load the configuration
    info "Environment variables are missing or not configured properly, running command to load configuration"
    # Run the command to load the configuration
    . ./edksetup.sh
fi

# Build the OvmfPkg
info "Building OvmfPkg..."
output=$(build -a X64 -b RELEASE -t GCC -p OvmfPkg/OvmfPkgX64.dsc -D LINUX_LOADER 2>&1)
# Capture the exit code of the build command
exit_code=$?

# Check if the build was successful
if [ $exit_code -eq 0 ]; then
    # If the build was successful, print a message indicating success
    info "OvmfPkg compiled successfully"
    
    # Check if CODE_COMPILED exists
    if [ -f "$CODE_COMPILED" ]; then
        debug "CODE_COMPILED file exists: $CODE_COMPILED" "green"
        # Copy and overwrite CODE_PKG with CODE_COMPILED
        cp -f "$CODE_COMPILED" "$CODE_PKG"
        debug "CODE_PKG updated with newly built CODE_COMPILED" "green"
    else
        echo "Error: CODE_COMPILED file does not exist: $CODE_COMPILED"
        exit 1
    fi
    
    # Check if VARS_COMPILED exists
    if [ -f "$VARS_COMPILED" ]; then
        debug "VARS_COMPILED file exists: $VARS_COMPILED" "green"
        # Copy and overwrite VARS_PKG with VARS_COMPILED
        cp -f "$VARS_COMPILED" "$VARS_PKG"
        debug "VARS_PKG updated with newly built VARS_COMPILED" "green"
    else
        echo "Error: VARS_COMPILED file does not exist: $VARS_COMPILED"
        exit 1
    fi
else
    # If the build failed, print the output of the build command and exit with an error message
    echo "Error: OvmfPkg compilation failed"
    echo "$output"
    exit 1
fi

# Change the working directory to PKG_ROOT
cd "$PKG_ROOT" || { echo "Error: Unable to change directory to $PKG_ROOT"; exit 1; }
debug "Changed working directory to $PKG_ROOT" "green"

# Check if the 'pkg' folder exists in PKG_ROOT
if [ -d "$PKG_ROOT/pkg" ]; then
    # If 'pkg' folder exists, remove it
    info "Removing existing 'pkg' folder..."
    rm -rf "$PKG_ROOT/pkg" || { echo "Error: Failed to remove 'pkg' folder"; exit 1; }
    debug "'pkg' folder removed successfully" "green"
else
    # If 'pkg' folder does not exist, print a message indicating it
    debug "'pkg' folder does not exist" "yellow"
fi

# Update pkgver variable in PKGBUILD file
pkgbuild_file="PKGBUILD"

if [ -f "$pkgbuild_file" ]; then
    # If PKGBUILD file exists, update pkgver variable
    current_pkgver=$(awk -F "=" '/pkgver=/ {print $2}' "$pkgbuild_file" | tr -d '[:space:]')
    new_pkgver="1.0.$(( ${current_pkgver##*.} + 1 ))" # Increment the last part of the version number
    sed -i "s/pkgver=$current_pkgver/pkgver=$new_pkgver/" "$pkgbuild_file" || { echo "Error: Failed to update pkgver variable in $pkgbuild_file"; exit 1; }
    info "Updated pkgver variable in $pkgbuild_file to $new_pkgver" "green"
else
    # If PKGBUILD file does not exist, print an error message
    echo "Error: PKGBUILD file does not exist in $PKG_ROOT"
    exit 1
fi

# Construct the command
makepkg_command="makepkg -f"

# Execute the command
info "Building package..."
makepkg_output=$(eval "$makepkg_command" 2>&1)
makepkg_exit_code=$?

# Check if the makepkg command was successful
if [ $makepkg_exit_code -eq 0 ]; then
    # If the command was successful, print a success message
    info "Package built successfully"
else
    # If the command failed, print the output and exit status
    echo "Error: Failed to build package"
    echo "$makepkg_output"
    
    # Handle different cases based on the exit status
    case $makepkg_exit_code in
        # Handle specific exit status codes if needed
        # For example:
        # 1) 127: Command not found
        # 2) 126: Permission denied
        *)
            # Default action for any other exit status
            echo "Error: Unexpected exit status $makepkg_exit_code"
            ;;
    esac

    # You can add more specific actions for different exit statuses if needed
fi

# Construct the pacman install command
pacman_command="sudo pacman -U DUDK-Firmware-${new_pkgver}-1-x86_64.pkg.tar.zst"

# Execute the pacman install command
info "Installing firmware package..."
$pacman_command

# Check if the installation was successful
if [ $? -eq 0 ]; then
    # If the installation was successful, print a success message
    info "Firmware package installed successfully"
else
    # If the installation failed, print an error message
    echo "Error: Failed to install firmware package"
    exit 1
fi

# Clean-up of pkg folder created while building pkg

# Check if the 'pkg' folder exists in PKG_ROOT
if [ -d "$PKG_ROOT/pkg" ]; then
    # If 'pkg' folder exists, remove it
    debug "Removing existing 'pkg' folder..." "green"
    rm -rf "$PKG_ROOT/pkg" || { echo "Error: Failed to remove 'pkg' folder"; exit 1; }
    debug "'pkg' folder removed successfully" "green"
else
    # If 'pkg' folder does not exist, print a message indicating it
    debug "'pkg' folder does not exist" "yellow"
fi

info "END OF LINE."
