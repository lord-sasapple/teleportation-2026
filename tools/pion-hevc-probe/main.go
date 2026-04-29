package main

import (
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/pion/webrtc/v4"
)

func must[T any](value T, err error) T {
	if err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}
	return value
}

func printCodecLines(sdp string) bool {
	hasH265 := false

	fmt.Println("offer codec lines:")
	for _, line := range strings.Split(sdp, "\n") {
		line = strings.TrimSpace(line)
		upper := strings.ToUpper(line)

		if strings.HasPrefix(line, "m=video") ||
			(strings.HasPrefix(line, "a=rtpmap:") &&
				(strings.Contains(upper, "H265") ||
					strings.Contains(upper, "HEVC") ||
					strings.Contains(upper, "H264") ||
					strings.Contains(upper, "VP8") ||
					strings.Contains(upper, "VP9") ||
					strings.Contains(upper, "AV1"))) ||
			(strings.HasPrefix(line, "a=fmtp:") &&
				(strings.Contains(upper, "TX-MODE") ||
					strings.Contains(upper, "PROFILE-ID") ||
					strings.Contains(upper, "LEVEL-ID") ||
					strings.Contains(upper, "APT="))) {
			fmt.Println("  " + line)
		}

		if strings.Contains(upper, "H265/90000") || strings.Contains(upper, "HEVC/90000") {
			hasH265 = true
		}
	}

	return hasH265
}

func main() {
	fmt.Println("===== Pion HEVC/H.265 WebRTC probe =====")

	var mediaEngine webrtc.MediaEngine
	must(struct{}{}, mediaEngine.RegisterDefaultCodecs())

	api := webrtc.NewAPI(
		webrtc.WithMediaEngine(&mediaEngine),
	)

	peerConnection := must(api.NewPeerConnection(webrtc.Configuration{
		ICEServers: []webrtc.ICEServer{
			{
				URLs: []string{"stun:stun.l.google.com:19302"},
			},
		},
	}))
	defer func() {
		_ = peerConnection.Close()
	}()

	track := must(webrtc.NewTrackLocalStaticSample(
		webrtc.RTPCodecCapability{
			MimeType:     webrtc.MimeTypeH265,
			ClockRate:    90000,
			SDPFmtpLine:  "level-id=180;profile-id=1;tier-flag=0;tx-mode=SRST",
			RTCPFeedback: []webrtc.RTCPFeedback{{Type: "nack"}, {Type: "nack", Parameter: "pli"}, {Type: "ccm", Parameter: "fir"}},
		},
		"x5-hevc-video",
		"teleportation-hevc",
	))

	rtpSender := must(peerConnection.AddTrack(track))

	go func() {
		buf := make([]byte, 1500)
		for {
			if _, _, err := rtpSender.Read(buf); err != nil {
				return
			}
		}
	}()

	offer := must(peerConnection.CreateOffer(nil))

	gatherComplete := webrtc.GatheringCompletePromise(peerConnection)
	must(struct{}{}, peerConnection.SetLocalDescription(offer))

	select {
	case <-gatherComplete:
	case <-time.After(5 * time.Second):
		fmt.Println("warn: ICE gathering timeout; printing local description anyway")
	}

	localDescription := peerConnection.LocalDescription()
	if localDescription == nil {
		fmt.Println("RESULT: failed; local description is nil")
		os.Exit(1)
	}

	hasH265 := printCodecLines(localDescription.SDP)

	fmt.Println("has SDP HEVC/H265:", hasH265)
	if hasH265 {
		fmt.Println("RESULT: Pion exposes HEVC/H.265 in offer SDP")
	} else {
		fmt.Println("RESULT: Pion does NOT expose HEVC/H.265 in offer SDP")
	}

	fmt.Println("========================================")
}
