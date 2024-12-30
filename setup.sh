#!/bin/bash

# Install Starship prompt
echo "Installing Starship prompt..."
if command -v starship > /dev/null 2>&1; then
  echo "Starship is already installed. Skipping..."
else
  curl -sS https://starship.rs/install.sh | sh && echo "Starship installed successfully." || echo "Failed to install Starship."
fi

# File containing package names
PACKAGES_FILE="packages.txt"

# Check if the packages file exists
if [ ! -f "$PACKAGES_FILE" ]; then
  echo "Error: $PACKAGES_FILE not found."
  exit 1
fi

# Update package list
echo "Updating package list..."
sudo apt update -y

# Install packages
while IFS= read -r package || [[ -n "$package" ]]; do
  if dpkg -l | grep -q "^ii  $package"; then
    echo "$package is already installed. Skipping..."
  else
    echo "Installing $package..."
    sudo apt install -y "$package" && echo "$package installed successfully." || echo "Failed to install $package."
  fi
done < "$PACKAGES_FILE"

# Run stow
echo "Running 'stow .' in the current directory..."
if stow .; then
  echo "'stow .' completed successfully."
else
  echo "Failed to run 'stow .'. Please check for errors."
fi

echo "Script completed."
