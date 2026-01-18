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

# Install Playwright system dependencies for Chromium
RUN npx playwright@latest install-deps chromium

# Install Playwright for both Node.js and Python
RUN npx playwright@latest install chromium
RUN pip3 install --no-cache-dir playwright==1.40.0 python-dateutil==2.8.2 requests==2.31.0
RUN python3 -m playwright install chromium

# Install AWS CLI for S3 storage support
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip" \
    && unzip -q /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/awscliv2.zip /tmp/aws

# Install Node.js dependencies for storage helpers
RUN npm install -g node-fetch@2 form-data

# Python dependencies now installed above with Playwright

# Create workspace directory
RUN mkdir -p /workspace

# Copy persistent storage helpers
COPY persist-result.sh /usr/local/bin/persist-result
COPY persist-result.js /usr/local/bin/persist-result.js
RUN chmod +x /usr/local/bin/persist-result /usr/local/bin/persist-result.js

# Copy BC Ferries tools
COPY wait-for-ferry.py /usr/local/bin/wait-for-ferry
COPY bc_ferries_booking_modular.py /usr/local/lib/python3.10/dist-packages/
COPY bc-ferries-book.py /usr/local/bin/bc-ferries-book
COPY test-playwright.py /usr/local/bin/test-playwright
RUN chmod +x /usr/local/bin/wait-for-ferry /usr/local/bin/bc-ferries-book /usr/local/bin/test-playwright

# Verify installations
RUN node --version && npm --version && claude --version

# Set working directory
WORKDIR /workspace

# Default command
CMD ["bash"]
