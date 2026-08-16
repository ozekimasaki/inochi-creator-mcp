import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { runTool } from "./common.js";

export function registerAnimationTools(server: McpServer): void {
  server.tool(
    "creator_list_animations",
    "List animation clip names and the current playback state.",
    async () => runTool("list_animations"),
  );

  server.tool(
    "creator_set_animation",
    "Select the animation clip to edit or play.",
    {
      name: z.string().min(1).describe("Animation name"),
    },
    async ({ name }) => runTool("set_animation", { name }),
  );

  server.tool(
    "creator_play_animation",
    "Play an animation. If name is omitted, plays the current clip.",
    {
      name: z.string().optional().describe("Animation name"),
      loop: z.boolean().optional().describe("Loop playback (default false)"),
    },
    async (args) => runTool("play_animation", { name: args.name, loop: args.loop ?? false }),
  );

  server.tool(
    "creator_pause_animation",
    "Pause the current animation.",
    async () => runTool("pause_animation"),
  );

  server.tool(
    "creator_stop_animation",
    "Stop all animations.",
    {
      immediate: z.boolean().optional().describe("Skip lead-out (default true)"),
    },
    async ({ immediate }) => runTool("stop_animation", { immediate: immediate ?? true }),
  );

  server.tool(
    "creator_seek_animation",
    "Seek the current animation to a frame.",
    {
      frame: z.number().int().min(0).describe("Frame index"),
    },
    async ({ frame }) => runTool("seek_animation", { frame }),
  );

  server.tool(
    "creator_add_keyframe",
    "Add or update a keyframe on the current animation at the current frame.",
    {
      uuid: z.union([z.number().int(), z.string()]).optional().describe("Parameter UUID"),
      name: z.string().optional().describe("Parameter name"),
      axis: z.number().int().min(0).max(1).optional().describe("0 = X, 1 = Y (default 0)"),
      value: z.number().optional().describe("Keyframe value; defaults to the parameter's current value"),
    },
    async (args) => runTool("add_keyframe", args),
  );

  server.tool(
    "creator_remove_keyframe",
    "Remove a keyframe from the current animation at the current frame.",
    {
      uuid: z.union([z.number().int(), z.string()]).optional().describe("Parameter UUID"),
      name: z.string().optional().describe("Parameter name"),
      axis: z.number().int().min(0).max(1).optional().describe("0 = X, 1 = Y (default 0)"),
    },
    async (args) => runTool("remove_keyframe", args),
  );
}
