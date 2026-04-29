package main

import (
	"context"
	"encoding/binary"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"strings"
	"sync/atomic"
	"time"

	"github.com/pion/webrtc/v4"
	"github.com/pion/webrtc/v4/pkg/media"
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
	annexBFile   string
	listenFrames string
	fps          int
	queueSize    int
}

func main() {
	cfg := parseFlags()

	log.Printf("== Pion HEVC sender ==")
	log.Printf("room=%s", cfg.room)
	log.Printf("signaling=%s", cfg.signalingURL)
	log.Printf("duration=%s", cfg.duration)
	log.Printf("annexb-file=%s", cfg.annexBFile)
	log.Printf("listen-frames=%s", cfg.listenFrames)
	log.Printf("fps=%d", cfg.fps)
	log.Printf("queue-size=%d", cfg.queueSize)

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
	flag.StringVar(&cfg.annexBFile, "annexb-file", "", "optional HEVC Annex B elementary stream file to loop")
	flag.StringVar(&cfg.listenFrames, "listen-frames", "", "optional TCP listen address for length-prefixed HEVC Annex B access units, e.g. 127.0.0.1:5005")
	flag.IntVar(&cfg.fps, "fps", 30, "sample send fps")
	flag.IntVar(&cfg.queueSize, "queue-size", 3, "low-latency frame queue size for TCP HEVC access units")
	durationSeconds := flag.Int("duration", 600, "run duration seconds")
	flag.Parse()

	cfg.duration = time.Duration(*durationSeconds) * time.Second
	if cfg.fps <= 0 {
		cfg.fps = 30
	}
	if cfg.queueSize <= 0 {
		cfg.queueSize = 1
	}
	return cfg
}

