#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Opaque handle to a running runcore node.
typedef uint64_t runcore_handle_t;

// Called for every internal log line. The line includes timestamp prefix.
typedef void (*runcore_log_cb)(void* user_data, int32_t level, const char* line);
typedef void (*runcore_raw_tx_cb)(void* user_data, const uint8_t* data, int32_t len);
typedef void (*runcore_inbound_cb)(void* user_data, const char* source, const char* title, const char* content, double timestamp, const char* message_id, const char* attachment_path, const char* attachment_name, const char* attachment_mime, int32_t attachment_type, int32_t has_location, double latitude, double longitude, double accuracy, int64_t location_timestamp);
typedef void (*runcore_status_cb)(void* user_data, const char* client_id, const char* status);

// Set a global log callback (applies process-wide). Pass NULL to disable.
void runcore_set_log_cb(runcore_log_cb cb, void* user_data);

// Set global loglevel (0..7). Applies immediately.
void runcore_set_loglevel(int32_t level);

// Start Reticulum+LXMF node.
// - contacts_dir: directory for contacts storage (iCloud Drive)
// - send_dir: directory watched for outbound payloads (iCloud Drive; reserved for future use)
// - messages_dir: directory used for inbound/outbound LXMF message files
// - loglevel: Reticulum log level 0..7
// Returns 0 on failure.
runcore_handle_t runcore_start(const char* contacts_dir, const char* send_dir, const char* messages_dir, int32_t loglevel);

// Persist state and stop (best-effort). Returns 0 on success.
int32_t runcore_stop(runcore_handle_t handle);
int32_t runcore_attach_raw_interface(runcore_handle_t handle, runcore_raw_tx_cb cb, void* user_data, int32_t bitrate);
int32_t runcore_raw_interface_receive(runcore_handle_t handle, const uint8_t* data, int32_t len);
int32_t runcore_set_raw_interface_enabled(runcore_handle_t handle, int32_t enabled);
int32_t runcore_connect_tcp_interface(runcore_handle_t handle, const char* host, int32_t port);
int32_t runcore_disconnect_tcp_interface(runcore_handle_t handle);
// 0 = disconnected, 1 = connecting/reconnecting, 2 = connected.
int32_t runcore_tcp_interface_state(runcore_handle_t handle);
int32_t runcore_announce(runcore_handle_t handle);
int32_t runcore_set_announce_location(runcore_handle_t handle, double latitude, double longitude, double accuracy, int64_t timestamp, int32_t enabled);
int32_t runcore_send_text(runcore_handle_t handle, const char* destination, const char* content, int32_t direct, const char* client_id);
int32_t runcore_send_attachment(runcore_handle_t handle, const char* destination, const char* content, const char* file_path, const char* file_name, const char* mime_type, const char* client_id);
int32_t runcore_set_inbound_cb(runcore_handle_t handle, runcore_inbound_cb cb, void* user_data);
int32_t runcore_set_status_cb(runcore_handle_t handle, runcore_status_cb cb, void* user_data);
// Ingest an lxm:// paper-message URI. Returns 0 when delivered locally,
// 1 for a duplicate, 2 when addressed elsewhere, and -1 on invalid input.
int32_t runcore_ingest_lxm_uri(runcore_handle_t handle, const char* uri);

// Outbound message statuses are reflected via xattr on message files.

// Returns the active config dir used by the node (config, identity, storage, rns/config).
// The returned pointer must be freed with runcore_free_string().
char* runcore_config_dir(runcore_handle_t handle);

// Returns the current node LXMF delivery destination hash hex.
// The returned pointer must be freed with runcore_free_string().
char* runcore_destination_hash_hex(runcore_handle_t handle);

// Sending is done by writing into the send folder.

// Update display_name used in announce app-data (does not restart the node). Returns 0 on success.
int32_t runcore_set_display_name(runcore_handle_t handle, const char* display_name);

// Restart the LXMF router (re-announce on restart). Returns 0 on success.
int32_t runcore_restart(runcore_handle_t handle);

// Recreate the local identity and LXMF delivery destination. Returns 0 on success.
int32_t runcore_reset_profile(runcore_handle_t handle);

// Free a C string allocated by the library (eg. runcore_interface_stats_json()).
void runcore_free_string(char* p);

// Return the embedded default runcore (lxmd-style) config.
// The returned pointer must be freed with runcore_free_string().
char* runcore_default_lxmd_config(void);

// Return the embedded default Reticulum config used for configDir/rns/config.
// The returned pointer must be freed with runcore_free_string().
char* runcore_default_rns_config(void);

// Returns JSON with Reticulum interface stats (includes `interfaces` array with `name`, `type`, `status`, `rxb`, `txb`, etc).
// The returned pointer must be freed with runcore_free_string().
char* runcore_interface_stats_json(runcore_handle_t handle);

// Attachments are sent by placing files into the send folder.

// Attachment fetch is handled by the Go core and stored on disk.


// Enable/disable an interface by config section name (eg "Default Interface").
// Returns 0 on success.
int32_t runcore_set_interface_enabled(runcore_handle_t handle, const char* name, int32_t enabled);

#ifdef __cplusplus
}
#endif
