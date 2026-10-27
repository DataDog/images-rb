#include <cstddef>

#if !__has_feature(address_sanitizer)
#error "mkmf must inherit AddressSanitizer instrumentation for C++ too"
#endif

extern "C" unsigned char asan_read_cpp(size_t offset)
{
    volatile unsigned char *bytes = new unsigned char[8]();
    unsigned char value = bytes[offset];
    delete[] bytes;
    return value;
}
