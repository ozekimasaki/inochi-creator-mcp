const DEFAULT_PORT = 17320;
const DEFAULT_TIMEOUT_MS = 60_000;

export class CreatorUnavailableError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "CreatorUnavailableError";
  }
}

export class CreatorRpcError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "CreatorRpcError";
  }
}

type RpcResponse = {
  ok: boolean;
  result?: unknown;
  error?: string;
};

function bridgeUrl(): string {
  const port = Number(process.env.INOCHI_MCP_PORT ?? DEFAULT_PORT);
  return `http://127.0.0.1:${port}/rpc`;
}

export async function callCreator(
  method: string,
  params: Record<string, unknown> = {},
  timeoutMs = DEFAULT_TIMEOUT_MS,
): Promise<unknown> {
  const token = process.env.INOCHI_MCP_TOKEN ?? "";
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
  };
  if (token.length > 0) {
    headers.Authorization = `Bearer ${token}`;
    headers["X-Inochi-Token"] = token;
  }

  let response: Response;
  try {
    response = await fetch(bridgeUrl(), {
      method: "POST",
      headers,
      body: JSON.stringify({ method, params }),
      signal: AbortSignal.timeout(timeoutMs),
    });
  } catch (error) {
    const detail = error instanceof Error ? error.message : String(error);
    throw new CreatorUnavailableError(
      `パッチ済み Inochi Creator に接続できません (127.0.0.1:${process.env.INOCHI_MCP_PORT ?? DEFAULT_PORT})。ブリッジを入れた Creator を起動してください。 (${detail})`,
    );
  }

  if (response.status === 401) {
    throw new CreatorRpcError("INOCHI_MCP_TOKEN が Creator 側と一致しません。");
  }

  let payload: RpcResponse;
  try {
    payload = (await response.json()) as RpcResponse;
  } catch {
    throw new CreatorRpcError(`Creator ブリッジが JSON 以外を返しました (HTTP ${response.status})。`);
  }

  if (!payload.ok) {
    throw new CreatorRpcError(payload.error ?? "Creator ブリッジがエラーを返しました。");
  }

  return payload.result;
}
