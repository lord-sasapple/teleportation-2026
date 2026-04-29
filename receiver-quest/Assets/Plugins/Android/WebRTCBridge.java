package com.telepresence.x5quest;

import android.util.Log;

public final class WebRTCBridge {
    private static final String TAG = "X5QuestWebRTCBridge";
    private String unityReceiver;
    private String preferredCodec;

    public void initialize(String unityReceiver, String preferredCodec) {
        this.unityReceiver = unityReceiver;
        this.preferredCodec = preferredCodec;
        Log.w(TAG, "WebRTCBridge Java stub initialized. Native libwebrtc/MediaCodec implementation is pending. preferredCodec=" + preferredCodec);
    }

    public long getExternalTexturePtr() {
        return 0L;
    }

    public void setRemoteOffer(String sdp) {
        Log.w(TAG, "setRemoteOffer stub: sdpBytes=" + (sdp == null ? 0 : sdp.length()));
    }

    public void addRemoteIceCandidate(String candidate, String sdpMid, int sdpMLineIndex) {
        Log.w(TAG, "addRemoteIceCandidate stub: candidateBytes=" + (candidate == null ? 0 : candidate.length()));
    }

    public String pollStatsJson() {
        return "{\"codec\":\"" + preferredCodec + "\",\"decoderName\":\"android-java-stub\",\"softwareDecoder\":true}";
    }

    public void shutdown() {
        Log.w(TAG, "shutdown stub");
    }
}

