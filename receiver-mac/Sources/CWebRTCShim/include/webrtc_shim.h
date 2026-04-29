#ifndef WEBRTC_SHIM_H
#define WEBRTC_SHIM_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

void webrtc_shim_init(const char* signaling_url, const char* room);
void webrtc_shim_set_preferred_codec(const char* codec);
void webrtc_shim_set_remote_offer(const char* sdp);
void webrtc_shim_add_ice_candidate(const char* candidate_json);
void webrtc_shim_shutdown(void);

#ifdef __cplusplus
}
#endif

#endif // WEBRTC_SHIM_H
