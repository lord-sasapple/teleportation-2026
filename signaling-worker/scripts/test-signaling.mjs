const baseUrl = process.env.SIGNALING_WS_URL ?? "ws://127.0.0.1:8787";
const roomId = process.env.ROOM_ID ?? `script-${Date.now()}`;

class TestSocket {
  constructor(role) {
    this.role = role;
    this.messages = [];
    this.waiters = [];
    this.closed = false;
    this.ws = new WebSocket(`${baseUrl}/room/${encodeURIComponent(roomId)}?role=${role}`);
  }

  async open() {
    await new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error(`${this.role} open timeout`)), 3000);
      this.ws.addEventListener("open", () => {
        clearTimeout(timer);
        resolve();
      });
      this.ws.addEventListener("error", () => {
        clearTimeout(timer);
        reject(new Error(`${this.role} WebSocket error`));
      });
    });

    this.ws.addEventListener("message", (event) => this.handleMessage(event.data));
    this.ws.addEventListener("close", () => {
      this.closed = true;
    });

    return this;
  }

  async join() {
    await this.open();
    await this.next((message) => message.type === "joined", `${this.role} joined`);
    return this;
  }

  send(message) {
    this.ws.send(JSON.stringify(message));
  }

  close() {
    this.ws.close();
  }

  async closeAndWait(timeoutMs = 1000) {
    if (this.closed || this.ws.readyState === 3) {
      return;
    }

    await new Promise((resolve) => {
      const timer = setTimeout(resolve, timeoutMs);
      this.ws.addEventListener(
        "close",
        () => {
          clearTimeout(timer);
          resolve();
        },
        { once: true }
      );
      this.ws.close();
    });
  }

  async next(predicate, label, timeoutMs = 3000) {
    const existingIndex = this.messages.findIndex(predicate);
    if (existingIndex >= 0) {
      const [message] = this.messages.splice(existingIndex, 1);
      return message;
    }

    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        reject(new Error(`timeout waiting for ${label}`));
      }, timeoutMs);

      this.waiters.push({
        predicate,
        resolve: (message) => {
          clearTimeout(timer);
          resolve(message);
        }
      });
    });
  }

  handleMessage(data) {
    const text = typeof data === "string" ? data : Buffer.from(data).toString("utf8");
    const message = JSON.parse(text);
    const waiterIndex = this.waiters.findIndex((waiter) => waiter.predicate(message));

    if (waiterIndex >= 0) {
      const [waiter] = this.waiters.splice(waiterIndex, 1);
      waiter.resolve(message);
      return;
    }

    this.messages.push(message);
  }
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

async function main() {
  console.log(`Testing signaling server: ${baseUrl}, room=${roomId}`);

  const sender = await new TestSocket("sender").join();
  const receiver = await new TestSocket("receiver").join();

  await sender.next((message) => message.type === "peer-joined" && message.role === "receiver", "sender peer-joined");

  sender.send({ type: "offer", sdp: "v=0\r\no=- 1 1 IN IP4 127.0.0.1\r\n" });
  const offer = await receiver.next((message) => message.type === "offer", "offer");
  assert(offer.sdp.startsWith("v=0"), "offer was not forwarded");

  receiver.send({ type: "answer", sdp: "v=0\r\no=- 2 2 IN IP4 127.0.0.1\r\n" });
  const answer = await sender.next((message) => message.type === "answer", "answer");
  assert(answer.sdp.startsWith("v=0"), "answer was not forwarded");

  const senderCandidate = {
    type: "ice-candidate",
    candidate: { candidate: "candidate:sender", sdpMid: "0", sdpMLineIndex: 0 }
  };
  sender.send(senderCandidate);
  const receiverIce = await receiver.next((message) => message.type === "ice-candidate", "sender ice-candidate");
  assert(receiverIce.candidate.candidate === "candidate:sender", "sender candidate was not forwarded");

  const receiverCandidate = {
    type: "ice-candidate",
    candidate: { candidate: "candidate:receiver", sdpMid: "0", sdpMLineIndex: 0 }
  };
  receiver.send(receiverCandidate);
  const senderIce = await sender.next((message) => message.type === "ice-candidate", "receiver ice-candidate");
  assert(senderIce.candidate.candidate === "candidate:receiver", "receiver candidate was not forwarded");

  sender.send({ type: "latency-sync", sequence: 1, senderTimeMs: Date.now() });
  const sync = await receiver.next((message) => message.type === "latency-sync" && message.sequence === 1, "latency-sync");
  receiver.send({
    type: "latency-echo",
    sequence: sync.sequence,
    senderTimeMs: sync.senderTimeMs,
    receiverTimeMs: Date.now()
  });
  await sender.next((message) => message.type === "latency-echo" && message.sequence === 1, "latency-echo");

  const duplicateSender = await new TestSocket("sender").open();
  await duplicateSender.next((message) => message.type === "error" && message.message.includes("duplicate"), "duplicate sender error");

  receiver.send({ type: "leave" });
  await sender.next((message) => message.type === "peer-left" && message.role === "receiver", "peer-left");

  await Promise.all([sender.closeAndWait(), receiver.closeAndWait(), duplicateSender.closeAndWait()]);

  console.log("All signaling checks passed.");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
