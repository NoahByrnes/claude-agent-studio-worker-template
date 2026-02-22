# Conductor Template - Stu's orchestration environment
# Based on standard worker template + claude-mem plugin for memory
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
    tzdata \
    cron \
    && rm -rf /var/lib/apt/lists/*

# Set default timezone (can be overridden with TZ environment variable)
ENV TZ=UTC
RUN ln -sf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Install Node.js 20
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install Claude Code CLI globally (v1.1.0+)
RUN npm install -g @anthropic-ai/claude-code

# Set default token budget for conductor (higher limit for orchestration tasks)
ENV CONDUCTOR_MAX_BUDGET_USD=20.00

# Install token budget wrapper for Claude CLI
COPY claude-with-budget.sh /usr/local/bin/claude-with-budget
RUN chmod +x /usr/local/bin/claude-with-budget && \
    mv /usr/bin/claude /usr/bin/claude-real && \
    ln -s /usr/local/bin/claude-with-budget /usr/bin/claude

# Install Node.js packages for timestamp utilities
RUN npm install -g \
    dayjs \
    moment-timezone

# Create user directories (E2B runs as 'user', not 'root')
RUN useradd -m -s /bin/bash user || true

# Install Bun runtime (required by claude-mem) as user
USER user
WORKDIR /home/user
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/home/user/.bun/bin:${PATH}"

# Install claude-mem plugin for persistent memory
RUN mkdir -p /home/user/.claude/plugins && \
    cd /home/user/.claude/plugins && \
    git clone https://github.com/thedotmack/claude-mem.git claude-mem && \
    cd claude-mem && \
    npm install && \
    npm run build

# Create data directory
RUN mkdir -p /home/user/.claude-mem

# Install Python packages for SMS/email handling with timestamp support
RUN pip3 install --no-cache-dir \
    twilio \
    sendgrid \
    python-dateutil \
    pytz \
    email-validator

# Switch back to root for final setup
USER root

# Create workspace
RUN mkdir -p /workspace && chown user:user /workspace

# Create cron log directory
RUN mkdir -p /var/log/conductor-cron && chown user:user /var/log/conductor-cron

# Copy cron scripts
COPY status-update.sh /usr/local/bin/status-update.sh
COPY setup-cron.sh /usr/local/bin/setup-cron.sh
RUN chmod +x /usr/local/bin/status-update.sh /usr/local/bin/setup-cron.sh

# Copy watchdog system for worker monitoring
COPY watchdog.sh /usr/local/bin/watchdog.sh
COPY watchdog-alert.sh /usr/local/bin/watchdog-alert.sh
COPY watchdog-setup.sh /usr/local/bin/watchdog-setup.sh
COPY heartbeat.sh /usr/local/bin/heartbeat.sh
RUN chmod +x /usr/local/bin/watchdog.sh /usr/local/bin/watchdog-alert.sh /usr/local/bin/watchdog-setup.sh /usr/local/bin/heartbeat.sh

# Create watchdog directories
RUN mkdir -p /tmp/watchdog /var/log/watchdog && chown user:user /var/log/watchdog

# Switch to user for runtime
USER user

# Verify installations
RUN node --version && \
    npm --version && \
    claude --version && \
    bun --version

# Set working directory
WORKDIR /workspace

# Default command
CMD ["bash"]
