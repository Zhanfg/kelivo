const SAFE_TOOLS = new Set([
  "read",
  "grep",
  "find",
  "ls",
  "lsp",
  "kelivo_plan",
]);
const sessionAllowed = new Set();
let approvedPlanFingerprint = null;

function planFingerprint(params) {
  const steps = Array.isArray(params?.steps) ? params.steps : [];
  return JSON.stringify(steps.map((step) => String(step?.text || "").trim()));
}

function summarize(event) {
  const input = event.input || {};
  if (event.toolName === "bash") return String(input.command || "bash");
  const path = input.path || input.file_path || input.filePath;
  if (path) return event.toolName + ": " + path;
  return event.toolName;
}

export default function (pi) {
  const z = pi.zod;

  pi.registerTool({
    name: "kelivo_plan",
    label: "Update plan",
    description:
      "Publish or update the visible KELIVO task plan. For multi-step work, call this before the first mutating action and whenever the plan materially changes.",
    parameters: z.object({
      summary: z.string().optional(),
      steps: z.array(
        z.object({
          text: z.string(),
          status: z.enum(["pending", "in_progress", "completed"]),
        }),
      ),
    }),
    async execute(_toolCallId, params, _onUpdate, ctx, _signal) {
      const mode = process.env.KELIVO_AGENT_PERMISSION_MODE || "ask";
      const fingerprint = planFingerprint(params);
      let approved = mode !== "planFirst";

      if (mode === "planFirst") {
        if (approvedPlanFingerprint === fingerprint) {
          approved = true;
        } else if (ctx.hasUI) {
          const summary = String(params?.summary || "").trim();
          const steps = Array.isArray(params?.steps) ? params.steps : [];
          const preview = [
            summary,
            ...steps.map(
              (step, index) =>
                `${index + 1}. ${String(step?.text || "").trim()}`,
            ),
          ]
            .filter(Boolean)
            .join("\n");

          const choice = await ctx.ui.select(
            `Approve Agent plan?\n${preview}`,
            ["Approve and implement", "Keep planning", "Do not implement"],
          );
          approved = choice === "Approve and implement";
          if (approved) approvedPlanFingerprint = fingerprint;
        }

        if (!approved) {
          return {
            content: [
              {
                type: "text",
                text:
                  "The plan is visible in KELIVO but has not been approved for implementation. Continue read-only investigation or revise the plan.",
              },
            ],
            details: { ...params, approved: false },
          };
        }
      }

      return {
        content: [
          {
            type: "text",
            text: approved
              ? "Plan approved in KELIVO. Implementation may proceed."
              : "Plan updated in KELIVO.",
          },
        ],
        details: { ...params, approved },
      };
    },
  });

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

    if (mode === "planFirst") {
      if (approvedPlanFingerprint != null) return undefined;
      return {
        block: true,
        reason:
          "KELIVO Plan first mode requires an approved kelivo_plan before mutating tools can run",
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
      `Approve action: ${target}`,
      ["Allow once", "Always allow this tool", "Block"],
    );

    if (choice === "Always allow this tool") {
      sessionAllowed.add(tool);
      return undefined;
    }
    if (choice === "Allow once") return undefined;

    return { block: true, reason: "Blocked by user" };
  });
}
