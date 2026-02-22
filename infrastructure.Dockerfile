# Infrastructure Worker Template
# Special E2B template for workers that can modify the worker template repository
# Includes: GitHub CLI, E2B CLI, Docker CLI, Git

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install base dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    unzip \
    jq \
    git \
    ca-certificates \
    gnupg \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 20
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install Claude Code CLI globally (v1.1.0+)
RUN npm install -g @anthropic-ai/claude-code

# Set default token budget for infrastructure workers
ENV INFRASTRUCTURE_MAX_BUDGET_USD=10.00

# Install token budget wrapper for Claude CLI
COPY claude-with-budget.sh /usr/local/bin/claude-with-budget
RUN chmod +x /usr/local/bin/claude-with-budget && \
    mv /usr/bin/claude /usr/bin/claude-real && \
    ln -s /usr/local/bin/claude-with-budget /usr/bin/claude

# Install Playwright system dependencies (for browser automation)
RUN npx playwright install-deps chromium || true

# INFRASTRUCTURE WORKER ADDITIONS:

# Install GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | \
    gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | \
    tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
    apt-get update && apt-get install -y gh && \
    rm -rf /var/lib/apt/lists/*

# Install E2B CLI
RUN npm install -g @e2b/cli

# Install Docker CLI and configure docker group access
RUN apt-get update && apt-get install -y docker.io && \
    rm -rf /var/lib/apt/lists/*

# Create docker group if it doesn't exist
RUN groupadd -f docker

# Configure sudo to allow docker commands without password
# This enables infrastructure workers to run: sudo usermod -aG docker $(whoami)
# E2B runs as 'user' by default, so we allow this user passwordless sudo for docker setup
RUN echo "user ALL=(ALL) NOPASSWD: /usr/sbin/usermod, /usr/sbin/groupadd, /usr/sbin/groupmod, /bin/chmod /var/run/docker.sock, /usr/bin/docker" >> /etc/sudoers.d/docker-access && \
    chmod 0440 /etc/sudoers.d/docker-access

# Install AWS CLI for S3 storage support
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip" \
    && unzip -q /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/awscliv2.zip /tmp/aws

# Install Node.js dependencies for storage helpers
RUN npm install -g node-fetch@2 form-data

# Git configuration for commits
RUN git config --global user.name "Claude Agent Studio Bot" && \
    git config --global user.email "bot@claude-agent-studio.dev"

# Create workspace directory
RUN mkdir -p /workspace

# Copy persistent storage helpers
COPY persist-result.sh /usr/local/bin/persist-result
COPY persist-result.js /usr/local/bin/persist-result.js
RUN chmod +x /usr/local/bin/persist-result /usr/local/bin/persist-result.js

# Copy Docker access initialization script
COPY init-docker-access.sh /usr/local/bin/init-docker-access
RUN chmod +x /usr/local/bin/init-docker-access

# Copy watchdog system for worker monitoring
COPY watchdog.sh /usr/local/bin/watchdog.sh
COPY watchdog-alert.sh /usr/local/bin/watchdog-alert.sh
COPY watchdog-setup.sh /usr/local/bin/watchdog-setup.sh
COPY heartbeat.sh /usr/local/bin/heartbeat.sh
RUN chmod +x /usr/local/bin/watchdog.sh /usr/local/bin/watchdog-alert.sh /usr/local/bin/watchdog-setup.sh /usr/local/bin/heartbeat.sh

# Create watchdog directories
RUN mkdir -p /tmp/watchdog /var/log/watchdog

# Verify installations
RUN node --version && npm --version && claude --version && gh --version && e2b --version

# Set working directory
WORKDIR /workspace

# Default command
CMD ["bash"]
