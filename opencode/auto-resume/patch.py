#!/usr/bin/env python3
"""Patch opencode-auto-resume's bundled dist to add a `skipRootSessions` option.

When enabled, the plugin leaves non-subagent (root/main) sessions completely
alone: it never sends "continue"/recovery prompts and never aborts them. Subagent
sessions (sessions created with a parentID) keep the full recovery behavior.

Usage: patch.py path/to/dist/index.js
"""

import sys

path = sys.argv[1]
s = open(path).read()


def replace(old, new):
    global s
    count = s.count(old)
    assert count == 1, f"anchor not unique/found ({count}): {old.splitlines()[0][:70]!r}"
    s = s.replace(old, new)


replace(
    '  const busyStallStrategy = rawBusyStallStrategy === "abort" || rawBusyStallStrategy === "off" ? rawBusyStallStrategy : "continue";',
    '  const busyStallStrategy = rawBusyStallStrategy === "abort" || rawBusyStallStrategy === "off" ? rawBusyStallStrategy : "continue";\n'
    "  const skipRootSessions = options?.skipRootSessions === true;",
)

replace(
    "  async function sendContinuePrompt(sid, text, w) {",
    """  function isRootSkipped(w) {
    return skipRootSessions && !(w && w.isSubagent);
  }
  async function sendContinuePrompt(sid, text, w) {
    if (isRootSkipped(w)) {
      await log("debug", `${short(sid)} - skipRootSessions: leaving root session alone`);
      return;
    }""",
)

replace(
    "  async function tryAbortAndResume(sid, w) {",
    """  async function tryAbortAndResume(sid, w) {
    if (isRootSkipped(w))
      return false;""",
)

replace(
    '''          if (typeof sid !== "string" || !sid.startsWith("ses"))
            return;
          w.pluginAbortInFlight = true;''',
    '''          if (typeof sid !== "string" || !sid.startsWith("ses"))
            return;
          if (isRootSkipped(w))
            return;
          w.pluginAbortInFlight = true;''',
)

open(path, "w").write(s)
print("auto-resume patched: skipRootSessions option added")
