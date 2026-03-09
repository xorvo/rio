#!/bin/bash
# Script to start Phoenix with SQLite backend in dev mode.
# Inherits the user's shell environment so asdf/mise shims are available.

set -e

# Source shell profile for asdf/mise
if [ -f "$HOME/.zshrc" ]; then
  source "$HOME/.zshrc" 2>/dev/null || true
elif [ -f "$HOME/.bashrc" ]; then
  source "$HOME/.bashrc" 2>/dev/null || true
fi

# Navigate to the project root (parent of native/)
cd "$(dirname "$0")/../.."

export WORK_TREE_DESKTOP=true
export PHX_SERVER=true
# PORT is passed in from the launcher
export PORT="${PORT:-4000}"

exec mix phx.server
