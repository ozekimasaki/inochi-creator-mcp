import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { runTool } from "./common.js";

const paramRef = {
  uuid: z.union([z.number().int(), z.string()]).optional().describe("Parameter UUID"),
  name: z.string().optional().describe("Parameter name (used if uuid is omitted)"),
};

export function registerParameterTools(server: McpServer): void {
  server.tool(
    "creator_list_parameters",
    "List puppet parameters (including groups) with current values and ranges.",
    async () => runTool("list_parameters"),
  );

  server.tool(
    "creator_set_parameter",
    "Set a parameter value. For 1D params only x is used. For 2D params provide x and y.",
    {
      ...paramRef,
      x: z.number().describe("X value"),
      y: z.number().optional().describe("Y value for vec2 parameters"),
    },
    async (args) => runTool("set_parameter", args),
  );

  server.tool(
    "creator_arm_parameter",
    "Arm a parameter for deformation editing (disables drivers while armed).",
    paramRef,
    async (args) => runTool("arm_parameter", args),
  );

  server.tool(
    "creator_disarm_parameter",
    "Disarm the currently armed parameter and re-enable drivers.",
    async () => runTool("disarm_parameter"),
  );

  server.tool(
    "creator_add_parameter",
    "Add a new parameter to the puppet.",
    {
      name: z.string().min(1).describe("Parameter name"),
      is_vec2: z.boolean().optional().describe("True for a 2D parameter (default false)"),
    },
    async (args) => runTool("add_parameter", { name: args.name, is_vec2: args.is_vec2 ?? false }),
  );

  server.tool(
    "creator_remove_parameter",
    "Remove a parameter from the puppet.",
    paramRef,
    async (args) => runTool("remove_parameter", args),
  );
}
