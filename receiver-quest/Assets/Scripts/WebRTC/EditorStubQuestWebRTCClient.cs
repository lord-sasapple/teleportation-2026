using System;
using UnityEngine;
using X5Quest.Signaling;

namespace X5Quest.WebRTC
{
    public sealed class EditorStubQuestWebRTCClient : IQuestWebRTCClient
    {
        private float lastStatsTime;
        private readonly Texture2D placeholderTexture;

        public event Action<string> LocalAnswerReady;
        public event Action<IceCandidatePayload> LocalIceCandidateReady;
        public event Action<string> DataChannelMessageReceived;
        public event Action<ReceiverStatsSnapshot> StatsUpdated;
        public event Action<Texture> TextureReady;
        public event Action<string> Log;

        public bool IsAvailable => false;

        public EditorStubQuestWebRTCClient()
        {
            placeholderTexture = new Texture2D(2, 2, TextureFormat.RGBA32, false);
            placeholderTexture.SetPixels(new[] { Color.black, Color.gray, Color.gray, Color.black });
            placeholderTexture.Apply();
        }

        public void Initialize(PreferredCodec preferredCodec)
        {
            Log?.Invoke($"Editor stub WebRTC receiverです。preferredCodec={preferredCodec}");
            TextureReady?.Invoke(placeholderTexture);
        }

        public void SetRemoteOffer(string sdp)
        {
            Log?.Invoke($"stub remote offer受信: sdpBytes={sdp.Length}");
            LocalAnswerReady?.Invoke("v=0\r\ns=-\r\n");
        }

        public void AddRemoteIceCandidate(IceCandidatePayload candidate)
        {
            Log?.Invoke($"stub remote ICE受信: candidateBytes={candidate?.candidate?.Length ?? 0}");
        }

        public void PollStats()
        {
            if (Time.realtimeSinceStartup - lastStatsTime < 1f)
            {
                return;
            }

            lastStatsTime = Time.realtimeSinceStartup;
            StatsUpdated?.Invoke(new ReceiverStatsSnapshot
            {
                selectedCandidatePair = "stub",
                localCandidateType = "unknown",
                remoteCandidateType = "unknown",
                codec = "stub",
                decoderName = "editor-stub",
                frameWidth = 2880,
                frameHeight = 1440,
                framesPerSecond = 30
            });
        }

        public void Shutdown()
        {
            Log?.Invoke("stub WebRTC receiverを停止しました");
        }

        public void Dispose()
        {
            Shutdown();
        }
    }
}

