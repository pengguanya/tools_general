#!/bin/bash
# aiconf - git wrapper for AI configuration repo (~/.ai-config.git)
# Replaces the shell alias: alias aiconf='git --git-dir=$HOME/.ai-config.git --work-tree=$HOME'
# Works in non-interactive shells (Claude Code, cron, ssh commands)

exec git --git-dir="$HOME/.ai-config.git" --work-tree="$HOME" "$@"
