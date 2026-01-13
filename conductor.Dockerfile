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
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 20
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install Claude Code CLI globally (v1.1.0+)
RUN npm install -g @anthropic-ai/claude-code

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

# Switch back to root for final setup
USER root

# Create workspace
RUN mkdir -p /workspace && chown user:user /workspace

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
