import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { runTool } from "./common.js";

export function registerStatusTools(server: McpServer): void {
  server.tool(
    "creator_ping",
    "Check that a patched Inochi Creator instance is reachable on localhost.",
    async () => runTool("ping"),
  );

  server.tool(
    "creator_get_status",
    "Get the current Inochi Creator project path, edit mode, selection, armed parameter, and undo state.",
    async () => runTool("get_status"),
  );

  server.tool(
    "creator_set_edit_mode",
    "Switch Inochi Creator edit mode. Use model, vertex, anim, or test.",
    {
      mode: z.enum(["model", "vertex", "anim", "test"]).describe("Target edit mode"),
    },
    async ({ mode }) => runTool("set_edit_mode", { mode }),
  );
}
