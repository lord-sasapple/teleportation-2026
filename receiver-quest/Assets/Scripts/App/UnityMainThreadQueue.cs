using System;
using System.Collections.Concurrent;
using UnityEngine;

namespace X5Quest.App
{
    public sealed class UnityMainThreadQueue : MonoBehaviour
    {
        private static readonly ConcurrentQueue<Action> Queue = new ConcurrentQueue<Action>();

        public static void Enqueue(Action action)
        {
            if (action != null)
            {
                Queue.Enqueue(action);
            }
        }

        private void Update()
        {
            while (Queue.TryDequeue(out var action))
            {
                action();
            }
        }
    }
}

