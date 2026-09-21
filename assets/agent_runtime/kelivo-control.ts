const SAFE_TOOLS = new Set(["read", "grep", "find", "ls"]);
const sessionAllowed = new Set();

function summarize(event) {
  const input = event.input || {};
  if (event.toolName === "bash") return String(input.command || "bash");
  const path = input.path || input.file_path || input.filePath;
  if (path) return event.toolName + ": " + path;
  return event.toolName;
}

export default function (pi) {
  pi.on("tool_call", async (event, ctx) => {
    const mode = process.env.KELIVO_AGENT_PERMISSION_MODE || "ask";
    const tool = event.toolName;

    if (SAFE_TOOLS.has(tool)) return undefined;

    if (mode === "readOnly") {
      return {
        block: true,
        reason: "Blocked by KELIVO read-only permission mode",
      };
    }

    if (mode === "auto" || sessionAllowed.has(tool)) return undefined;

    if (!ctx.hasUI) {
      return {
        block: true,
        reason: "KELIVO approval UI is unavailable",
      };
    }

    const target = summarize(event);
    const choice = await ctx.ui.select(
      "Approve action",
      ["Allow once", "Always allow this tool", "Block"],
      { message: target },
    );

    if (choice === "Always allow this tool") {
      sessionAllowed.add(tool);
      return undefined;
    }
    if (choice === "Allow once") return undefined;

    return { block: true, reason: "Blocked by user" };
  });
}
