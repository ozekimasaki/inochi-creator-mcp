import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { runTool } from "./common.js";

export function registerHistoryTools(server: McpServer): void {
  server.tool(
    "creator_undo",
    "Undo the last Inochi Creator action.",
    async () => runTool("undo"),
  );

  server.tool(
    "creator_redo",
    "Redo the last undone Inochi Creator action.",
    async () => runTool("redo"),
  );
}
