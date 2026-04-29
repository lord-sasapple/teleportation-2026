using System;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace X5Quest.Signaling
{
    public enum SignalingRole
    {
        Sender,
        Receiver
    }

    [Serializable]
    public sealed class IceCandidatePayload
    {
        public string candidate;
        public string sdpMid;
        public int? sdpMLineIndex;
    }

    public enum SignalingMessageType
    {
        Joined,
        PeerJoined,
        Offer,
        Answer,
        IceCandidate,
        PeerLeft,
        Pong,
        Error,
        LatencySync,
        LatencyEcho,
        Unknown
    }

    public sealed class SignalingMessage
    {
        public SignalingMessageType Type { get; private set; }
        public string RawType { get; private set; }
        public string RoomId { get; private set; }
        public SignalingRole Role { get; private set; }
        public string Sdp { get; private set; }
        public IceCandidatePayload Candidate { get; private set; }
        public string ErrorMessage { get; private set; }
        public long Sequence { get; private set; }
        public long SenderTimeMs { get; private set; }
        public long ReceiverTimeMs { get; private set; }

        public static SignalingMessage Parse(string json)
        {
            var obj = JObject.Parse(json);
            var type = obj.Value<string>("type") ?? "unknown";
            var message = new SignalingMessage { RawType = type, Type = MapType(type) };

            message.RoomId = obj.Value<string>("roomId") ?? string.Empty;
            message.Role = ParseRole(obj.Value<string>("role"));
            message.Sdp = obj.Value<string>("sdp") ?? string.Empty;
            message.ErrorMessage = obj.Value<string>("message") ?? string.Empty;
            message.Sequence = obj.Value<long?>("sequence") ?? 0;
            message.SenderTimeMs = obj.Value<long?>("senderTimeMs") ?? 0;
            message.ReceiverTimeMs = obj.Value<long?>("receiverTimeMs") ?? 0;

            var candidate = obj["candidate"];
            if (candidate != null)
            {
                message.Candidate = candidate.ToObject<IceCandidatePayload>();
            }

            return message;
        }

        public static string Join(string roomId)
        {
            return JsonConvert.SerializeObject(new
            {
                type = "join",
                roomId,
                role = "receiver"
            });
        }

        public static string Answer(string sdp)
        {
            return JsonConvert.SerializeObject(new { type = "answer", sdp });
        }

        public static string IceCandidate(IceCandidatePayload candidate)
        {
            return JsonConvert.SerializeObject(new { type = "ice-candidate", candidate });
        }

        public static string Leave()
        {
            return JsonConvert.SerializeObject(new { type = "leave" });
        }

        public static string Ping()
        {
            return JsonConvert.SerializeObject(new { type = "ping" });
        }

        public static string LatencyEcho(long sequence, long senderTimeMs, long receiverTimeMs)
        {
            return JsonConvert.SerializeObject(new
            {
                type = "latency-echo",
                sequence,
                senderTimeMs,
                receiverTimeMs
            });
        }

        private static SignalingMessageType MapType(string type)
        {
            switch (type)
            {
                case "joined": return SignalingMessageType.Joined;
                case "peer-joined": return SignalingMessageType.PeerJoined;
                case "offer": return SignalingMessageType.Offer;
                case "answer": return SignalingMessageType.Answer;
                case "ice-candidate": return SignalingMessageType.IceCandidate;
                case "peer-left": return SignalingMessageType.PeerLeft;
                case "pong": return SignalingMessageType.Pong;
                case "error": return SignalingMessageType.Error;
                case "latency-sync": return SignalingMessageType.LatencySync;
                case "latency-echo": return SignalingMessageType.LatencyEcho;
                default: return SignalingMessageType.Unknown;
            }
        }

        private static SignalingRole ParseRole(string role)
        {
            return role == "sender" ? SignalingRole.Sender : SignalingRole.Receiver;
        }
    }
}

