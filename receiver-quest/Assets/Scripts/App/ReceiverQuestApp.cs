using System;
using System.Threading.Tasks;
using UnityEngine;
using X5Quest.Latency;
using X5Quest.Rendering;
using X5Quest.Signaling;
using X5Quest.WebRTC;

namespace X5Quest.App
{
    public sealed class ReceiverQuestApp : MonoBehaviour
    {
        [Header("Signaling")]
        [SerializeField] private string signalingUrl = "wss://x5-webrtc-signaling.lord-sasapple.workers.dev";
        [SerializeField] private string roomId = "x5-test-room";
        [SerializeField] private PreferredCodec preferredCodec = PreferredCodec.Hevc;

        [Header("Scene")]
        [SerializeField] private InsideOutSphereRenderer sphereRenderer;
        [SerializeField] private LatencyOverlay overlay;

        private SignalingClient signaling;
        private IQuestWebRTCClient webRTC;
        private readonly LatencyTracker latencyTracker = new LatencyTracker();
        private float lastStatsPoll;

        private async void Start()
        {
            EnsureSceneObjects();
            overlay.SetStatus("starting");

            webRTC = QuestWebRTCClientFactory.Create();
            if (webRTC is AndroidQuestWebRTCClient androidClient)
            {
                EnsureRouter().Client = androidClient;
            }

            webRTC.Log += message => UnityMainThreadQueue.Enqueue(() => Log(message));
            webRTC.LocalAnswerReady += sdp => UnityMainThreadQueue.Enqueue(() => OnLocalAnswerReady(sdp));
            webRTC.LocalIceCandidateReady += candidate => UnityMainThreadQueue.Enqueue(() => OnLocalIceCandidateReady(candidate));
            webRTC.DataChannelMessageReceived += text => UnityMainThreadQueue.Enqueue(() => OnDataChannelMessage(text));
            webRTC.StatsUpdated += stats => UnityMainThreadQueue.Enqueue(() => OnStatsUpdated(stats));
            webRTC.TextureReady += texture => UnityMainThreadQueue.Enqueue(() => sphereRenderer.SetTexture(texture));
            webRTC.Initialize(preferredCodec);

            signaling = new SignalingClient();
            signaling.Log += message => UnityMainThreadQueue.Enqueue(() => Log(message));
            signaling.MessageReceived += message => UnityMainThreadQueue.Enqueue(() => OnSignalingMessage(message));

            try
            {
                await signaling.ConnectAsync(signalingUrl, roomId);
                overlay.SetStatus($"joined room={roomId}");
            }
            catch (Exception ex)
            {
                overlay.SetStatus("signaling error");
                Log($"signaling接続失敗: {ex.Message}");
            }
        }

        private void Update()
        {
            if (Time.realtimeSinceStartup - lastStatsPoll > 1f)
            {
                lastStatsPoll = Time.realtimeSinceStartup;
                webRTC?.PollStats();
            }

            latencyTracker.MarkRenderSubmit();
            if (latencyTracker.LastReport != null)
            {
                overlay.SetLatency(latencyTracker.LastReport);
            }
        }

        private async void OnDestroy()
        {
            if (signaling != null)
            {
                await signaling.DisconnectAsync();
                signaling.Dispose();
            }
            webRTC?.Shutdown();
            webRTC?.Dispose();
        }

        private void OnSignalingMessage(SignalingMessage message)
        {
            switch (message.Type)
            {
                case SignalingMessageType.Joined:
                    overlay.SetStatus($"joined {message.RoomId}");
                    break;
                case SignalingMessageType.PeerJoined:
                    overlay.SetStatus($"peer joined {message.Role}");
                    break;
                case SignalingMessageType.Offer:
                    overlay.SetStatus("offer received");
                    Log($"offer受信: sdpBytes={message.Sdp.Length}");
                    webRTC.SetRemoteOffer(message.Sdp);
                    break;
                case SignalingMessageType.IceCandidate:
                    webRTC.AddRemoteIceCandidate(message.Candidate);
                    break;
                case SignalingMessageType.PeerLeft:
                    overlay.SetStatus("peer left");
                    break;
                case SignalingMessageType.LatencySync:
                    _ = signaling.SendAsync(SignalingMessage.LatencyEcho(message.Sequence, message.SenderTimeMs, DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()));
                    break;
                case SignalingMessageType.Error:
                    overlay.SetStatus($"error: {message.ErrorMessage}");
                    Log($"signaling error: {message.ErrorMessage}");
                    break;
            }
        }

        private void OnLocalAnswerReady(string sdp)
        {
            _ = signaling.SendAsync(SignalingMessage.Answer(sdp));
            overlay.SetStatus("answer sent");
        }

        private void OnLocalIceCandidateReady(IceCandidatePayload candidate)
        {
            _ = signaling.SendAsync(SignalingMessage.IceCandidate(candidate));
        }

        private void OnDataChannelMessage(string text)
        {
            if (FrameTimestampMessage.TryParse(text, out var timestamp))
            {
                var report = latencyTracker.OnFrameTimestamp(timestamp);
                overlay.SetLatency(report);
                Log($"frame latency report: {report.ToJson()}");
            }
            else
            {
                Log($"DataChannel message: {text}");
            }
        }

        private void OnStatsUpdated(ReceiverStatsSnapshot stats)
        {
            overlay.SetStats(stats);
            if (stats.softwareDecoder)
            {
                Log($"警告: software decodeの可能性があります decoder={stats.decoderName}");
            }
        }

        private void EnsureSceneObjects()
        {
            if (sphereRenderer == null)
            {
                var sphere = new GameObject("InsideOutSphere");
                sphere.transform.SetParent(transform, false);
                sphereRenderer = sphere.AddComponent<InsideOutSphereRenderer>();
            }

            if (overlay == null)
            {
                overlay = gameObject.AddComponent<LatencyOverlay>();
            }

            if (FindObjectOfType<UnityMainThreadQueue>() == null)
            {
                new GameObject("UnityMainThreadQueue").AddComponent<UnityMainThreadQueue>();
            }
        }

        private NativeBridgeMessageRouter EnsureRouter()
        {
            var existing = FindObjectOfType<NativeBridgeMessageRouter>();
            if (existing != null)
            {
                return existing;
            }

            return new GameObject(NativeBridgeMessageRouter.GameObjectName).AddComponent<NativeBridgeMessageRouter>();
        }

        private void Log(string message)
        {
            Debug.Log($"[X5QuestReceiver] {message}");
        }
    }
}
