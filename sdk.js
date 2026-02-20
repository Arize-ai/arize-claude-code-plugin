"use strict";

const path = require("path");

const HOOKS_DIR = path.resolve(__dirname, "plugins", "claude-code-tracing", "hooks");

const HOOK_NAMES = [
  "session_start",
  "user_prompt_submit",
  "pre_tool_use",
  "post_tool_use",
  "stop",
  "subagent_stop",
  "notification",
  "permission_request",
  "session_end",
];

function makeHookEntry(scriptName) {
  return [{ hooks: [{ type: "command", command: `bash "${path.join(HOOKS_DIR, scriptName)}.sh"` }] }];
}

/**
 * Returns the hooks configuration object for use with the Claude Code Agent SDK.
 *
 * Pass the result directly to the `hooks` option when calling `claude()`:
 *
 *   const { claude } = require("@anthropic-ai/claude-code");
 *   const { getTracingHooks } = require("arize-claude-code-plugin");
 *
 *   const result = await claude("your prompt", {
 *     hooks: getTracingHooks(),
 *   });
 *
 * Environment variables (PHOENIX_ENDPOINT, ARIZE_API_KEY, etc.) must be set in
 * the process environment before invoking claude().
 */
function getTracingHooks() {
  return {
    SessionStart: makeHookEntry("session_start"),
    UserPromptSubmit: makeHookEntry("user_prompt_submit"),
    PreToolUse: makeHookEntry("pre_tool_use"),
    PostToolUse: makeHookEntry("post_tool_use"),
    Stop: makeHookEntry("stop"),
    SubagentStop: makeHookEntry("subagent_stop"),
    Notification: makeHookEntry("notification"),
    PermissionRequest: makeHookEntry("permission_request"),
    SessionEnd: makeHookEntry("session_end"),
  };
}

/**
 * Returns the absolute path to the hooks directory.
 * Useful if you need to construct custom hook commands.
 */
function getHooksDir() {
  return HOOKS_DIR;
}

module.exports = { getTracingHooks, getHooksDir };
