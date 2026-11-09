# Copyright (C) 2020-2025 Cisco Systems, Inc. and/or its affiliates. All rights reserved.

# The vigilixav-milter executable.
add_executable( vigilixav-milter )
target_sources( vigilixav-milter
    PRIVATE
        clamav-milter.c
        clamfi.c
        clamfi.h
        connpool.c
        connpool.h
        netcode.c
        netcode.h
        allow_list.c
        allow_list.h )
target_include_directories( vigilixav-milter
    PRIVATE ${CMAKE_BINARY_DIR} # For clamav-config.h
)
set_target_properties( vigilixav-milter PROPERTIES COMPILE_FLAGS "${WARNCFLAGS}" )

if (APPLE AND CLAMAV_SIGN_FILE)
    set_target_properties( vigilixav-milter PROPERTIES
        XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY ${CODE_SIGN_IDENTITY}
        XCODE_ATTRIBUTE_DEVELOPMENT_TEAM ${DEVELOPMENT_TEAM_ID}
    )
endif()

target_link_libraries( vigilixav-milter
    PRIVATE
        VigilixAV::libvigilixav
        VigilixAV::common
        Sendmail::milter )
install(TARGETS vigilixav-milter DESTINATION ${CMAKE_INSTALL_SBINDIR} COMPONENT programs)
