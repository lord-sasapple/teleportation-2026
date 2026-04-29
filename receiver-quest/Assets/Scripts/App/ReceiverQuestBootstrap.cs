using UnityEngine;

namespace X5Quest.App
{
    public static class ReceiverQuestBootstrap
    {
        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        private static void EnsureReceiverApp()
        {
            if (Object.FindObjectOfType<ReceiverQuestApp>() != null)
            {
                return;
            }

            var app = new GameObject("ReceiverQuestApp");
            app.AddComponent<ReceiverQuestApp>();
            Object.DontDestroyOnLoad(app);
            Debug.Log("[X5QuestReceiver] ReceiverQuestAppを自動生成しました");
        }
    }
}
