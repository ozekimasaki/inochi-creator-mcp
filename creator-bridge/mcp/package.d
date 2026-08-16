/*
    Inochi Creator MCP bridge
    Listens on 127.0.0.1 and executes commands on the UI thread.
*/
module creator.mcp;

import creator.mcp.handlers;
import std.conv : to;
import std.json;
import std.socket;
import std.string;
import std.array : split;
import std.algorithm.searching : findSplit, canFind;
import std.process : environment;
import core.thread;
import core.sync.mutex;
import core.sync.condition;
import core.time : seconds, Duration;

private {
    __gshared TcpSocket listener;
    __gshared Mutex queueMutex;
    __gshared McpJob[] queue;
    __gshared bool running;
    __gshared ushort listenPort = 17320;
    __gshared string authToken;
}

class McpJob {
    string method;
    JSONValue params;
    JSONValue result;
    string error;
    bool ok;
    bool done;
    Mutex mutex;
    Condition cond;

    this() {
        mutex = new Mutex();
        cond = new Condition(mutex);
    }

    void finish() {
        synchronized (mutex) {
            done = true;
            cond.notifyAll();
        }
    }

    bool waitFor(Duration timeout) {
        synchronized (mutex) {
            if (done) return true;
            cond.wait(timeout);
            return done;
        }
    }
}

/**
    Start the localhost MCP HTTP server. Safe to call once after the window exists.
*/
void incMcpInit() {
    if (running) return;

    queueMutex = new Mutex();
    listenPort = to!ushort(environment.get("INOCHI_MCP_PORT", "17320"));
    authToken = environment.get("INOCHI_MCP_TOKEN", "");

    try {
        listener = new TcpSocket();
        listener.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, true);
        listener.bind(new InternetAddress("127.0.0.1", listenPort));
        listener.listen(16);
        running = true;
    } catch (Exception ex) {
        running = false;
        return;
    }

    auto serverThread = new Thread(&mcpAcceptLoop);
    serverThread.isDaemon = true;
    serverThread.start();
}

/**
    Drain queued MCP jobs on the main thread.
*/
void incMcpPoll() {
    if (!running) return;

    McpJob[] jobs;
    synchronized (queueMutex) {
        jobs = queue;
        queue.length = 0;
    }

    foreach (job; jobs) {
        try {
            job.result = incMcpHandle(job.method, job.params);
            job.ok = true;
        } catch (Exception ex) {
            job.ok = false;
            job.error = ex.msg;
        }
        job.finish();
    }
}

private void mcpAcceptLoop() {
    while (running) {
        try {
            auto client = listener.accept();
            spawnClient(client);
        } catch (Exception) {
            if (!running) break;
        }
    }
}

private void spawnClient(Socket client) {
    auto worker = new Thread({
        mcpHandleClient(client);
    });
    worker.isDaemon = true;
    worker.start();
}

