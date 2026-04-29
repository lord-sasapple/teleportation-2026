import { isRecord, isRole, type Role } from "../../shared/protocol/messages";

export interface Env {
  ROOMS: DurableObjectNamespace;
}

export interface WebSocketAttachment {
  role: Role;
  roomId: string;
  connectedAt: number;
  connectionId: string;
}

export function isWebSocketAttachment(value: unknown): value is WebSocketAttachment {
  return (
    isRecord(value) &&
    isRole(value.role) &&
    typeof value.roomId === "string" &&
    value.roomId.length > 0 &&
    typeof value.connectedAt === "number" &&
    typeof value.connectionId === "string"
  );
}

