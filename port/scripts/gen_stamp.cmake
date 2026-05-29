# Writes a build-time timestamp header. Run on every build (from a custom
# target with no tracked output) so BUILD_STAMP always reflects the current
# compile, letting us tell at a glance which build the browser loaded.
#   cmake -DOUT=<path> -P gen_stamp.cmake
string(TIMESTAMP STAMP "%Y-%m-%d %H:%M")
set(CONTENT "#pragma once\n#define BUILD_STAMP \"${STAMP}\"\n")
if(EXISTS "${OUT}")
    file(READ "${OUT}" OLD)
    if(OLD STREQUAL CONTENT)
        return()  # unchanged within the same minute -> don't touch mtime
    endif()
endif()
file(WRITE "${OUT}" "${CONTENT}")
