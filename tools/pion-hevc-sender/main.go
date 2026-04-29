package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"strings"
	"sync/atomic"
	"time"

	"github.com/pion/webrtc/v4"
	"nhooyr.io/websocket"
)

type signalMessage struct {
	Type      string          `json:"type"`
	RoomID    string          `json:"roomId,omitempty"`
	Role      string          `json:"role,omitempty"`
	SDP       string          `json:"sdp,omitempty"`
	Candidate *candidateValue `json:"candidate,omitempty"`
	Message   string          `json:"message,omitempty"`
}

type candidateValue struct {
	Candidate     string `json:"candidate"`
	SDPMid        string `json:"sdpMid,omitempty"`
	SDPMLineIndex uint16 `json:"sdpMLineIndex,omitempty"`
}

type config struct {
	room         string
	signalingURL string
	duration     time.Duration
}

func main() {
	cfg := parseFlags()

	log.Printf("== Pion HEVC sender ==")
	log.Printf("room=%s", cfg.room)
	log.Printf("signaling=%s", cfg.signalingURL)
	log.Printf("duration=%s", cfg.duration)

	ctx, cancel := context.WithTimeout(context.Background(), cfg.duration)
	defer cancel()

	if err := run(ctx, cfg); err != nil {
		log.Fatalf("fatal: %v", err)
	}
}

func parseFlags() config {
	var cfg config
	flag.StringVar(&cfg.room, "room", "pion-hevc-test-001", "signaling room id")
	flag.StringVar(&cfg.signalingURL, "signaling-url", "wss://x5-webrtc-signaling.lord-sasapple.workers.dev", "signaling worker base URL")
	durationSeconds := flag.Int("duration", 600, "run duration seconds")
	flag.Parse()

	cfg.duration = time.Duration(*durationSeconds) * time.Second
	return cfg
}

func run(ctx context.Context, cfg config) error {
	pc, err := newPeerConnection()
	if err != nil {
		return err
	}
	defer pc.Close()

	var wsReady atomic.Bool
	var wsConn *websocket.Conn

	pc.OnICEConnectionStateChange(func(state webrtc.ICEConnectionState) {
		log.Printf("ICE connection state: %s", state.String())
	})
	pc.OnConnectionStateChange(func(state webrtc.PeerConnectionState) {
		log.Printf("PeerConnection state: %s", state.String())
	})
	pc.OnICEGatheringStateChange(func(state webrtc.ICEGatheringState) {
		log.Printf("ICE gathering state: %s", state.String())
	})
	pc.OnICECandidate(func(c *webrtc.ICECandidate) {
		if c == nil {
			log.Printf("ICE candidate gathering complete")
			return
		}
		if !wsReady.Load() || wsConn == nil {
			log.Printf("ICE candidate generated before signaling ready; skip")
			return
		}
		init := c.ToJSON()
		payload := signalMessage{
			Type: "ice-candidate",
			Candidate: &candidateValue{
				Candidate:     init.Candidate,
				SDPMid:        derefString(init.SDPMid),
				SDPMLineIndex: derefUint16(init.SDPMLineIndex),
			},
		}
		if err := writeJSON(context.Background(), wsConn, payload); err != nil {
			log.Printf("failed to send ICE candidate: %v", err)
			return
		}
		log.Printf("signaling send: ice-candidate mid=%s mline=%d", derefString(init.SDPMid), derefUint16(init.SDPMLineIndex))
	})

	if err := addH265Track(pc); err != nil {
		return err
	}

	wsURL := strings.TrimRight(cfg.signalingURL, "/") + "/room/" + cfg.room + "?role=sender"
	c, _, err := websocket.Dial(ctx, wsURL, nil)
	if err != nil {
		return fmt.Errorf("connect signaling: %w", err)
	}
	defer c.Close(websocket.StatusNormalClosure, "done")
	wsConn = c
	wsReady.Store(true)

	log.Printf("signaling connected: %s", wsURL)

	if err := writeJSON(ctx, c, signalMessage{Type: "join", RoomID: cfg.room, Role: "sender"}); err != nil {
		return fmt.Errorf("send join: %w", err)
	}
	log.Printf("signaling send: join")

	offer, err := pc.CreateOffer(nil)
	if err != nil {
		return fmt.Errorf("create offer: %w", err)
	}
	if err := pc.SetLocalDescription(offer); err != nil {
		return fmt.Errorf("set local description: %w", err)
	}

	local := pc.LocalDescription()
	if local == nil {
		return fmt.Errorf("local description is nil")
	}
	logCodecLines("local offer", local.SDP)

	if err := writeJSON(ctx, c, signalMessage{Type: "offer", SDP: local.SDP}); err != nil {
		return fmt.Errorf("send offer: %w", err)
	}
	log.Printf("signaling send: offer")

	pingTicker := time.NewTicker(20 * time.Second)
	defer pingTicker.Stop()

	for {
		select {
		case <-ctx.Done():
			_ = writeJSON(context.Background(), c, signalMessage{Type: "leave"})
			return nil
		case <-pingTicker.C:
			_ = writeJSON(ctx, c, signalMessage{Type: "ping"})
			log.Printf("signaling send: ping")
		default:
			typ, data, err := c.Read(ctx)
			if err != nil {
				return fmt.Errorf("signaling read: %w", err)
			}
			if typ != websocket.MessageText {
				continue
			}
			if err := handleSignal(ctx, pc, data); err != nil {
				log.Printf("signal handle warning: %v", err)
			}
		}
	}
}

