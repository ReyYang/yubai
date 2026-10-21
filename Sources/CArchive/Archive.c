#include "CArchive.h"
#include <zlib.h>
#include <limits.h>
#if defined(__APPLE__)
#include <CommonCrypto/CommonKeyDerivation.h>
#endif
int yubai_inflate(const uint8_t *source, size_t length, uint8_t *output, size_t output_length) {
    if (length > UINT_MAX || output_length > UINT_MAX) return -1;
    z_stream stream = {0};
    stream.next_in = (Bytef *)source;
    stream.avail_in = (uInt)length;
    stream.next_out = output;
    stream.avail_out = (uInt)output_length;
    if (inflateInit2(&stream, -MAX_WBITS) != Z_OK) return -1;
    int result = inflate(&stream, Z_FINISH);
    int ok = result == Z_STREAM_END && stream.total_out == output_length;
    inflateEnd(&stream);
    return ok ? 0 : -1;
}
uint32_t yubai_crc32(const uint8_t *source, size_t length) {
    return (uint32_t)crc32(0, source, (uInt)length);
}
int yubai_gzip(const uint8_t *source, size_t length, uint8_t *output, size_t *output_length) {
    if (length > UINT_MAX || *output_length > UINT_MAX) return -1;
    z_stream stream = {0};
    stream.next_in = (Bytef *)source; stream.avail_in = (uInt)length;
    stream.next_out = output; stream.avail_out = (uInt)*output_length;
    if (deflateInit2(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, MAX_WBITS + 16, 8, Z_DEFAULT_STRATEGY) != Z_OK) return -1;
    int result = deflate(&stream, Z_FINISH);
    *output_length = stream.total_out;
    deflateEnd(&stream);
    return result == Z_STREAM_END ? 0 : -1;
}
int yubai_gunzip(const uint8_t *source, size_t length, uint8_t *output, size_t *output_length) {
    if (length > UINT_MAX || *output_length > UINT_MAX) return -1;
    z_stream stream = {0};
    stream.next_in = (Bytef *)source; stream.avail_in = (uInt)length;
    stream.next_out = output; stream.avail_out = (uInt)*output_length;
    if (inflateInit2(&stream, MAX_WBITS + 16) != Z_OK) return -1;
    int result = inflate(&stream, Z_FINISH);
    int ok = result == Z_STREAM_END && stream.avail_in == 0;
    int full = stream.avail_out == 0;
    *output_length = stream.total_out;
    inflateEnd(&stream);
    return ok ? 0 : (result == Z_BUF_ERROR && full ? 1 : -1);
}
#if defined(__APPLE__)
int yubai_derive_key(const char *password, size_t password_length, const uint8_t *salt, size_t salt_length, uint32_t rounds, uint8_t *key) {
    return CCKeyDerivationPBKDF(kCCPBKDF2, password, password_length, salt, salt_length, kCCPRFHmacAlgSHA256, rounds, key, 32);
}
#endif
