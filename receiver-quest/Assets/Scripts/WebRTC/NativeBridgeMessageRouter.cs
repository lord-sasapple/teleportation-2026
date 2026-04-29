using UnityEngine;

namespace X5Quest.WebRTC
{
    public sealed class NativeBridgeMessageRouter : MonoBehaviour
    {
        public const string GameObjectName = "NativeBridgeMessageRouter";
        public static NativeBridgeMessageRouter Instance { get; private set; }
        public AndroidQuestWebRTCClient Client { get; set; }

        private void Awake()
        {
            if (Instance != null && Instance != this)
            {
                Destroy(gameObject);
                return;
            }

            Instance = this;
            gameObject.name = GameObjectName;
            DontDestroyOnLoad(gameObject);
        }

        public void OnLocalAnswer(string sdp)
        {
            Client?.OnLocalAnswer(sdp);
        }

        public void OnLocalIceCandidate(string json)
        {
            Client?.OnLocalIceCandidate(json);
        }

        public void OnDataChannelMessage(string text)
        {
            Client?.OnDataChannelMessage(text);
        }
    }
}