func newPeerConnection() (*webrtc.PeerConnection, error) {
	var mediaEngine webrtc.MediaEngine
	if err := mediaEngine.RegisterDefaultCodecs(); err != nil {
		return nil, err
	}

	api := webrtc.NewAPI(webrtc.WithMediaEngine(&mediaEngine))

	return api.NewPeerConnection(webrtc.Configuration{
		ICEServers: []webrtc.ICEServer{
			{URLs: []string{"stun:stun.l.google.com:19302"}},
		},
	})
}

func addH265Track(pc *webrtc.PeerConnection) error {
	track, err := webrtc.NewTrackLocalStaticSample(
		webrtc.RTPCodecCapability{
			MimeType:     webrtc.MimeTypeH265,
			ClockRate:    90000,
			SDPFmtpLine:  "level-id=180;profile-id=1;tier-flag=0;tx-mode=SRST",
			RTCPFeedback: []webrtc.RTCPFeedback{{Type: "nack"}, {Type: "nack", Parameter: "pli"}, {Type: "ccm", Parameter: "fir"}},
		},
		"x5-hevc-video",
		"teleportation-hevc",
	)
	if err != nil {
		return err
	}

	rtpSender, err := pc.AddTrack(track)
	if err != nil {
		return err
	}

	go func() {
		buf := make([]byte, 1500)
		for {
			if _, _, err := rtpSender.Read(buf); err != nil {
				return
			}
		}
	}()

	log.Printf("added H265 track: id=x5-hevc-video stream=teleportation-hevc")
	return nil
}

func handleSignal(ctx context.Context, pc *webrtc.PeerConnection, data []byte) error {
	var msg signalMessage
	if err := json.Unmarshal(data, &msg); err != nil {
		return fmt.Errorf("decode signaling json: %w text=%s", err, string(data))
	}

	switch msg.Type {
	case "joined":
		log.Printf("signaling recv: joined room=%s role=%s", msg.RoomID, msg.Role)
	case "peer-joined":
		log.Printf("signaling recv: peer-joined role=%s", msg.Role)
	case "answer":
		log.Printf("signaling recv: answer")
		logCodecLines("remote answer", msg.SDP)
		return pc.SetRemoteDescription(webrtc.SessionDescription{
			Type: webrtc.SDPTypeAnswer,
			SDP:  msg.SDP,
		})
	case "ice-candidate":
		if msg.Candidate == nil || msg.Candidate.Candidate == "" {
			return nil
		}
		log.Printf("signaling recv: ice-candidate mid=%s mline=%d", msg.Candidate.SDPMid, msg.Candidate.SDPMLineIndex)
		return pc.AddICECandidate(webrtc.ICECandidateInit{
			Candidate:     msg.Candidate.Candidate,
			SDPMid:        optionalString(msg.Candidate.SDPMid),
			SDPMLineIndex: optionalUint16(msg.Candidate.SDPMLineIndex),
		})
	case "pong":
		log.Printf("signaling recv: pong")
	case "error":
		return fmt.Errorf("signaling error: %s", msg.Message)
	case "peer-left":
		log.Printf("signaling recv: peer-left role=%s", msg.Role)
	default:
		log.Printf("signaling recv: unknown type=%s raw=%s", msg.Type, string(data))
	}

	_ = ctx
	return nil
}

func writeJSON(ctx context.Context, c *websocket.Conn, value any) error {
	data, err := json.Marshal(value)
	if err != nil {
		return err
	}
	return c.Write(ctx, websocket.MessageText, data)
}

func logCodecLines(label string, sdp string) {
	log.Printf("%s codec lines:", label)
	hasH265 := false
	for _, line := range strings.Split(sdp, "\n") {
		line = strings.TrimSpace(line)
		upper := strings.ToUpper(line)
		if strings.HasPrefix(line, "m=video") ||
			(strings.HasPrefix(line, "a=rtpmap:") &&
				(strings.Contains(upper, "H265") ||
					strings.Contains(upper, "HEVC") ||
					strings.Contains(upper, "H264") ||
					strings.Contains(upper, "AV1") ||
					strings.Contains(upper, "VP9") ||
					strings.Contains(upper, "VP8"))) ||
			(strings.HasPrefix(line, "a=fmtp:") &&
				(strings.Contains(upper, "APT=") ||
					strings.Contains(upper, "PROFILE-ID") ||
					strings.Contains(upper, "LEVEL-ID") ||
					strings.Contains(upper, "TX-MODE"))) {
			log.Printf("  %s", line)
		}
		if strings.Contains(upper, "H265/90000") || strings.Contains(upper, "HEVC/90000") {
			hasH265 = true
		}
	}
	log.Printf("%s has H265=%t", label, hasH265)
}

func optionalString(value string) *string {
	if value == "" {
		return nil
	}
	return &value
}

func optionalUint16(value uint16) *uint16 {
	return &value
}

func derefString(value *string) string {
	if value == nil {
		return ""
	}
	return *value
}

func derefUint16(value *uint16) uint16 {
	if value == nil {
		return 0
	}
	return *value
}
