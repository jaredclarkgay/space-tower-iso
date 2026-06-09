#!/usr/bin/env bash
# Builder Agent session-capture hook.
#
# Wired up in .claude/settings.json to fire on:
#   - SessionEnd matcher=clear  (user runs /clear)
#   - PreCompact  matcher=auto  (context auto-compacts)
#
# Receives JSON on stdin from Claude Code with session_id, transcript_path,
# and cwd. Backgrounds a Claude headless run that distills takeaways into
# agent/session_log.md, agent/failure_log.json, agent/rules/, and
# agent/competency_map.json. The hook itself returns in milliseconds so
# /clear isn't blocked.
#
# The capture run only fires if there's been at least one commit since the
# last agent/ update — nothing to summarise on a no-op session.

set -euo pipefail

INPUT="$(cat)"
TRANSCRIPT_PATH="$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)"

# Bail unless we're inside the iso prototype repo. Other projects can wire
# their own capture script with their own filter.
case "$CWD" in
    *space-tower-iso*) ;;
    *) exit 0 ;;
esac

cd "$CWD" || exit 0

# Skip if there's nothing new to capture. The reference point is the most
# recent commit that touched anything under agent/; if no other commits
# have landed since then, the session was either empty or already captured.
LAST_AGENT_COMMIT="$(git log --format='%H' -n 1 -- agent/ 2>/dev/null || true)"
if [ -n "$LAST_AGENT_COMMIT" ]; then
    NEW_COMMITS="$(git log --oneline "${LAST_AGENT_COMMIT}..HEAD" 2>/dev/null | wc -l | tr -d ' ')"
    if [ "$NEW_COMMITS" = "0" ]; then
        exit 0
    fi
fi

# Bail if claude isn't on PATH (e.g. shell init didn't load the alias).
command -v claude >/dev/null 2>&1 || exit 0

PROMPT="Capture takeaways from this session into the Builder Agent files in agent/.

Steps:
1. Read the tail of agent/session_log.md, agent/competency_map.json (last_updated + version),
   and agent/failure_log.json (existing F-NNN ids) so you don't duplicate.
2. Run 'git log --oneline -30' and 'git diff --stat \${LAST_AGENT_COMMIT}..HEAD' to see what
   was committed since the last agent/ update at \$LAST_AGENT_COMMIT.
3. For genuinely new and non-obvious takeaways, append:
   - New failure entries to agent/failure_log.json (next F-NNN id; trigger + fix + rule_added)
   - A new Session entry at the bottom of agent/session_log.md summarising what landed
   - A new agent/rules/*.md ONLY if a pattern is reusable across future projects
   - Confidence shifts in agent/competency_map.json (bump version + last_updated)
4. Capture only what is NEW and NON-OBVIOUS. Skip routine bug fixes, formatting, dependency
   bumps, and anything derivable from reading the current code or git history.
5. Refresh STATUS.md (repo root) — the always-current human-readable snapshot. Re-derive it
   from the CODE + git log (not from the old STATUS.md prose), keeping its existing section
   shape: the one-liner, tech/shape, architecture, the floor table, the GameDirector.Phase
   arc, 'What just shipped' (this session), the open question, and the two 'Next move'
   sections (Playable / Agentic). Update the 'Last refreshed' line to today + the session.
   Trust order is code > git log > session_log > STATUS.md; if prose disagrees with code,
   rewrite the prose. Only change lines the work actually moved — don't churn the file.
6. Stage the agent/ files AND STATUS.md. Single 'chore(agent): capture session takeaways'
   commit. Do NOT push — the operator pushes manually after review.
7. Be terse. This runs unattended.

Transcript for reference: $TRANSCRIPT_PATH"

LOG_FILE="/tmp/agent-capture-$(date +%s)-$$.log"

# Background the capture so the hook itself returns immediately. Claude
# may take 30+ s to read the transcript, diff the repo, write files, and
# commit; we don't want /clear blocked behind that.
nohup claude -p "$PROMPT" --dangerously-skip-permissions \
    > "$LOG_FILE" 2>&1 &
disown

exit 0
