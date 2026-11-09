# Copyright (C) 2020-2025 Cisco Systems, Inc. and/or its affiliates. All rights reserved.

if(WIN32)
    add_definitions(-DWIN32_LEAN_AND_MEAN)
    add_definitions(-D_CRT_SECURE_NO_WARNINGS)
    add_definitions(-D_CRT_SECURE_NO_DEPRECATE)
    add_definitions(-D_CRT_NONSTDC_NO_DEPRECATE)

    # Windows compatibility headers
    include_directories(${CMAKE_SOURCE_DIR}/win32/compat)
endif()

# The freshvigilix executable.
add_executable( freshvigilix )
target_sources( freshvigilix
    PRIVATE
        freshclam.c
        execute.c
        execute.h
        notify.c
        notify.h )
if(WIN32)
    target_sources( freshvigilix
        PRIVATE
            ${CMAKE_SOURCE_DIR}/win32/res/freshclam.rc
            ${CMAKE_SOURCE_DIR}/win32/res/clam.manifest )
endif()
set_target_properties( freshvigilix PROPERTIES COMPILE_FLAGS "${WARNCFLAGS}" )

if (APPLE AND CLAMAV_SIGN_FILE)
    set_target_properties( freshvigilix PROPERTIES
        XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY ${CODE_SIGN_IDENTITY}
        XCODE_ATTRIBUTE_DEVELOPMENT_TEAM ${DEVELOPMENT_TEAM_ID}
    )
endif()

target_link_libraries(freshvigilix
    PRIVATE
        VigilixAV::libfreshvigilix
        VigilixAV::libvigilixav
        VigilixAV::common )
install(TARGETS freshvigilix COMPONENT programs)
if(WIN32)
    install(FILES $<TARGET_PDB_FILE:freshvigilix> TYPE BIN OPTIONAL COMPONENT programs)
endif()

if(SYSTEMD_FOUND)
    configure_file(
        ${CMAKE_CURRENT_SOURCE_DIR}/clamav-freshclam.service.in
        ${CMAKE_CURRENT_BINARY_DIR}/vigilixav-freshvigilix.service @ONLY)
    install(
        FILES ${CMAKE_CURRENT_BINARY_DIR}/vigilixav-freshvigilix.service
        DESTINATION ${SYSTEMD_UNIT_DIR}
        COMPONENT programs)
    configure_file(
        ${CMAKE_CURRENT_SOURCE_DIR}/clamav-freshclam-once.service.in
        ${CMAKE_CURRENT_BINARY_DIR}/vigilixav-freshvigilix-once.service @ONLY)
    install(
        FILES ${CMAKE_CURRENT_BINARY_DIR}/vigilixav-freshvigilix-once.service
        DESTINATION ${SYSTEMD_UNIT_DIR}
        COMPONENT programs)
    configure_file(
        ${CMAKE_CURRENT_SOURCE_DIR}/clamav-freshclam-once.timer.in
        ${CMAKE_CURRENT_BINARY_DIR}/vigilixav-freshvigilix-once.timer @ONLY)
    install(
        FILES ${CMAKE_CURRENT_BINARY_DIR}/vigilixav-freshvigilix-once.timer
        DESTINATION ${SYSTEMD_UNIT_DIR}
        COMPONENT programs)
endif()
