import { RoomObject } from "./RoomObject";
import { isRole, type Role } from "../../shared/protocol/messages";
import type { Env } from "./types";

export { RoomObject };

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization"
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json; charset=utf-8"
    }
  });
}

function isWebSocketUpgrade(request: Request): boolean {
  return request.headers.get("Upgrade")?.toLowerCase() === "websocket";
}

// 後続タスクで token 認証を入れやすいように入口を分けておく。
function authorizeRequest(_request: Request, _roomId: string, _role: Role): boolean {
  return true;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders });
    }

    if (request.method === "GET" && url.pathname === "/healthz") {
      return jsonResponse({
        ok: true,
        service: "x5-webrtc-signaling",
        mediaRelay: false
      });
    }

    if (url.pathname === "/room" || url.pathname === "/room/") {
      return jsonResponse({ type: "error", message: "roomId is required" }, 400);
    }

    const roomMatch = url.pathname.match(/^\/room\/([^/]+)$/);
    if (!roomMatch) {
      return jsonResponse({ type: "error", message: "not found" }, 404);
    }

    const roomId = decodeURIComponent(roomMatch[1] ?? "").trim();
    if (roomId.length === 0) {
      return jsonResponse({ type: "error", message: "roomId is required" }, 400);
    }

    const roleParam = url.searchParams.get("role");
    if (!isRole(roleParam)) {
      return jsonResponse({ type: "error", message: "role must be sender or receiver" }, 400);
    }

    if (!isWebSocketUpgrade(request)) {
      return new Response("WebSocket upgrade required", {
        status: 426,
        headers: {
          ...corsHeaders,
          Upgrade: "websocket"
        }
      });
    }

    if (!authorizeRequest(request, roomId, roleParam)) {
      return jsonResponse({ type: "error", message: "unauthorized" }, 401);
    }

    const objectId = env.ROOMS.idFromName(roomId);
    const room = env.ROOMS.get(objectId);
    return room.fetch(request);
  }
} satisfies ExportedHandler<Env>;

