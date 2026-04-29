export type Role = "sender" | "receiver";

export interface IceCandidatePayload {
  candidate: string;
  sdpMid?: string | null;
  sdpMLineIndex?: number | null;
}

export interface JoinMessage {
  type: "join";
  roomId: string;
  role: Role;
}

export interface OfferMessage {
  type: "offer";
  sdp: string;
}

export interface AnswerMessage {
  type: "answer";
  sdp: string;
}

export interface IceCandidateMessage {
  type: "ice-candidate";
  candidate: IceCandidatePayload;
}

export interface LeaveMessage {
  type: "leave";
}

export interface PingMessage {
  type: "ping";
}

export interface LatencySyncMessage {
  type: "latency-sync";
  sequence: number;
  senderTimeMs: number;
}

export interface LatencyEchoMessage {
  type: "latency-echo";
  sequence: number;
  senderTimeMs: number;
  receiverTimeMs: number;
}

export type ClientMessage =
  | JoinMessage
  | OfferMessage
  | AnswerMessage
  | IceCandidateMessage
  | LeaveMessage
  | PingMessage
  | LatencySyncMessage
  | LatencyEchoMessage;

export interface JoinedMessage {
  type: "joined";
  roomId: string;
  role: Role;
}

export interface PeerJoinedMessage {
  type: "peer-joined";
  role: Role;
}

export interface PeerLeftMessage {
  type: "peer-left";
  role: Role;
}

export interface PongMessage {
  type: "pong";
}

export interface ErrorMessage {
  type: "error";
  message: string;
}

export type ServerMessage =
  | JoinedMessage
  | PeerJoinedMessage
  | OfferMessage
  | AnswerMessage
  | IceCandidateMessage
  | PeerLeftMessage
  | PongMessage
  | ErrorMessage
  | LatencySyncMessage
  | LatencyEchoMessage;

export function isRole(value: unknown): value is Role {
  return value === "sender" || value === "receiver";
}

export function peerRole(role: Role): Role {
  return role === "sender" ? "receiver" : "sender";
}

export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function isIceCandidatePayload(value: unknown): value is IceCandidatePayload {
  if (!isRecord(value)) {
    return false;
  }

  const { candidate, sdpMid, sdpMLineIndex } = value;

  return (
    typeof candidate === "string" &&
    (sdpMid === undefined || sdpMid === null || typeof sdpMid === "string") &&
    (sdpMLineIndex === undefined ||
      sdpMLineIndex === null ||
      (typeof sdpMLineIndex === "number" && Number.isInteger(sdpMLineIndex) && sdpMLineIndex >= 0))
  );
}

export function isLatencySyncMessage(value: unknown): value is LatencySyncMessage {
  return (
    isRecord(value) &&
    value.type === "latency-sync" &&
    Number.isInteger(value.sequence) &&
    typeof value.senderTimeMs === "number"
  );
}

export function isLatencyEchoMessage(value: unknown): value is LatencyEchoMessage {
  return (
    isRecord(value) &&
    value.type === "latency-echo" &&
    Number.isInteger(value.sequence) &&
    typeof value.senderTimeMs === "number" &&
    typeof value.receiverTimeMs === "number"
  );
}

export function isClientMessage(value: unknown): value is ClientMessage {
  if (!isRecord(value) || typeof value.type !== "string") {
    return false;
  }

  switch (value.type) {
    case "join":
      return typeof value.roomId === "string" && isRole(value.role);
    case "offer":
    case "answer":
      return typeof value.sdp === "string";
    case "ice-candidate":
      return isIceCandidatePayload(value.candidate);
    case "leave":
    case "ping":
      return true;
    case "latency-sync":
      return isLatencySyncMessage(value);
    case "latency-echo":
      return isLatencyEchoMessage(value);
    default:
      return false;
  }
}

export function parseClientMessage(value: unknown): ClientMessage | null {
  return isClientMessage(value) ? value : null;
}
