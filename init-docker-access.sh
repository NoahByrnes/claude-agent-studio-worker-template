#!/bin/bash
# Initialize Docker Access for Infrastructure Workers
# Run this once at the start of infrastructure worker session

set -e

echo "Initializing Docker access..."

# Add current user to docker group
CURRENT_USER=$(whoami)
sudo usermod -aG docker "$CURRENT_USER"

# Make docker socket writable (in case group membership isn't enough)
if [ -S /var/run/docker.sock ]; then
    sudo chmod 666 /var/run/docker.sock
fi

echo "✓ Docker access configured!"
echo ""
echo "You can now run Docker commands:"
echo "  docker ps"
echo "  e2b template build"
echo ""
