import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { registerStatusTools } from "./status.js";
import { registerProjectTools } from "./project.js";
import { registerNodeTools } from "./nodes.js";
import { registerParameterTools } from "./parameters.js";
import { registerHistoryTools } from "./history.js";
import { registerImportTools } from "./import.js";
import { registerAnimationTools } from "./animation.js";
import { registerViewportTools } from "./viewport.js";

export function registerAllTools(server: McpServer): void {
  registerStatusTools(server);
  registerProjectTools(server);
  registerNodeTools(server);
  registerParameterTools(server);
  registerHistoryTools(server);
  registerImportTools(server);
  registerAnimationTools(server);
  registerViewportTools(server);
}
