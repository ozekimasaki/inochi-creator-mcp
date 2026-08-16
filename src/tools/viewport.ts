import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { callCreator, CreatorRpcError, CreatorUnavailableError } from "../creator-client.js";
import { errorResult, type ToolResult } from "./common.js";

type CaptureResult = {
  width: number;
  height: number;
  png_base64: string;
  path?: string;
};

export function registerViewportTools(server: McpServer): void {
  server.tool(
    "creator_capture_viewport",
    "Capture the current Inochi Creator viewport as a PNG. Returns an image the model can see. By default the long side is scaled to 1024 pixels.",
    {
      path: z.string().optional().describe("Optional absolute path to also save the PNG"),
      full: z.boolean().optional().describe("If true, return the original resolution instead of downscaling"),
    },
    async (args): Promise<ToolResult> => {
      try {
        const result = (await callCreator("capture_viewport", {
          path: args.path,
          full: args.full ?? false,
        })) as CaptureResult;

        const content: ToolResult["content"] = [
          {
            type: "text",
            text: JSON.stringify(
              {
                width: result.width,
                height: result.height,
                path: result.path ?? null,
              },
              null,
              2,
            ),
          },
        ];

        if (typeof result.png_base64 === "string" && result.png_base64.length > 0) {
          content.push({
            type: "image",
            data: result.png_base64,
            mimeType: "image/png",
          });
        }

        return { content };
      } catch (error) {
        if (error instanceof CreatorUnavailableError || error instanceof CreatorRpcError) {
          return errorResult(error.message);
        }
        return errorResult(error instanceof Error ? error.message : String(error));
      }
    },
  );
}
