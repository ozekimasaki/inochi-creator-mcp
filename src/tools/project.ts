import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { runTool } from "./common.js";

export function registerProjectTools(server: McpServer): void {
  server.tool(
    "creator_new_project",
    "Create a new empty Inochi Creator project. Discards the unsaved current project.",
    async () => runTool("new_project"),
  );

  server.tool(
    "creator_open_project",
    "Open an .inx (or compatible INP) project in the running Inochi Creator.",
    {
      path: z.string().min(1).describe("Absolute path to the .inx project"),
    },
    async ({ path }) => runTool("open_project", { path }),
  );

  server.tool(
    "creator_save_project",
    "Save the current project as .inx. If path is omitted, saves to the current project path.",
    {
      path: z.string().min(1).optional().describe("Absolute save path; .inx is appended if missing"),
    },
    async ({ path }) => runTool("save_project", path ? { path } : {}),
  );

  server.tool(
    "creator_export_inp",
    "Export the current puppet as a packed .inp file using default atlas settings. Does not open the export UI.",
    {
      path: z.string().min(1).describe("Absolute destination path for the .inp file"),
    },
    async ({ path }) => runTool("export_inp", { path }),
  );
}
