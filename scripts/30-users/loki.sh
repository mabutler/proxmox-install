#!/usr/bin/env bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then 
   echo "This script must be run as root"
   exit 1
fi

USERNAME="loki"
USER_HOME="/home/$USERNAME"

echo "=== Creating Media Management User: $USERNAME ==="
echo

# Check if user already exists
if id "$USERNAME" &>/dev/null; then
    echo "User '$USERNAME' already exists"
    echo "User ID: $(id -u $USERNAME)"
    echo "Home directory: $USER_HOME"
else
    echo "Creating user '$USERNAME'..."
    
    # Create user with nologin shell and home directory
    useradd -r -m -s /usr/sbin/nologin -c "Media Management User" "$USERNAME"
    
    echo "✓ User '$USERNAME' created"
    echo "  UID: $(id -u $USERNAME)"
    echo "  GID: $(id -g $USERNAME)"
    echo "  Home: $USER_HOME"
fi

echo
echo "Setting up directories..."

# Create necessary directories
mkdir -p "$USER_HOME/.ssh"
mkdir -p "$USER_HOME/.local/bin"
mkdir -p "$USER_HOME/.local/log"
mkdir -p "$USER_HOME/.config/rclone"

# Set proper ownership
chown -R "$USERNAME:$USERNAME" "$USER_HOME"
chmod 700 "$USER_HOME/.ssh"

echo "✓ Directories set up and ownership assigned to '$USERNAME'"
