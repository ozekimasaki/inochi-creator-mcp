import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { runTool } from "./common.js";

const uuid = z.union([z.number().int(), z.string()]).describe("Node UUID");

export function registerNodeTools(server: McpServer): void {
  server.tool(
    "creator_list_nodes",
    "List the puppet node tree (uuid, name, type, enabled, children).",
    {
      detail: z.boolean().optional().describe("Include local transform on every node"),
    },
    async ({ detail }) => runTool("list_nodes", { detail: detail ?? false }),
  );

  server.tool(
    "creator_get_node",
    "Get one node by UUID, including transform and type-specific fields.",
    { uuid },
    async (args) => runTool("get_node", args),
  );

  server.tool(
    "creator_select_node",
    "Select a node by UUID. Omit uuid to clear the selection.",
    {
      uuid: z.union([z.number().int(), z.string()]).optional().describe("Node UUID; omit to clear"),
    },
    async (args) => runTool("select_node", args.uuid === undefined ? {} : { uuid: args.uuid }),
  );

  server.tool(
    "creator_focus_camera",
    "Focus the viewport camera on a node.",
    { uuid },
    async (args) => runTool("focus_camera", args),
  );

  server.tool(
    "creator_rename_node",
    "Rename a node.",
    {
      uuid,
      name: z.string().min(1).describe("New node name"),
    },
    async (args) => runTool("rename_node", args),
  );

  server.tool(
    "creator_set_node_enabled",
    "Enable or disable a node (visibility).",
    {
      uuid,
      enabled: z.boolean().describe("Whether the node is enabled"),
    },
    async (args) => runTool("set_node_enabled", args),
  );

  server.tool(
    "creator_set_node_transform",
    "Set a node's local translation, rotation (radians), and/or scale. Unspecified axes are left unchanged.",
    {
      uuid,
      translation: z.tuple([z.number(), z.number(), z.number()]).optional().describe("Local translation [x, y, z]"),
      rotation: z.tuple([z.number(), z.number(), z.number()]).optional().describe("Local Euler rotation in radians [x, y, z]"),
      scale: z.tuple([z.number(), z.number()]).optional().describe("Local scale [x, y]"),
      zsort: z.number().optional().describe("Z-sort offset"),
    },
    async (args) => runTool("set_node_transform", args),
  );

  server.tool(
    "creator_create_node",
    "Create a node under a parent. Types match the Nodes panel Add menu: Node, Composite, MeshGroup, SimplePhysics, Camera. Parts must be created via creator_import_images.",
    {
      type: z.enum(["Node", "Composite", "MeshGroup", "SimplePhysics", "Camera"]).describe("Node type to create"),
      parent_uuid: z.union([z.number().int(), z.string()]).optional().describe("Parent UUID; defaults to root"),
      name: z.string().optional().describe("Optional node name"),
    },
    async (args) => runTool("create_node", args),
  );

  server.tool(
    "creator_duplicate_node",
    "Duplicate a node and its children (cameras cannot be duplicated).",
    { uuid },
    async (args) => runTool("duplicate_node", args),
  );

  server.tool(
    "creator_delete_node",
    "Delete a node (and its children) with undo history.",
    { uuid },
    async (args) => runTool("delete_node", args),
  );

  server.tool(
    "creator_reparent_node",
    "Move a node to a new parent. index is the insertion offset among siblings (0 = first).",
    {
      uuid,
      parent_uuid: z.union([z.number().int(), z.string()]).describe("New parent UUID"),
      index: z.number().int().min(0).optional().describe("Sibling insertion index"),
    },
    async (args) => runTool("reparent_node", args),
  );
}
