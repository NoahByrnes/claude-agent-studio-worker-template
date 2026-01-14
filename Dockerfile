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

# Install AWS CLI for S3 storage support
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip" \
    && unzip -q /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/awscliv2.zip /tmp/aws

# Install Node.js dependencies for storage helpers
RUN npm install -g node-fetch@2 form-data

# Create workspace directory
RUN mkdir -p /workspace

# Copy persistent storage helpers
COPY persist-result.sh /usr/local/bin/persist-result
COPY persist-result.js /usr/local/bin/persist-result.js
RUN chmod +x /usr/local/bin/persist-result /usr/local/bin/persist-result.js

# Verify installations
RUN node --version && npm --version && claude --version

# Set working directory
WORKDIR /workspace

# Default command
CMD ["bash"]
