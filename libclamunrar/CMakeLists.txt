# Copyright (C) 2019-2025 Cisco Systems, Inc. and/or its affiliates. All rights reserved.

add_compile_definitions(RARDLL)
add_compile_definitions(_FILE_OFFSET_BITS=64)

if(WIN32)
    add_compile_definitions(_CRT_SECURE_NO_WARNINGS)
endif()

# not using an object library for the sake of Xcode compatibility
# See: https://cmake.org/pipermail/cmake/2016-May/063479.html
set( UNRAR_SOURCES
    archive.cpp
    arcread.cpp
    blake2s.cpp
    cmddata.cpp
    consio.cpp
    crc.cpp
    crypt.cpp
    dll.cpp
    encname.cpp
    errhnd.cpp
    extinfo.cpp
    extract.cpp
    filcreat.cpp
    file.cpp
    filefn.cpp
    filestr.cpp
    find.cpp
    getbits.cpp
    global.cpp
    hash.cpp
    headers.cpp
    list.cpp
    match.cpp
    options.cpp
    pathfn.cpp
    qopen.cpp
    rar.cpp
    rarvm.cpp
    rawread.cpp
    rdwrfn.cpp
    recvol.cpp
    resource.cpp
    rijndael.cpp
    rs.cpp
    rs16.cpp
    scantree.cpp
    secpassword.cpp
    sha1.cpp
    sha256.cpp
    smallfn.cpp
    strfn.cpp
    strlist.cpp
    system.cpp
    threadpool.cpp
    timefn.cpp
    ui.cpp
    unicode.cpp
    unpack.cpp
    volume.cpp
)
if(WIN32)
    list(APPEND UNRAR_SOURCES isnt.cpp)
endif()

if(ENABLE_SHARED_LIB)
    # The unrar shared library.
    add_library( vigilixunrar SHARED )
    set_target_properties( vigilixunrar PROPERTIES
        VERSION ${LIBVIGILIXAV_VERSION}
        SOVERSION ${LIBVIGILIXAV_SOVERSION}
        CXX_STANDARD 11
    )

    target_sources( vigilixunrar
        PRIVATE
            ${UNRAR_SOURCES}
        PUBLIC
            rar.hpp
            dll.hpp )
    target_include_directories( vigilixunrar
        PRIVATE "${CMAKE_BINARY_DIR}"
        PUBLIC  "${CMAKE_CURRENT_SOURCE_DIR}" )

    if(NOT WIN32)
        set_target_properties( vigilixunrar PROPERTIES
            COMPILE_FLAGS "-Wno-logical-op-parentheses -Wno-switch -Wno-dangling-else")
    endif()

    if (APPLE AND CLAMAV_SIGN_FILE)
        set_target_properties( vigilixunrar PROPERTIES
            XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY ${CODE_SIGN_IDENTITY}
            XCODE_ATTRIBUTE_DEVELOPMENT_TEAM ${DEVELOPMENT_TEAM_ID}
        )
    endif()

    if(WIN32)
        set_target_properties(vigilixunrar PROPERTIES WINDOWS_EXPORT_ALL_SYMBOLS ON)
    elseif(UNIX AND NOT APPLE AND NOT AIX)
        target_link_options(vigilixunrar PRIVATE "-Wl,--version-script=${CMAKE_CURRENT_SOURCE_DIR}/libvigilixunrar.map")
        if (${CMAKE_SYSTEM_NAME} MATCHES "SunOS")
            # Solaris 11.4 linker supports a subset of GNU ld version scripts, but requires a special option to enable
            target_link_options(vigilixunrar PRIVATE "-Wl,-z,gnu-version-script-compat")
        endif()
    endif()

    install(TARGETS vigilixunrar COMPONENT libraries)

    add_library( VigilixAV::libunrar ALIAS vigilixunrar )
endif()

if(ENABLE_STATIC_LIB)
    # The vigilixunrar static library.
    add_library( vigilixunrar_static STATIC)
    set_target_properties( vigilixunrar_static PROPERTIES
        CXX_STANDARD 11
    )
    target_sources( vigilixunrar_static
        PRIVATE
            ${UNRAR_SOURCES}
        PUBLIC
            rar.hpp
            dll.hpp )
    target_include_directories( vigilixunrar_static
        PRIVATE "${CMAKE_BINARY_DIR}"
        PUBLIC  "${CMAKE_CURRENT_SOURCE_DIR}" )

    if(NOT WIN32)
        set_target_properties( vigilixunrar_static PROPERTIES
            COMPILE_FLAGS "-Wno-logical-op-parentheses -Wno-switch -Wno-dangling-else")
    endif()

    install(TARGETS vigilixunrar_static COMPONENT libraries)

    add_library( VigilixAV::libunrar_static ALIAS vigilixunrar_static )
    if(NOT ENABLE_SHARED_LIB)
        add_library( VigilixAV::libunrar ALIAS vigilixunrar_static )
    endif()
endif()
