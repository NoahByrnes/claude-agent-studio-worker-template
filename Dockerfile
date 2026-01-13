# E2B Worker Template - Base Ubuntu environment for Claude Code CLI
FROM ubuntu:22.04

# Prevent interactive prompts during installation
ENV DEBIAN_FRONTEND=noninteractive

# Install essential tools
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    unzip \
    jq \
    git \
    ca-certificates \
    gnupg \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 20
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install Claude Code CLI globally (v1.1.0+)
RUN npm install -g @anthropic-ai/claude-code

# Install Playwright with Chromium browser (for browser automation)
RUN npx playwright@latest install-deps chromium
RUN npx playwright@latest install chromium

# Create workspace directory
RUN mkdir -p /workspace

# Verify installations
RUN node --version && npm --version && claude --version

# Set working directory
WORKDIR /workspace

# Default command
CMD ["bash"]
