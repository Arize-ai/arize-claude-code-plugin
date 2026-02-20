interface HookCommand {
  type: "command";
  command: string;
}

interface HookMatcher {
  hooks: HookCommand[];
}

interface TracingHooks {
  SessionStart: HookMatcher[];
  UserPromptSubmit: HookMatcher[];
  PreToolUse: HookMatcher[];
  PostToolUse: HookMatcher[];
  Stop: HookMatcher[];
  SubagentStop: HookMatcher[];
  Notification: HookMatcher[];
  PermissionRequest: HookMatcher[];
  SessionEnd: HookMatcher[];
}

/**
 * Returns the hooks configuration object for use with the Claude Code Agent SDK.
 *
 * Pass the result directly to the `hooks` option when calling `claude()`:
 *
 * ```typescript
 * import { claude } from "@anthropic-ai/claude-code";
 * import { getTracingHooks } from "arize-claude-code-plugin";
 *
 * const result = await claude("your prompt", {
 *   hooks: getTracingHooks(),
 * });
 * ```
 *
 * Environment variables (`PHOENIX_ENDPOINT`, `ARIZE_API_KEY`, etc.) must be set
 * in the process environment before invoking `claude()`.
 */
export declare function getTracingHooks(): TracingHooks;

/**
 * Returns the absolute path to the hooks directory.
 * Useful if you need to construct custom hook commands.
 */
export declare function getHooksDir(): string;
