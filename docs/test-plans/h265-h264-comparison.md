# H.265 / H.264 Comparison Test Plan

This test keeps the architecture as WebRTC 1:1 P2P. The signaling-worker only exchanges SDP, ICE candidates, and lightweight latency control JSON.

## Preconditions

- X5 is connected to MacBook M3 in USB Webcam Mode.
- Quest 3 receiver is installed and joins the same room.
- sender-mac builds with `WEBRTC_PROVIDER=livekit`.
- Signaling URL is reachable:

```bash
curl https://x5-webrtc-signaling.lord-sasapple.workers.dev/healthz
```

## Sender Smoke Test

Without camera:

```bash
cd sender-mac
WEBRTC_PROVIDER=livekit ./Scripts/run-signaling-only.sh
```

Confirm:

- sender-mac starts.
- signaling-worker returns `joined` and `pong`.
- no media relay is used.

With X5 camera:

```bash
cd sender-mac
WEBRTC_PROVIDER=livekit ./Scripts/run-sender-smoke.sh
```

Confirm:

- X5 appears in device list.
- 2880x1440 / 30fps format appears.
- supported codecs log includes H265/HEVC or clearly falls back to H.264.

## HEVC/H.265 Run

Quest receiver should join:

```text
wss://x5-webrtc-signaling.lord-sasapple.workers.dev/room/x5-codec-test-hevc?role=receiver
```

Sender:

```bash
cd sender-mac
WEBRTC_PROVIDER=livekit xcrun swift run sender-mac \
  --device-name "Insta360 X5" \
  --width 2880 \
  --height 1440 \
  --fps 30 \
  --codec hevc \
  --bitrate 18000000 \
  --signaling-url wss://x5-webrtc-signaling.lord-sasapple.workers.dev \
  --room x5-codec-test-hevc \
  --duration 60
```

Record:

- SDP codec lines for H265/HEVC/H264.
- selected codec from receiver overlay.
- decoder name from receiver overlay.
- software decoder warning if present.
- current RTT, jitter, packets lost, frames decoded, frames dropped.
- estimated app latency from DataChannel timestamps.
- glass-to-glass latency from camera measurement.

## H.264 Run

Quest receiver should join:

```text
wss://x5-webrtc-signaling.lord-sasapple.workers.dev/room/x5-codec-test-h264?role=receiver
```

Sender:

```bash
cd sender-mac
WEBRTC_PROVIDER=livekit xcrun swift run sender-mac \
  --device-name "Insta360 X5" \
  --width 2880 \
  --height 1440 \
  --fps 30 \
  --codec h264 \
  --bitrate 16000000 \
  --signaling-url wss://x5-webrtc-signaling.lord-sasapple.workers.dev \
  --room x5-codec-test-h264 \
  --duration 60
```

## Automated Sender Sweep

This runs HEVC then H.264 with matching resolution/fps and separate rooms:

```bash
cd sender-mac
WEBRTC_PROVIDER=livekit DURATION=60 ./Scripts/run-codec-comparison.sh
```

## Comparison Table

| Field | HEVC/H.265 | H.264 |
| --- | --- | --- |
| selectedCandidatePair | | |
| localCandidateType | | |
| remoteCandidateType | | |
| currentRoundTripTime | | |
| availableOutgoingBitrate | | |
| jitter | | |
| jitterBufferDelay | | |
| packetsLost | | |
| framesDecoded | | |
| framesDropped | | |
| codec | | |
| decoderName | | |
| softwareDecoder warning | | |
| estimatedAppLatencyMs median | | |
| glassToGlassLatencyMs median | | |
| glassToGlassLatencyMs p90 | | |

## Pass Criteria

- Signaling succeeds without media relay.
- selected candidate pair is preferably `host` or `srflx`.
- HEVC/H.265 is attempted first.
- If HEVC fails, H.264 fallback establishes P2P.
- Receiver overlay shows codec, decoder, frame rate, dropped frames, and latency.
- Final latency number comes from glass-to-glass measurement.
