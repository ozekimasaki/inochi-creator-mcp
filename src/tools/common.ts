import { callCreator, CreatorUnavailableError, CreatorRpcError } from "../creator-client.js";

export type TextContent = { type: "text"; text: string };
export type ImageContent = { type: "image"; data: string; mimeType: string };
export type ToolResult = {
  content: Array<TextContent | ImageContent>;
  isError?: boolean;
};

export function jsonResult(data: unknown): ToolResult {
  return {
    content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
  };
}

export function errorResult(message: string): ToolResult {
  return {
    content: [{ type: "text", text: message }],
    isError: true,
  };
}

export async function runTool(
  method: string,
  params: Record<string, unknown> = {},
): Promise<ToolResult> {
  try {
    const result = await callCreator(method, params);
    return jsonResult(result);
  } catch (error) {
    if (error instanceof CreatorUnavailableError || error instanceof CreatorRpcError) {
      return errorResult(error.message);
    }
    const message = error instanceof Error ? error.message : String(error);
    return errorResult(message);
  }
}
