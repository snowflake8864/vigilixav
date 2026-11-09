#
# vigilixav config files
#

install(
    FILES
        ${CMAKE_CURRENT_SOURCE_DIR}/clamd.conf.sample
    RENAME
        vigilixd.conf.sample
    DESTINATION
        ${APP_CONFIG_DIRECTORY}
    COMPONENT programs)

install(
    FILES
        ${CMAKE_CURRENT_SOURCE_DIR}/freshclam.conf.sample
    RENAME
        freshvigilix.conf.sample
    DESTINATION
        ${APP_CONFIG_DIRECTORY}
    COMPONENT programs)

if(ENABLE_MILTER)
    install(
        FILES
            ${CMAKE_CURRENT_SOURCE_DIR}/clamav-milter.conf.sample
        RENAME
            vigilixav-milter.conf.sample
        DESTINATION
            ${APP_CONFIG_DIRECTORY}
        COMPONENT programs)
endif()
