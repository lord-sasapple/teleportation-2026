using System;
using System.Net.WebSockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using UnityEngine;

namespace X5Quest.Signaling
{
    public sealed class SignalingClient : IDisposable
    {
        private ClientWebSocket socket;
        private CancellationTokenSource cancellation;
        private readonly byte[] receiveBuffer = new byte[64 * 1024];

        public event Action<SignalingMessage> MessageReceived;
        public event Action<string> Log;

        public WebSocketState State => socket?.State ?? WebSocketState.None;

        public async Task ConnectAsync(string baseUrl, string roomId)
        {
            cancellation = new CancellationTokenSource();
            socket = new ClientWebSocket();
            var uri = BuildRoomUri(baseUrl, roomId);
            Log?.Invoke($"signalingへ接続します: {uri}");
            await socket.ConnectAsync(uri, cancellation.Token);
            _ = Task.Run(ReceiveLoop);
            await SendAsync(SignalingMessage.Join(roomId));
            await SendAsync(SignalingMessage.Ping());
        }

        public async Task SendAsync(string json)
        {
            if (socket == null || socket.State != WebSocketState.Open)
            {
                Log?.Invoke("signaling送信をスキップしました: WebSocket未接続");
                return;
            }

            var bytes = Encoding.UTF8.GetBytes(json);
            await socket.SendAsync(new ArraySegment<byte>(bytes), WebSocketMessageType.Text, true, cancellation.Token);
        }

        public async Task DisconnectAsync()
        {
            if (socket == null)
            {
                return;
            }

            try
            {
                if (socket.State == WebSocketState.Open)
                {
                    await SendAsync(SignalingMessage.Leave());
                    await socket.CloseAsync(WebSocketCloseStatus.NormalClosure, "leave", CancellationToken.None);
                }
            }
            catch (Exception ex)
            {
                Log?.Invoke($"signaling切断中に例外: {ex.Message}");
            }
            finally
            {
                cancellation?.Cancel();
                socket.Dispose();
                socket = null;
            }
        }

        public void Dispose()
        {
            cancellation?.Cancel();
            socket?.Dispose();
            cancellation?.Dispose();
        }

        private async Task ReceiveLoop()
        {
            var builder = new StringBuilder();

            while (socket != null && socket.State == WebSocketState.Open && !cancellation.IsCancellationRequested)
            {
                try
                {
                    var result = await socket.ReceiveAsync(new ArraySegment<byte>(receiveBuffer), cancellation.Token);
                    if (result.MessageType == WebSocketMessageType.Close)
                    {
                        Log?.Invoke("signalingがcloseされました");
                        return;
                    }

                    builder.Append(Encoding.UTF8.GetString(receiveBuffer, 0, result.Count));
                    if (!result.EndOfMessage)
                    {
                        continue;
                    }

                    var text = builder.ToString();
                    builder.Clear();
                    var message = SignalingMessage.Parse(text);
                    MessageReceived?.Invoke(message);
                }
                catch (Exception ex)
                {
                    if (!cancellation.IsCancellationRequested)
                    {
                        Log?.Invoke($"signaling受信エラー: {ex.Message}");
                    }
                    return;
                }
            }
        }

        private static Uri BuildRoomUri(string baseUrl, string roomId)
        {
            var builder = new UriBuilder(baseUrl);
            if (builder.Scheme == "http")
            {
                builder.Scheme = "ws";
            }
            else if (builder.Scheme == "https")
            {
                builder.Scheme = "wss";
            }

            builder.Path = $"/room/{Uri.EscapeDataString(roomId)}";
            builder.Query = "role=receiver";
            return builder.Uri;
        }
    }
}

