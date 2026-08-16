import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { runTool } from "./common.js";

export function registerImportTools(server: McpServer): void {
  server.tool(
    "creator_import_psd",
    "Import a Photoshop .psd file as a new project. THIS REPLACES THE CURRENT PROJECT.",
    {
      path: z.string().min(1).describe("Absolute path to the .psd file"),
      keep_structure: z.boolean().optional().describe("Keep PSD folder structure (default false)"),
    },
    async (args) =>
      runTool("import_psd", {
        path: args.path,
        keep_structure: args.keep_structure ?? false,
      }),
  );

  server.tool(
    "creator_import_kra",
    "Import a Krita .kra file as a new project. THIS REPLACES THE CURRENT PROJECT.",
    {
      path: z.string().min(1).describe("Absolute path to the .kra file"),
      keep_structure: z.boolean().optional().describe("Keep KRA folder structure (default false)"),
    },
    async (args) =>
      runTool("import_kra", {
        path: args.path,
        keep_structure: args.keep_structure ?? false,
      }),
  );

  server.tool(
    "creator_import_inp",
    "Import an Inochi2D .inp puppet as a new project. THIS REPLACES THE CURRENT PROJECT.",
    {
      path: z.string().min(1).describe("Absolute path to the .inp file"),
    },
    async ({ path }) => runTool("import_inp", { path }),
  );

  server.tool(
    "creator_import_folder",
    "Import PNG/TGA/JPEG images from a folder as a new project. THIS REPLACES THE CURRENT PROJECT.",
    {
      path: z.string().min(1).describe("Absolute folder path"),
    },
    async ({ path }) => runTool("import_folder", { path }),
  );

  server.tool(
    "creator_import_images",
    "Import PNG/TGA/JPEG files as Parts under the selected (or specified) node. Does not replace the project.",
    {
      paths: z.array(z.string().min(1)).min(1).describe("Absolute image file paths"),
      parent_uuid: z.union([z.number().int(), z.string()]).optional().describe("Parent node UUID; defaults to current selection or root"),
    },
    async (args) => runTool("import_images", args),
  );
}
