using UnityEngine;

namespace X5Quest.WebRTC
{
    public static class QuestWebRTCClientFactory
    {
        public static IQuestWebRTCClient Create()
        {
#if UNITY_ANDROID && !UNITY_EDITOR
            return new AndroidQuestWebRTCClient();
#else
            return new EditorStubQuestWebRTCClient();
#endif
        }
    }
}

