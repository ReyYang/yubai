#include "CArchive.h"
#include <zlib.h>
#include <limits.h>
#include <CommonCrypto/CommonKeyDerivation.h>
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
int yubai_derive_key(const char *password, size_t password_length, const uint8_t *salt, size_t salt_length, uint32_t rounds, uint8_t *key) {
    return CCKeyDerivationPBKDF(kCCPBKDF2, password, password_length, salt, salt_length, kCCPRFHmacAlgSHA256, rounds, key, 32);
}
