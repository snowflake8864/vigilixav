# Copyright (C) 2020-2025 Cisco Systems, Inc. and/or its affiliates. All rights reserved.

if(WIN32)
    add_definitions(-DWIN32_LEAN_AND_MEAN)
    add_definitions(-D_CRT_SECURE_NO_WARNINGS)
    add_definitions(-D_CRT_SECURE_NO_DEPRECATE)
    add_definitions(-D_CRT_NONSTDC_NO_DEPRECATE)

    # Windows compatibility headers
    include_directories(${CMAKE_SOURCE_DIR}/win32/compat)
endif()

# The vigilixscan executable.
add_executable( vigilixscan )
target_sources( vigilixscan
    PRIVATE
        clamscan.c
        manager.c
        manager.h
        global.h )
if(WIN32)
    target_sources( vigilixscan
    PRIVATE
        ${CMAKE_SOURCE_DIR}/win32/res/clamscan.rc
        ${CMAKE_SOURCE_DIR}/win32/res/clam.manifest )
endif()
target_include_directories( vigilixscan
    PRIVATE ${CMAKE_BINARY_DIR} # For clamav-config.h
)
set_target_properties( vigilixscan PROPERTIES COMPILE_FLAGS "${WARNCFLAGS}" )

if (APPLE AND CLAMAV_SIGN_FILE)
    set_target_properties( vigilixscan PROPERTIES
        XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY ${CODE_SIGN_IDENTITY}
        XCODE_ATTRIBUTE_DEVELOPMENT_TEAM ${DEVELOPMENT_TEAM_ID}
    )
endif()

target_link_libraries( vigilixscan
    PRIVATE
        VigilixAV::libvigilixav
        VigilixAV::common )
install(TARGETS vigilixscan COMPONENT programs)
if(WIN32)
    install(FILES $<TARGET_PDB_FILE:vigilixscan> TYPE BIN OPTIONAL COMPONENT programs)
endif()
