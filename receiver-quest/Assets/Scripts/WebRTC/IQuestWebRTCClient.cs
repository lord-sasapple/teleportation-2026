using System;
using UnityEngine;
using X5Quest.Signaling;

namespace X5Quest.WebRTC
{
    public enum PreferredCodec
    {
        Hevc,
        H264
    }

    public sealed class ReceiverStatsSnapshot
    {
        public string selectedCandidatePair;
        public string localCandidateType;
        public string remoteCandidateType;
        public float currentRoundTripTimeMs;
        public float jitterMs;
        public float jitterBufferDelayMs;
        public float jitterBufferTargetDelayMs;
        public int packetsLost;
        public int framesReceived;
        public int framesDecoded;
        public int framesDropped;
        public int frameWidth;
        public int frameHeight;
        public float framesPerSecond;
        public string codec;
        public string decoderName;
        public bool softwareDecoder;
    }

    public interface IQuestWebRTCClient : IDisposable
    {
        event Action<string> LocalAnswerReady;
        event Action<IceCandidatePayload> LocalIceCandidateReady;
        event Action<string> DataChannelMessageReceived;
        event Action<ReceiverStatsSnapshot> StatsUpdated;
        event Action<Texture> TextureReady;
        event Action<string> Log;

        bool IsAvailable { get; }
        void Initialize(PreferredCodec preferredCodec);
        void SetRemoteOffer(string sdp);
        void AddRemoteIceCandidate(IceCandidatePayload candidate);
        void PollStats();
        void Shutdown();
    }
}

