#!/usr/bin/env bash
# Sets up Ollama and a local model for NoHands natural-language commands.
# Usage: Scripts/setup-local-model.sh [model]
set -euo pipefail

URL="http://127.0.0.1:11434"

if [ $# -ge 1 ] && [ -n "$1" ]; then
  MODEL="$1"
else
  MEM_BYTES="$(sysctl -n hw.memsize)"
  # Same default as AppConfig.defaultLocalModel: 7B at >= 12 GB, else 3B.
  if [ "$MEM_BYTES" -ge $((12 * 1024 * 1024 * 1024)) ]; then
    MODEL="qwen2.5:7b-instruct"
  else
    MODEL="qwen2.5:3b-instruct"
  fi
fi

INSTALLED_BY_BREW=0
if ! command -v ollama >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    echo "Installing Ollama with Homebrew..."
    brew install ollama
    INSTALLED_BY_BREW=1
  else
    echo "Install Ollama from https://ollama.com/download, then re-run this script."
    exit 1
  fi
elif command -v brew >/dev/null 2>&1 && brew list --formula ollama >/dev/null 2>&1; then
  INSTALLED_BY_BREW=1
fi

if ! curl -sf "$URL/api/tags" >/dev/null 2>&1; then
  echo "Starting Ollama..."
  if [ "$INSTALLED_BY_BREW" -eq 1 ]; then
    brew services start ollama
  else
    open -a Ollama
  fi
  for _ in $(seq 1 30); do
    if curl -sf "$URL/api/tags" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
  if ! curl -sf "$URL/api/tags" >/dev/null 2>&1; then
    echo "Ollama did not start within 30 seconds." >&2
    exit 1
  fi
fi

echo "Pulling $MODEL (this can take a while)..."
ollama pull "$MODEL"

echo "Running a smoke test..."
curl -sf "$URL/api/chat" -d '{"model":"'"$MODEL"'","messages":[{"role":"user","content":"Reply with OK"}],"stream":false}' >/dev/null

echo "Ready. NoHands will use $MODEL when no anthropicAPIKey is set (or set \"intentBackend\": \"local\")."
