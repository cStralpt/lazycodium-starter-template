#!/bin/sh
# Publishes one Claude agent's state where Neovim can see it.
#
# Called by Claude Code hooks (see hooks.settings.json next to this file) with
# the status word as its first argument. Everything it needs to know about
# WHICH agent it is comes from $TMUX_PANE, which hooks inherit from the Claude
# process, which inherited it from the tmux pane it runs in -- the same pane id
# (%17) util/claude_agents.lua already uses as an agent's real identity. That
# inheritance is the whole trick: no session-id mapping, no registry, no
# handshake between Claude and Neovim.
#
# Status arrives as an ARGUMENT rather than being read out of the JSON, because
# the hook config already knows which event it wired up. Only the events that
# carry something we cannot know otherwise -- the prompt text and the
# permission mode -- pay for a `jq` parse, and they are the once-per-turn ones.
#
# Not in a tmux pane = not an agent this workspace can address, so do nothing.
# That is the normal case for a Claude run in a plain terminal.
[ -n "$TMUX_PANE" ] || exit 0

dir="${XDG_RUNTIME_DIR:-/tmp}/nvim-claude-agents"
mkdir -p "$dir" 2>/dev/null || exit 0
file="$dir/${TMUX_PANE#%}"

status="$1"

if [ "$status" = "gone" ]; then
  rm -f "$file"
  exit 0
fi

# Carry the previous record forward: most events know one field and must not
# blank the others. `mode` and `task` in particular are set once per turn and
# have to survive the run of PostToolUse reports that follows.
prev_status="" since="" mode="" task="" reply=""
if [ -r "$file" ]; then
  while IFS='=' read -r k v; do
    case "$k" in
      status) prev_status=$v ;;
      since) since=$v ;;
      mode) mode=$v ;;
      task) task=$v ;;
      reply) reply=$v ;;
    esac
  done <"$file"
fi

# `since` is when the CURRENT state began, not when it was last reported. The
# distinction is the whole value of the number: PostToolUse fires continuously
# while Claude works, and resetting the clock on each one would pin every agent
# at "0s" forever -- exactly hiding the agent that has been stuck for 14
# minutes, which is the one you wanted to find.
if [ "$status" != "$prev_status" ] || [ -z "$since" ]; then
  since=$(date +%s)
fi

if [ "$2" = "parse" ]; then
  # One jq invocation covers both parsing events. UserPromptSubmit carries
  # `.prompt`, Stop carries `.last_assistant_message`, and each leaves the
  # other's field absent -- so a single extraction plus "only overwrite what
  # came back non-empty" does the job without the script knowing which event
  # it is. Failure (no jq, malformed input) leaves everything as it was; a
  # stale label beats no label.
  fields=$(jq -r '[(.prompt // ""), (.permission_mode // ""), (.last_assistant_message // "")] | @tsv' 2>/dev/null)
  if [ -n "$fields" ]; then
    new_task=$(printf '%s' "$fields" | cut -f1 | cut -c1-160)
    new_mode=$(printf '%s' "$fields" | cut -f2)
    new_reply=$(printf '%s' "$fields" | cut -f3 | cut -c1-160)
    [ -n "$new_mode" ] && mode=$new_mode
    if [ -n "$new_task" ]; then
      # A prompt means a new turn has started, so last turn's reply is stale.
      # Clearing it here is what keeps "done -> show the answer" honest: the
      # answer on screen always belongs to the task next to it.
      task=$new_task
      reply=""
    fi
    [ -n "$new_reply" ] && reply=$new_reply
  fi
fi

# Write-then-rename: Neovim watches this directory with an fs_event and reads a
# file the instant it is told about it. A plain redirect would let it observe
# the truncated file mid-write.
tmp="$file.tmp$$"
{
  printf 'status=%s\n' "$status"
  printf 'since=%s\n' "$since"
  printf 'mode=%s\n' "$mode"
  printf 'task=%s\n' "$task"
  printf 'reply=%s\n' "$reply"
} >"$tmp" 2>/dev/null && mv -f "$tmp" "$file" 2>/dev/null

exit 0
