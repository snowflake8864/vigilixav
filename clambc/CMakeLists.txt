# Copyright (C) 2020-2025 Cisco Systems, Inc. and/or its affiliates. All rights reserved.

if(WIN32)
    add_definitions(-DWIN32_LEAN_AND_MEAN)
    add_definitions(-D_CRT_SECURE_NO_WARNINGS)
    add_definitions(-D_CRT_SECURE_NO_DEPRECATE)
    add_definitions(-D_CRT_NONSTDC_NO_DEPRECATE)

    # Windows compatibility headers
    include_directories(${CMAKE_SOURCE_DIR}/win32/compat)
endif()

# The vigilixbc executable.
add_executable( vigilixbc )
target_sources( vigilixbc
    PRIVATE
        bcrun.c )
if(WIN32)
    target_sources( vigilixbc PRIVATE
    ${CMAKE_SOURCE_DIR}/win32/res/clambc.rc
    ${CMAKE_SOURCE_DIR}/win32/res/clam.manifest )
endif()
target_include_directories( vigilixbc
    PRIVATE ${CMAKE_BINARY_DIR} # For clamav-config.h
)
set_target_properties( vigilixbc PROPERTIES COMPILE_FLAGS "${WARNCFLAGS}" )

if (APPLE AND CLAMAV_SIGN_FILE)
    set_target_properties( vigilixbc PROPERTIES
        XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY ${CODE_SIGN_IDENTITY}
        XCODE_ATTRIBUTE_DEVELOPMENT_TEAM ${DEVELOPMENT_TEAM_ID}
    )
endif()

target_link_libraries( vigilixbc
    PRIVATE
        VigilixAV::libvigilixav
        VigilixAV::common )
install(TARGETS vigilixbc COMPONENT programs)
if(WIN32)
    install(FILES $<TARGET_PDB_FILE:vigilixbc> TYPE BIN OPTIONAL COMPONENT programs)
endif()
