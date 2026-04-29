using System;
using Newtonsoft.Json;

namespace X5Quest.Latency
{
    [Serializable]
    public sealed class FrameTimestampMessage
    {
        public string type;
        public long sequence;
        public long captureTimeMs;
        public long encodeStartTimeMs;
        public long encodeEndTimeMs;
        public long sendTimeMs;

        public static bool TryParse(string json, out FrameTimestampMessage message)
        {
            message = null;
            try
            {
                var parsed = JsonConvert.DeserializeObject<FrameTimestampMessage>(json);
                if (parsed?.type != "frame-timestamp")
                {
                    return false;
                }

                message = parsed;
                return true;
            }
            catch
            {
                return false;
            }
        }
    }

    [Serializable]
    public sealed class FrameLatencyReportMessage
    {
        public string type = "frame-latency-report";
        public long sequence;
        public long captureTimeMs;
        public long encodeEndTimeMs;
        public long receiverDataTimeMs;
        public long firstFrameSeenTimeMs;
        public long renderSubmitTimeMs;
        public long estimatedAppLatencyMs;

        public string ToJson()
        {
            return JsonConvert.SerializeObject(this);
        }
    }

    public sealed class LatencyTracker
    {
        public FrameLatencyReportMessage LastReport { get; private set; }

        public FrameLatencyReportMessage OnFrameTimestamp(FrameTimestampMessage timestamp)
        {
            var now = UnixTimeMs();
            LastReport = new FrameLatencyReportMessage
            {
                sequence = timestamp.sequence,
                captureTimeMs = timestamp.captureTimeMs,
                encodeEndTimeMs = timestamp.encodeEndTimeMs,
                receiverDataTimeMs = now,
                firstFrameSeenTimeMs = now,
                renderSubmitTimeMs = now,
                estimatedAppLatencyMs = now - timestamp.captureTimeMs
            };
            return LastReport;
        }

        public void MarkRenderSubmit()
        {
            if (LastReport == null)
            {
                return;
            }

            LastReport.renderSubmitTimeMs = UnixTimeMs();
            LastReport.estimatedAppLatencyMs = LastReport.renderSubmitTimeMs - LastReport.captureTimeMs;
        }

        private static long UnixTimeMs()
        {
            return DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
        }
    }
}

