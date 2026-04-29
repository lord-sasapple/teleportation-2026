export type CandidateType = "host" | "srflx" | "prflx" | "relay" | "unknown";

export type CodecName = "HEVC/H.265" | "H.264" | "AV1" | "unknown" | string;

export interface FrameTimestampMessage {
  type: "frame-timestamp";
  sequence: number;
  captureTimeMs: number;
  encodeStartTimeMs: number;
  encodeEndTimeMs: number;
  sendTimeMs: number;
}

export interface FrameLatencyReportMessage {
  type: "frame-latency-report";
  sequence: number;
  captureTimeMs: number;
  encodeEndTimeMs: number;
  receiverDataTimeMs: number;
  firstFrameSeenTimeMs: number;
  renderSubmitTimeMs: number;
  estimatedAppLatencyMs: number;
}

export interface WebRTCStatsSnapshot {
  capturedAtMs: number;
  selectedCandidatePair?: string;
  localCandidateType?: CandidateType;
  remoteCandidateType?: CandidateType;
  currentRoundTripTimeMs?: number;
  availableOutgoingBitrateBps?: number;
  jitterMs?: number;
  jitterBufferDelayMs?: number;
  jitterBufferTargetDelayMs?: number;
  packetsLost?: number;
  framesSent?: number;
  framesReceived?: number;
  framesDecoded?: number;
  framesDropped?: number;
  frameWidth?: number;
  frameHeight?: number;
  framesPerSecond?: number;
  codec?: CodecName;
  encoderImplementation?: string;
  decoderImplementation?: string;
  raw?: Record<string, unknown>;
}

export interface LatencyMetrics {
  sequence: number;
  captureToEncodeEndMs?: number;
  encodeDurationMs?: number;
  encodeEndToReceiverDataMs?: number;
  receiverDataToFirstFrameSeenMs?: number;
  firstFrameSeenToRenderSubmitMs?: number;
  estimatedAppLatencyMs?: number;
  glassToGlassLatencyMs?: number;
  notes?: string;
}

export type LatencyDataChannelMessage = FrameTimestampMessage | FrameLatencyReportMessage;

