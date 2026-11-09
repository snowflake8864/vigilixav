# Copyright (C) 2019-2025 Cisco Systems, Inc. and/or its affiliates. All rights reserved.

if(WIN32)
    add_definitions(-DWIN32_LEAN_AND_MEAN)

    # Windows compatibility headers
    include_directories(${CMAKE_SOURCE_DIR}/win32/compat)
endif()

# Move public headers to a dedicated INTERFACE library
#
# An interface is required because libvigilixav objects will depend on the
# interface to put unrar_iface.h in the include path, but we don't want to link
# with it.
# libvigilixunrar_iface will be dynamically loaded at run time, if enabled.
add_library(vigilixunrar_iface_iface INTERFACE)
target_sources(vigilixunrar_iface_iface
    INTERFACE
        unrar_iface.h )
target_include_directories( vigilixunrar_iface_iface
    INTERFACE
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}> )

add_library( VigilixAV::libunrar_iface_iface ALIAS vigilixunrar_iface_iface )

if(ENABLE_UNRAR)
    # not using an object library for the sake of Xcode compatibility
    # See: https://cmake.org/pipermail/cmake/2016-May/063479.html
    set(UNRAR_IFACE_SOURCES
        unrar_iface.cpp
        unrar_iface.h
    )

    if(ENABLE_SHARED_LIB)
        # The vigilixunrar_iface SHARED library.
        add_library( vigilixunrar_iface SHARED )
        set_target_properties( vigilixunrar_iface PROPERTIES
            VERSION ${LIBVIGILIXAV_VERSION}
            SOVERSION ${LIBVIGILIXAV_SOVERSION}
            CXX_STANDARD 11
        )

        target_sources( vigilixunrar_iface
            PRIVATE
                ${UNRAR_IFACE_SOURCES}
            PUBLIC
                ${CMAKE_CURRENT_SOURCE_DIR}/unrar_iface.h )

        target_include_directories( vigilixunrar_iface
            PRIVATE
                ${CMAKE_BINARY_DIR} # For vigilixav-config.h
                $<TARGET_PROPERTY:VigilixAV::libunrar,INTERFACE_INCLUDE_DIRECTORIES>
                $<TARGET_PROPERTY:VigilixAV::libvigilixav,INTERFACE_INCLUDE_DIRECTORIES> )

        set_target_properties( vigilixunrar_iface PROPERTIES
            COMPILE_FLAGS "${WARNCXXFLAGS} ${CXX1XCXXFLAGS}" )

        if (APPLE AND CLAMAV_SIGN_FILE)
            set_target_properties( vigilixunrar_iface PROPERTIES
                XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY ${CODE_SIGN_IDENTITY}
                XCODE_ATTRIBUTE_DEVELOPMENT_TEAM ${DEVELOPMENT_TEAM_ID}
            )
        endif()

        if(WIN32)
            set_target_properties(vigilixunrar_iface PROPERTIES WINDOWS_EXPORT_ALL_SYMBOLS ON)
        elseif(UNIX AND NOT APPLE AND NOT AIX)
            target_link_options(vigilixunrar_iface PRIVATE "-Wl,--version-script=${CMAKE_CURRENT_SOURCE_DIR}/libvigilixunrar_iface.map")
            if (${CMAKE_SYSTEM_NAME} MATCHES "SunOS")
                # Solaris 11.4 linker supports a subset of GNU ld version scripts, but requires a special option to enable
                target_link_options(vigilixunrar_iface PRIVATE "-Wl,-z,gnu-version-script-compat")
            endif()
        endif()

        # Private (internal-only) dependencies.
        target_link_libraries( vigilixunrar_iface
            PRIVATE
                VigilixAV::libunrar
            PUBLIC
                VigilixAV::libunrar_iface_iface)

        install(TARGETS vigilixunrar_iface COMPONENT libraries)
        if(WIN32)
            install( FILES $<TARGET_PDB_FILE:vigilixunrar_iface> TYPE BIN OPTIONAL COMPONENT libraries )
        endif()

        add_library( VigilixAV::libunrar_iface ALIAS vigilixunrar_iface )
    endif()

    if(ENABLE_STATIC_LIB)
        # The vigilixunrar_iface static library.
        add_library( vigilixunrar_iface_static STATIC)
        set_target_properties( vigilixunrar_iface_static PROPERTIES
            CXX_STANDARD 11
        )

        target_sources( vigilixunrar_iface_static
            PRIVATE
                ${UNRAR_IFACE_SOURCES}
            PUBLIC
                ${CMAKE_CURRENT_SOURCE_DIR}/unrar_iface.h )

        target_include_directories( vigilixunrar_iface_static
            PRIVATE
                ${CMAKE_BINARY_DIR} # For vigilixav-config.h
                $<TARGET_PROPERTY:VigilixAV::libunrar,INTERFACE_INCLUDE_DIRECTORIES>
                $<TARGET_PROPERTY:VigilixAV::libvigilixav,INTERFACE_INCLUDE_DIRECTORIES> )

        # Public (forwarded) dependencies.
        target_link_libraries( vigilixunrar_iface_static
            PRIVATE
                VigilixAV::libunrar_static )

        install(TARGETS vigilixunrar_iface_static COMPONENT libraries)

        add_library( VigilixAV::libunrar_iface_static ALIAS vigilixunrar_iface_static )
        if(NOT ENABLE_SHARED_LIB)
            add_library( VigilixAV::libunrar_iface ALIAS vigilixunrar_iface_static )
        endif()
    endif()
endif()
