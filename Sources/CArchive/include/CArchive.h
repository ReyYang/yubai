#include <stddef.h>
#include <stdint.h>
int yubai_inflate(const uint8_t *source, size_t length, uint8_t *output, size_t output_length);
uint32_t yubai_crc32(const uint8_t *source, size_t length);
int yubai_gzip(const uint8_t *source, size_t length, uint8_t *output, size_t *output_length);
int yubai_gunzip(const uint8_t *source, size_t length, uint8_t *output, size_t *output_length);
#if defined(__APPLE__)
int yubai_derive_key(const char *password, size_t password_length, const uint8_t *salt, size_t salt_length, uint32_t rounds, uint8_t *key);
#endif
