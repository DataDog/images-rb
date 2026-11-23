#include <ruby.h>
#include <stdlib.h>
#include <string.h>

#if !__has_feature(address_sanitizer)
#error "mkmf must inherit AddressSanitizer instrumentation from Ruby"
#endif

unsigned char asan_read_cpp(size_t offset);

static VALUE read_byte(VALUE self, VALUE index)
{
    size_t offset = NUM2SIZET(index);
    volatile unsigned char *bytes = calloc(8, 1);
    if (!bytes) rb_memerror();

    /* Volatile keeps the invalid access observable under optimisation. */
    unsigned char value = bytes[offset];
    free((void *)bytes);
    return UINT2NUM(value);
}

static VALUE leak_memory(VALUE self)
{
    char *bytes = malloc(1337);
    if (!bytes) rb_memerror();

    memset(bytes, 'x', 1337);
    /* The Ruby string owns a copy; the allocation deliberately becomes lost. */
    return rb_str_new(bytes, 1337);
}

static VALUE read_byte_cpp(VALUE self, VALUE index)
{
    return UINT2NUM(asan_read_cpp(NUM2SIZET(index)));
}

void Init_asan_probe(void)
{
    VALUE module = rb_define_module("AsanProbe");
    rb_define_singleton_method(module, "read_byte", read_byte, 1);
    rb_define_singleton_method(module, "read_byte_cpp", read_byte_cpp, 1);
    rb_define_singleton_method(module, "leak_memory", leak_memory, 0);
}
