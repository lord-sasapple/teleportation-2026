using System;
using Newtonsoft.Json;
using UnityEngine;
using X5Quest.Signaling;

namespace X5Quest.WebRTC
{
    public sealed class AndroidQuestWebRTCClient : IQuestWebRTCClient
    {
        private AndroidJavaObject bridge;
        private Texture externalTexture;

        public event Action<string> LocalAnswerReady;
        public event Action<IceCandidatePayload> LocalIceCandidateReady;
        public event Action<string> DataChannelMessageReceived;
        public event Action<ReceiverStatsSnapshot> StatsUpdated;
        public event Action<Texture> TextureReady;
        public event Action<string> Log;

        public bool IsAvailable => bridge != null;

        public void Initialize(PreferredCodec preferredCodec)
        {
            try
            {
                bridge = new AndroidJavaObject("com.telepresence.x5quest.WebRTCBridge");
                bridge.Call("initialize", NativeBridgeMessageRouter.GameObjectName, preferredCodec == PreferredCodec.Hevc ? "hevc" : "h264");
                Log?.Invoke($"Android WebRTCBridgeを初期化しました: preferredCodec={preferredCodec}");

                var texturePtr = bridge.Call<long>("getExternalTexturePtr");
                if (texturePtr != 0)
                {
                    externalTexture = Texture2D.CreateExternalTexture(2880, 1440, TextureFormat.RGBA32, false, false, new IntPtr(texturePtr));
                    TextureReady?.Invoke(externalTexture);
                }
            }
            catch (Exception ex)
            {
                Log?.Invoke($"Android WebRTCBridge初期化に失敗しました: {ex.Message}");
                bridge = null;
            }
        }

        public void SetRemoteOffer(string sdp)
        {
            bridge?.Call("setRemoteOffer", sdp);
        }

        public void AddRemoteIceCandidate(IceCandidatePayload candidate)
        {
            if (candidate == null)
            {
                return;
            }

            bridge?.Call("addRemoteIceCandidate", candidate.candidate, candidate.sdpMid ?? string.Empty, candidate.sdpMLineIndex ?? 0);
        }

        public void PollStats()
        {
            if (bridge == null)
            {
                return;
            }

            var statsJson = bridge.Call<string>("pollStatsJson");
            if (!string.IsNullOrEmpty(statsJson))
            {
                StatsUpdated?.Invoke(JsonConvert.DeserializeObject<ReceiverStatsSnapshot>(statsJson));
            }
        }

        public void Shutdown()
        {
            bridge?.Call("shutdown");
            bridge?.Dispose();
            bridge = null;
        }

        public void Dispose()
        {
            Shutdown();
        }

        internal void OnLocalAnswer(string sdp)
        {
            LocalAnswerReady?.Invoke(sdp);
        }

        internal void OnLocalIceCandidate(string json)
        {
            LocalIceCandidateReady?.Invoke(JsonConvert.DeserializeObject<IceCandidatePayload>(json));
        }

        internal void OnDataChannelMessage(string text)
        {
            DataChannelMessageReceived?.Invoke(text);
        }
    }
}

