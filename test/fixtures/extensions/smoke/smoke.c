#include <ruby.h>

static VALUE answer(VALUE self)
{
    return INT2FIX(42);
}

void Init_smoke(void)
{
    VALUE smoke = rb_define_module("Smoke");
    rb_define_singleton_method(smoke, "answer", answer, 0);
}
