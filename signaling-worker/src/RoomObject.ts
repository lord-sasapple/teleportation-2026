import {
  parseClientMessage,
  peerRole,
  type ClientMessage,
  type Role,
  type ServerMessage
} from "../../shared/protocol/messages";
import { isWebSocketAttachment, type Env, type WebSocketAttachment } from "./types";

const CLOSE_NORMAL = 1000;
const CLOSE_BAD_MESSAGE = 4000;
const CLOSE_DUPLICATE_ROLE = 4008;

export class RoomObject implements DurableObject {
  private sockets = new Map<Role, WebSocket>();
  private roomId: string | undefined;

  constructor(private readonly state: DurableObjectState, private readonly env: Env) {
    this.restoreSockets();
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const role = url.searchParams.get("role");
    const roomId = decodeURIComponent(url.pathname.match(/^\/room\/([^/]+)$/)?.[1] ?? "").trim();

    if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
      return new Response("WebSocket upgrade required", { status: 426, headers: { Upgrade: "websocket" } });
    }

    if ((role !== "sender" && role !== "receiver") || roomId.length === 0) {
      return new Response("invalid room or role", { status: 400 });
    }

    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair) as [WebSocket, WebSocket];
    const attachment: WebSocketAttachment = {
      role,
      roomId,
      connectedAt: Date.now(),
      connectionId: crypto.randomUUID()
    };

    server.serializeAttachment(attachment);
    this.state.acceptWebSocket(server);

    if (this.sockets.has(role)) {
      console.warn(`重複接続を拒否しました: room=${roomId} role=${role}`);
      this.send(server, { type: "error", message: `duplicate role: ${role}` });
      this.safeClose(server, CLOSE_DUPLICATE_ROLE, "duplicate role");
      return new Response(null, { status: 101, webSocket: client });
    }

    this.roomId = roomId;
    this.sockets.set(role, server);
    console.log(`接続を受け付けました: room=${roomId} role=${role}`);

    this.send(server, { type: "joined", roomId, role });
    this.notifyPeerJoined(role, server);

    return new Response(null, { status: 101, webSocket: client });
  }

  webSocketMessage(ws: WebSocket, message: string | ArrayBuffer): void {
    const attachment = this.getAttachment(ws);
    if (!attachment) {
      this.send(ws, { type: "error", message: "missing WebSocket attachment" });
      this.safeClose(ws, CLOSE_BAD_MESSAGE, "missing attachment");
      return;
    }

    const text = this.messageToText(message);
    let parsed: unknown;

    try {
      parsed = JSON.parse(text);
    } catch {
      console.warn(`JSON parse error: room=${attachment.roomId} role=${attachment.role}`);
      this.send(ws, { type: "error", message: "invalid JSON" });
      return;
    }

    const clientMessage = parseClientMessage(parsed);
    if (!clientMessage) {
      const messageType =
        typeof parsed === "object" && parsed !== null && "type" in parsed
          ? String((parsed as { type?: unknown }).type)
          : "unknown";
      console.warn(`不明または不正なメッセージ: room=${attachment.roomId} role=${attachment.role} type=${messageType}`);
      this.send(ws, { type: "error", message: `unknown or invalid message: ${messageType}` });
      return;
    }

    this.handleClientMessage(ws, attachment, clientMessage);
  }

  webSocketClose(ws: WebSocket, code: number, reason: string, wasClean: boolean): void {
    const attachment = this.getAttachment(ws);
    if (!attachment) {
      return;
    }

    console.log(
      `切断を検知しました: room=${attachment.roomId} role=${attachment.role} code=${code} clean=${wasClean} reason=${reason}`
    );
    this.detachSocket(ws, true);
  }

  webSocketError(ws: WebSocket, error: unknown): void {
    const attachment = this.getAttachment(ws);
    console.warn(`WebSocket error: room=${attachment?.roomId ?? "unknown"} role=${attachment?.role ?? "unknown"}`, error);
    this.detachSocket(ws, true);
  }

  private restoreSockets(): void {
    for (const ws of this.state.getWebSockets()) {
      const attachment = this.getAttachment(ws);
      if (!attachment) {
        this.safeClose(ws, CLOSE_BAD_MESSAGE, "invalid attachment");
        continue;
      }

      if (this.sockets.has(attachment.role)) {
        console.warn(`復元時に重複roleを検知しました: room=${attachment.roomId} role=${attachment.role}`);
        this.safeClose(ws, CLOSE_DUPLICATE_ROLE, "duplicate restored role");
        continue;
      }

      this.roomId = attachment.roomId;
      this.sockets.set(attachment.role, ws);
      console.log(`hibernation復帰: room=${attachment.roomId} role=${attachment.role}`);
    }
  }

  private handleClientMessage(ws: WebSocket, attachment: WebSocketAttachment, message: ClientMessage): void {
    switch (message.type) {
      case "join":
        if (message.roomId !== attachment.roomId || message.role !== attachment.role) {
          this.send(ws, { type: "error", message: "join message does not match connection role or roomId" });
          return;
        }
        this.send(ws, { type: "joined", roomId: attachment.roomId, role: attachment.role });
        return;

      case "ping":
        this.send(ws, { type: "pong" });
        return;

      case "leave":
        console.log(`leaveを受信しました: room=${attachment.roomId} role=${attachment.role}`);
        this.detachSocket(ws, true);
        this.safeClose(ws, CLOSE_NORMAL, "leave");
        return;

      case "offer":
        if (!this.requireRole(ws, attachment.role, "sender", "offer")) {
          return;
        }
        this.forwardToPeer(ws, attachment, { type: "offer", sdp: message.sdp });
        return;

      case "answer":
        if (!this.requireRole(ws, attachment.role, "receiver", "answer")) {
          return;
        }
        this.forwardToPeer(ws, attachment, { type: "answer", sdp: message.sdp });
        return;

      case "ice-candidate":
        this.forwardToPeer(ws, attachment, { type: "ice-candidate", candidate: message.candidate });
        return;

      case "latency-sync":
        this.forwardToPeer(ws, attachment, {
          type: "latency-sync",
          sequence: message.sequence,
          senderTimeMs: message.senderTimeMs
        });
        return;

      case "latency-echo":
        this.forwardToPeer(ws, attachment, {
          type: "latency-echo",
          sequence: message.sequence,
          senderTimeMs: message.senderTimeMs,
          receiverTimeMs: message.receiverTimeMs
        });
        return;

      case "receiver-log":
        if (!this.requireRole(ws, attachment.role, "receiver", "receiver-log")) {
          return;
        }
        this.forwardToPeer(ws, attachment, {
          type: "receiver-log",
          level: message.level,
          message: message.message.slice(0, 2000),
          timestampMs: message.timestampMs
        });
        return;
    }
  }

  private requireRole(ws: WebSocket, actual: Role, expected: Role, messageType: string): boolean {
    if (actual === expected) {
      return true;
    }

    this.send(ws, { type: "error", message: `${messageType} is only allowed from ${expected}` });
    return false;
  }

  private forwardToPeer(ws: WebSocket, attachment: WebSocketAttachment, message: ServerMessage): void {
    const targetRole = peerRole(attachment.role);
    const peer = this.sockets.get(targetRole);

    if (!peer) {
      this.send(ws, { type: "error", message: `peer is not connected: ${targetRole}` });
      return;
    }

    console.log(`メッセージ中継: room=${attachment.roomId} ${attachment.role}->${targetRole} type=${message.type}`);
    this.send(peer, message);
  }

  private notifyPeerJoined(role: Role, ws: WebSocket): void {
    const targetRole = peerRole(role);
    const peer = this.sockets.get(targetRole);
    if (!peer) {
      return;
    }

    this.send(peer, { type: "peer-joined", role });
    this.send(ws, { type: "peer-joined", role: targetRole });
  }

  private detachSocket(ws: WebSocket, notifyPeer: boolean): void {
    const attachment = this.getAttachment(ws);
    if (!attachment) {
      return;
    }

    const current = this.sockets.get(attachment.role);
    if (current !== ws) {
      return;
    }

    this.sockets.delete(attachment.role);
    const targetRole = peerRole(attachment.role);
    const peer = this.sockets.get(targetRole);

    if (notifyPeer && peer) {
      this.send(peer, { type: "peer-left", role: attachment.role });
    }

    if (this.sockets.size === 0) {
      this.roomId = undefined;
    }
  }

  private getAttachment(ws: WebSocket): WebSocketAttachment | null {
    try {
      const attachment = ws.deserializeAttachment();
      return isWebSocketAttachment(attachment) ? attachment : null;
    } catch {
      return null;
    }
  }

  private messageToText(message: string | ArrayBuffer): string {
    if (typeof message === "string") {
      return message;
    }

    return new TextDecoder().decode(message);
  }

  private send(ws: WebSocket, message: ServerMessage): void {
    try {
      if (ws.readyState === 1) {
        ws.send(JSON.stringify(message));
      }
    } catch (error) {
      console.warn(`送信に失敗しました: type=${message.type}`, error);
    }
  }

  private safeClose(ws: WebSocket, code: number, reason: string): void {
    try {
      if (ws.readyState === 0 || ws.readyState === 1) {
        ws.close(code, reason);
      }
    } catch (error) {
      console.warn(`closeに失敗しました: code=${code} reason=${reason}`, error);
    }
  }
}
