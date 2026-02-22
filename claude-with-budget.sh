#!/bin/bash
# Claude Code CLI Budget Wrapper
# Automatically applies token budget limits to prevent runaway costs
# Only applies in non-interactive (--print) mode

# Determine which budget limit to use based on template type
# Priority: Specific template env var > Generic worker env var > Default
if [ -n "$CONDUCTOR_MAX_BUDGET_USD" ]; then
    MAX_BUDGET="${CONDUCTOR_MAX_BUDGET_USD}"
elif [ -n "$INFRASTRUCTURE_MAX_BUDGET_USD" ]; then
    MAX_BUDGET="${INFRASTRUCTURE_MAX_BUDGET_USD}"
else
    MAX_BUDGET="${WORKER_MAX_BUDGET_USD:-5.00}"
fi

# Check if budget limiting is explicitly disabled
if [ "$MAX_BUDGET" = "disabled" ] || [ "$MAX_BUDGET" = "0" ]; then
    # Budget limits disabled - pass through to real Claude CLI
    exec /usr/bin/claude "$@"
fi

# Check if running in non-interactive mode (--print or -p flag)
# Budget limits only apply to non-interactive mode
if [[ "$*" == *"--print"* ]] || [[ "$*" == *"-p"* ]]; then
    # Check if budget flag already provided by user
    if [[ "$*" != *"--max-budget-usd"* ]]; then
        # Add budget limit automatically
        exec /usr/bin/claude "$@" --max-budget-usd "$MAX_BUDGET"
    else
        # User provided their own budget - respect it
        exec /usr/bin/claude "$@"
    fi
else
    # Interactive mode - no automatic budget limiting
    # (users need control in interactive sessions)
    exec /usr/bin/claude "$@"
fi