func run(ctx context.Context, cfg config) error {
	pc, err := newPeerConnection()
	if err != nil {
		return err
	}
	defer pc.Close()

	var wsReady atomic.Bool
	var mediaReady atomic.Bool
	var wsConn *websocket.Conn
	var h265Track *webrtc.TrackLocalStaticSample

	pc.OnICEConnectionStateChange(func(state webrtc.ICEConnectionState) {
		log.Printf("ICE connection state: %s", state.String())
		if state == webrtc.ICEConnectionStateConnected ||
			state == webrtc.ICEConnectionStateCompleted {
			mediaReady.Store(true)
			log.Printf("media ready: true")
		}
		if state == webrtc.ICEConnectionStateFailed ||
			state == webrtc.ICEConnectionStateClosed {
			mediaReady.Store(false)
			log.Printf("media ready: false")
		}
	})
	pc.OnConnectionStateChange(func(state webrtc.PeerConnectionState) {
		log.Printf("PeerConnection state: %s", state.String())
		if state == webrtc.PeerConnectionStateConnected {
			mediaReady.Store(true)
			log.Printf("media ready: true")
			if cfg.annexBFile != "" && h265Track != nil {
				go streamAnnexBFile(ctx, h265Track, cfg.annexBFile, cfg.fps)
			}
		}
		if state == webrtc.PeerConnectionStateFailed ||
			state == webrtc.PeerConnectionStateClosed {
			mediaReady.Store(false)
			log.Printf("media ready: false")
		}
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

	h265Track, err = addH265Track(pc)
	if err != nil {
		return err
	}
	if cfg.listenFrames != "" {
		frameListener, err := net.Listen("tcp", cfg.listenFrames)
		if err != nil {
			return fmt.Errorf("start frame listener %s: %w", cfg.listenFrames, err)
		}
		go serveFrameStream(ctx, h265Track, frameListener, cfg.fps, cfg.queueSize, &mediaReady)
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
			if err := handleSignal(ctx, c, pc, data, local.SDP); err != nil {
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

func addH265Track(pc *webrtc.PeerConnection) (*webrtc.TrackLocalStaticSample, error) {
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
		return nil, err
	}

	rtpSender, err := pc.AddTrack(track)
	if err != nil {
		return nil, err
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
	return track, nil
}

func serveFrameStream(ctx context.Context, track *webrtc.TrackLocalStaticSample, listener net.Listener, fps int, queueSize int, mediaReady *atomic.Bool) {
	defer listener.Close()

	log.Printf("frame listener started: %s", listener.Addr())

	go func() {
		<-ctx.Done()
		_ = listener.Close()
	}()

	frameDuration := time.Second / time.Duration(fps)

	for {
		conn, err := listener.Accept()
		if err != nil {
			select {
			case <-ctx.Done():
				log.Printf("frame listener stopped")
				return
			default:
				log.Printf("frame listener accept failed: %v", err)
				continue
			}
		}

		log.Printf("frame source connected: %s", conn.RemoteAddr())
		handleFrameConn(ctx, track, conn, frameDuration, queueSize, mediaReady)
		log.Printf("frame source disconnected")
	}
}

func handleFrameConn(ctx context.Context, track *webrtc.TrackLocalStaticSample, conn net.Conn, frameDuration time.Duration, queueSize int, mediaReady *atomic.Bool) {
	defer conn.Close()

	if queueSize <= 0 {
		queueSize = 1
	}

	frameQueue := make(chan []byte, queueSize)
	readerDone := make(chan struct{})

	go func() {
		defer close(readerDone)
		defer close(frameQueue)

		var received uint64
		var dropped uint64
		header := make([]byte, 4)

		for {
			select {
			case <-ctx.Done():
				log.Printf("frame input stopped: received=%d dropped=%d queue=%d", received, dropped, len(frameQueue))
				return
			default:
			}

			if _, err := io.ReadFull(conn, header); err != nil {
				if err != io.EOF {
					log.Printf("frame length read failed: %v", err)
				}
				log.Printf("frame input closed: received=%d dropped=%d queue=%d", received, dropped, len(frameQueue))
				return
			}

			length := binary.BigEndian.Uint32(header)
			if length == 0 {
				continue
			}
			if length > 16*1024*1024 {
				log.Printf("frame too large: %d bytes", length)
				return
			}

			frame := make([]byte, length)
			if _, err := io.ReadFull(conn, frame); err != nil {
				log.Printf("frame payload read failed: %v", err)
				return
			}

			received++
			select {
			case frameQueue <- frame:
			default:
				select {
				case <-frameQueue:
					dropped++
				default:
				}

				select {
				case frameQueue <- frame:
				case <-ctx.Done():
					log.Printf("frame input stopped: received=%d dropped=%d queue=%d", received, dropped, len(frameQueue))
					return
				}
			}

			if received%30 == 0 {
				log.Printf("frame input received=%d dropped=%d queue=%d", received, dropped, len(frameQueue))
			}
		}
	}()

	go func() {
		<-ctx.Done()
		_ = conn.Close()
	}()

	ticker := time.NewTicker(frameDuration)
	defer ticker.Stop()

	var sent uint64
	var skipped uint64
	var lastBytes int

	for {
		select {
		case <-ctx.Done():
			log.Printf("frame stream stopped: sent=%d skipped=%d queue=%d", sent, skipped, len(frameQueue))
			return
		case <-readerDone:
			log.Printf("frame stream stopped: sent=%d skipped=%d queue=%d", sent, skipped, len(frameQueue))
			return
		case <-ticker.C:
			var frame []byte
			for {
				select {
				case queuedFrame, ok := <-frameQueue:
					if !ok {
						log.Printf("frame stream stopped: sent=%d skipped=%d queue=%d", sent, skipped, len(frameQueue))
						return
					}
					frame = queuedFrame
				default:
					goto drained
				}
			}
		drained:
			if frame == nil {
				continue
			}

			lastBytes = len(frame)
			if mediaReady != nil && !mediaReady.Load() {
				skipped++
				if skipped%30 == 0 {
					log.Printf("frame samples skipped: media not ready count=%d lastBytes=%d queue=%d", skipped, lastBytes, len(frameQueue))
				}
				continue
			}

			if err := track.WriteSample(media.Sample{
				Data:     frame,
				Duration: frameDuration,
			}); err != nil {
				log.Printf("frame write sample failed: %v", err)
				continue
			}

			sent++
			if sent%30 == 0 {
				log.Printf("frame samples sent=%d lastBytes=%d queue=%d skipped=%d", sent, lastBytes, len(frameQueue), skipped)
			}
		}
	}
}

func streamAnnexBFile(ctx context.Context, track *webrtc.TrackLocalStaticSample, path string, fps int) {
	data, err := os.ReadFile(path)
	if err != nil {
		log.Printf("annexb read failed: %v", err)
		return
	}
	if len(data) == 0 {
		log.Printf("annexb file is empty: %s", path)
		return
	}

	frames := splitAnnexBAccessUnits(data)
	if len(frames) == 0 {
		log.Printf("annexb split produced no frames; sending whole file as one repeated sample")
		frames = [][]byte{data}
	}

	frameDuration := time.Second / time.Duration(fps)
	ticker := time.NewTicker(frameDuration)
	defer ticker.Stop()

	log.Printf("annexb streaming started: file=%s bytes=%d frames=%d fps=%d", path, len(data), len(frames), fps)

	index := 0
	var sent uint64
	for {
		select {
		case <-ctx.Done():
			log.Printf("annexb streaming stopped: sent=%d", sent)
			return
		case <-ticker.C:
			frame := frames[index]
			index = (index + 1) % len(frames)

			if err := track.WriteSample(media.Sample{
				Data:     frame,
				Duration: frameDuration,
			}); err != nil {
				log.Printf("annexb write sample failed: %v", err)
				continue
			}

			sent++
			if sent%uint64(fps) == 0 {
				log.Printf("annexb samples sent=%d lastBytes=%d", sent, len(frame))
			}
		}
	}
}

func splitAnnexBAccessUnits(data []byte) [][]byte {
	nals := splitAnnexBNALUnits(data)
	if len(nals) == 0 {
		return nil
	}

	var frames [][]byte
	var current []byte

	flush := func() {
		if len(current) > 0 {
			copied := make([]byte, len(current))
			copy(copied, current)
			frames = append(frames, copied)
			current = nil
		}
	}

	for _, nal := range nals {
		nalType := h265NALType(nal)
		// VPS/SPS/PPS/SEI は次のVCLに付けたいので保持する。
		// VCL NALが来たら、新しいaccess unitとして扱う簡易split。
		if isH265VCL(nalType) {
			flush()
		}
		current = append(current, []byte{0x00, 0x00, 0x00, 0x01}...)
		current = append(current, nal...)
	}
	flush()

	return frames
}

func splitAnnexBNALUnits(data []byte) [][]byte {
	var starts []int
	for i := 0; i+3 < len(data); i++ {
		if data[i] == 0 && data[i+1] == 0 && data[i+2] == 1 {
			starts = append(starts, i)
			i += 2
			continue
		}
		if i+4 < len(data) && data[i] == 0 && data[i+1] == 0 && data[i+2] == 0 && data[i+3] == 1 {
			starts = append(starts, i)
			i += 3
			continue
		}
	}
	if len(starts) == 0 {
		return nil
	}

	var nals [][]byte
	for idx, start := range starts {
		prefix := 3
		if start+4 < len(data) && data[start] == 0 && data[start+1] == 0 && data[start+2] == 0 && data[start+3] == 1 {
			prefix = 4
		}

		nalStart := start + prefix
		nalEnd := len(data)
		if idx+1 < len(starts) {
			nalEnd = starts[idx+1]
		}

		for nalEnd > nalStart && data[nalEnd-1] == 0 {
			nalEnd--
		}
		if nalEnd > nalStart {
			nal := make([]byte, nalEnd-nalStart)
			copy(nal, data[nalStart:nalEnd])
			nals = append(nals, nal)
		}
	}

	return nals
}

func h265NALType(nal []byte) byte {
	if len(nal) < 2 {
		return 64
	}
	return (nal[0] >> 1) & 0x3f
}

func isH265VCL(nalType byte) bool {
	return nalType <= 31
}

func handleSignal(ctx context.Context, c *websocket.Conn, pc *webrtc.PeerConnection, data []byte, localOfferSDP string) error {
	var msg signalMessage
	if err := json.Unmarshal(data, &msg); err != nil {
		return fmt.Errorf("decode signaling json: %w text=%s", err, string(data))
	}

	switch msg.Type {
	case "joined":
		log.Printf("signaling recv: joined room=%s role=%s", msg.RoomID, msg.Role)
	case "peer-joined":
		log.Printf("signaling recv: peer-joined role=%s", msg.Role)
		if msg.Role == "receiver" && localOfferSDP != "" {
			if pc.SignalingState() != webrtc.SignalingStateHaveLocalOffer {
				log.Printf("skip offer resend: signalingState=%s; restart pion-hevc-sender for clean receiver reconnect", pc.SignalingState())
				return nil
			}
			if err := writeJSON(ctx, c, signalMessage{Type: "offer", SDP: localOfferSDP}); err != nil {
				return fmt.Errorf("resend offer after receiver joined: %w", err)
			}
			log.Printf("signaling resend: offer after receiver joined")
		}
	case "answer":
		log.Printf("signaling recv: answer")
		logCodecLines("remote answer", msg.SDP)
		if pc.SignalingState() != webrtc.SignalingStateHaveLocalOffer {
			log.Printf("skip answer: signalingState=%s", pc.SignalingState())
			return nil
		}
		if err := pc.SetRemoteDescription(webrtc.SessionDescription{
			Type: webrtc.SDPTypeAnswer,
			SDP:  msg.SDP,
		}); err != nil {
			return err
		}
		return nil
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
