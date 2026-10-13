require "rbconfig"

RbConfig::CONFIG["CC"] = RbConfig::MAKEFILE_CONFIG["CC"] = ENV.fetch("CC")

require "mkmf"

abort "cannot link a C library probe" unless have_func("malloc", "stdlib.h")

create_makefile("smoke")