private void mcpHandleClient(Socket client) {
    scope (exit) {
        try { client.close(); } catch (Exception) {}
    }

    try {
        client.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, 15.seconds);
        string raw = mcpReadHttp(client);
        if (raw.length == 0) return;

        auto split = raw.findSplit("\r\n\r\n");
        if (split[1].length == 0) {
            mcpSendJson(client, 400, `{"ok":false,"error":"malformed HTTP request"}`);
            return;
        }

        string headerText = split[0];
        string body = split[2];
        auto lines = split(headerText, "\r\n");
        if (lines.length == 0) {
            mcpSendJson(client, 400, `{"ok":false,"error":"empty request"}`);
            return;
        }

        auto reqLine = split(lines[0], " ");
        if (reqLine.length < 2) {
            mcpSendJson(client, 400, `{"ok":false,"error":"malformed request line"}`);
            return;
        }

        string httpMethod = reqLine[0];
        string path = reqLine[1];

        string[string] headers;
        foreach (line; lines[1 .. $]) {
            auto hv = line.findSplit(":");
            if (hv[1].length > 0) {
                headers[hv[0].strip.toLower] = hv[2].strip;
            }
        }

        if (authToken.length > 0) {
            string provided;
            if ("x-inochi-token" in headers) provided = headers["x-inochi-token"];
            else if ("authorization" in headers) {
                auto auth = headers["authorization"];
                if (auth.length > 7 && auth[0 .. 7].toLower == "bearer ") {
                    provided = auth[7 .. $].strip;
                } else {
                    provided = auth;
                }
            }
            if (provided != authToken) {
                mcpSendJson(client, 401, `{"ok":false,"error":"unauthorized"}`);
                return;
            }
        }

        if (httpMethod == "GET" && (path == "/" || path == "/health")) {
            mcpSendJson(client, 200, `{"ok":true,"result":{"bridge":"inochi-creator-mcp","port":` ~ to!string(listenPort) ~ `}}`);
            return;
        }

        if (httpMethod != "POST" || (path != "/rpc" && path != "/")) {
            mcpSendJson(client, 404, `{"ok":false,"error":"use POST /rpc"}`);
            return;
        }

        if ("content-length" in headers) {
            auto want = to!size_t(headers["content-length"]);
            while (body.length < want) {
                ubyte[4096] buf;
                auto n = client.receive(buf);
                if (n <= 0) break;
                body ~= cast(string)buf[0 .. n];
            }
            if (body.length > want) body = body[0 .. want];
        }

        JSONValue payload;
        try {
            payload = parseJSON(body);
        } catch (Exception ex) {
            mcpSendJson(client, 400, `{"ok":false,"error":"invalid JSON"}`);
            return;
        }

        if (payload.type != JSONType.object || "method" !in payload.object) {
            mcpSendJson(client, 400, `{"ok":false,"error":"method is required"}`);
            return;
        }

        auto job = new McpJob();
        job.method = payload["method"].str;
        job.params = parseJSON("{}");
        if ("params" in payload.object) job.params = payload["params"];

        synchronized (queueMutex) {
            queue ~= job;
        }

        if (!job.waitFor(60.seconds)) {
            mcpSendJson(client, 504, `{"ok":false,"error":"timed out waiting for the UI thread"}`);
            return;
        }

        JSONValue[string] resp;
        resp["ok"] = JSONValue(job.ok);
        if (job.ok) resp["result"] = job.result;
        else resp["error"] = JSONValue(job.error);
        mcpSendJson(client, 200, JSONValue(resp).toString());
    } catch (Exception ex) {
        try {
            mcpSendJson(client, 500, `{"ok":false,"error":` ~ JSONValue(ex.msg).toString() ~ `}`);
        } catch (Exception) {}
    }
}

private string mcpReadHttp(Socket client) {
    ubyte[] buf;
    ubyte[4096] tmp;
    enum headerEnd = "\r\n\r\n";
    while (true) {
        auto n = client.receive(tmp);
        if (n <= 0) return cast(string)buf;
        buf ~= tmp[0 .. n];
        if ((cast(string)buf).canFind(headerEnd)) return cast(string)buf;
        if (buf.length > 1024 * 1024) return null;
    }
}

private void mcpSendJson(Socket client, int status, string body) {
    string reason = "OK";
    if (status == 400) reason = "Bad Request";
    else if (status == 401) reason = "Unauthorized";
    else if (status == 404) reason = "Not Found";
    else if (status == 500) reason = "Internal Server Error";
    else if (status == 504) reason = "Gateway Timeout";

    auto resp = "HTTP/1.1 " ~ to!string(status) ~ " " ~ reason ~ "\r\n" ~
        "Content-Type: application/json; charset=utf-8\r\n" ~
        "Content-Length: " ~ to!string(body.length) ~ "\r\n" ~
        "Connection: close\r\n\r\n" ~ body;
    client.send(cast(const(void)[])resp);
}
