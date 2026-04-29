using UnityEngine;
using X5Quest.WebRTC;

namespace X5Quest.Latency
{
    public sealed class LatencyOverlay : MonoBehaviour
    {
        [SerializeField] private bool visible = true;
        private readonly GUIStyle style = new GUIStyle();
        private ReceiverStatsSnapshot stats;
        private FrameLatencyReportMessage latencyReport;
        private string status = "boot";

        private void Awake()
        {
            style.fontSize = 28;
            style.normal.textColor = Color.green;
            style.alignment = TextAnchor.UpperLeft;
            style.wordWrap = false;
        }

        public void SetStatus(string value)
        {
            status = value;
        }

        public void SetStats(ReceiverStatsSnapshot snapshot)
        {
            stats = snapshot;
        }

        public void SetLatency(FrameLatencyReportMessage report)
        {
            latencyReport = report;
        }

        private void OnGUI()
        {
            if (!visible)
            {
                return;
            }

            var text =
                $"X5 Quest Receiver\n" +
                $"status: {status}\n" +
                $"codec: {stats?.codec ?? "unknown"}\n" +
                $"decoder: {stats?.decoderName ?? "unknown"} {(stats != null && stats.softwareDecoder ? "(software?)" : "")}\n" +
                $"candidate: {stats?.localCandidateType ?? "?"}->{stats?.remoteCandidateType ?? "?"}\n" +
                $"rttMs: {stats?.currentRoundTripTimeMs ?? 0:0.0} jitterMs: {stats?.jitterMs ?? 0:0.0}\n" +
                $"frames: recv={stats?.framesReceived ?? 0} decoded={stats?.framesDecoded ?? 0} dropped={stats?.framesDropped ?? 0}\n" +
                $"size/fps: {stats?.frameWidth ?? 0}x{stats?.frameHeight ?? 0} @ {stats?.framesPerSecond ?? 0:0.0}\n" +
                $"latency seq: {latencyReport?.sequence ?? 0}\n" +
                $"estimatedAppLatencyMs: {latencyReport?.estimatedAppLatencyMs ?? 0}";

            GUI.Label(new Rect(24, 24, 1200, 460), text, style);
        }
    }
}

