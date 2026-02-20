import { fileURLToPath } from "url";
import path from "path";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const HOOKS_DIR = path.resolve(__dirname, "plugins", "claude-code-tracing", "hooks");

function makeHookEntry(scriptName) {
  return [{ hooks: [{ type: "command", command: `bash "${path.join(HOOKS_DIR, scriptName)}.sh"` }] }];
}

/**
 * Returns the hooks configuration object for use with the Claude Code Agent SDK.
 *
 * Pass the result directly to the `hooks` option when calling `claude()`:
 *
 *   import { claude } from "@anthropic-ai/claude-code";
 *   import { getTracingHooks } from "arize-claude-code-plugin";
 *
 *   const result = await claude("your prompt", {
 *     hooks: getTracingHooks(),
 *   });
 *
 * Environment variables (PHOENIX_ENDPOINT, ARIZE_API_KEY, etc.) must be set in
 * the process environment before invoking claude().
 */
export function getTracingHooks() {
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
export function getHooksDir() {
  return HOOKS_DIR;
}
