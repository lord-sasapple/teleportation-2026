#include "include/webrtc_shim.h"
#include <stdio.h>
#include <string.h>

void webrtc_shim_init(const char* signaling_url, const char* room) {
    printf("[webrtc_shim] init signaling_url=%s room=%s\n", signaling_url, room);
}

void webrtc_shim_set_preferred_codec(const char* codec) {
    printf("[webrtc_shim] set_preferred_codec=%s\n", codec);
}

void webrtc_shim_set_remote_offer(const char* sdp) {
    printf("[webrtc_shim] set_remote_offer len=%zu\n", sdp ? strlen(sdp) : 0);
}

void webrtc_shim_add_ice_candidate(const char* candidate_json) {
    printf("[webrtc_shim] add_ice_candidate: %s\n", candidate_json ? candidate_json : "null");
}

void webrtc_shim_shutdown(void) {
    printf("[webrtc_shim] shutdown\n");
}
