cmake_minimum_required(VERSION 3.16)

file(READ "${CMAKE_SOURCE_DIR}/version.txt" VERSION_STRING_RAW)
string(STRIP "${VERSION_STRING_RAW}" VERSION_STRING)

project(euclid-rui VERSION ${VERSION_STRING})

# Resolves the Qt Installer Framework config/package XML templates (dist/win32/installer/**/*.xml.in)
# against the version above and the current timestamp - mirrors ~/work/awsmock-qt-ui's
# CMakeLists.txt. Only meaningful for the Windows installer build, but harmless to run on every
# platform/configure (the generated .xml files are gitignored, regenerated each time).
string(TIMESTAMP RELEASE_DATE "%Y-%m-%d %H:%M:%S")

file(READ "${CMAKE_SOURCE_DIR}/dist/win32/installer/config/config.xml.in" _CONFIG_XML)
string(REPLACE "@VERSION_STRING@" "${VERSION_STRING}" _CONFIG_XML "${_CONFIG_XML}")
file(WRITE "${CMAKE_SOURCE_DIR}/dist/win32/installer/config/config.xml" "${_CONFIG_XML}")

file(READ "${CMAKE_SOURCE_DIR}/dist/win32/installer/packages/de.jensvogt.euclidrui/meta/package.xml.in" _PACKAGE_XML)
string(REPLACE "@VERSION_STRING@" "${VERSION_STRING}" _PACKAGE_XML "${_PACKAGE_XML}")
string(REPLACE "@RELEASE_DATE@" "${RELEASE_DATE}" _PACKAGE_XML "${_PACKAGE_XML}")
file(WRITE "${CMAKE_SOURCE_DIR}/dist/win32/installer/packages/de.jensvogt.euclidrui/meta/package.xml" "${_PACKAGE_XML}")

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

# Statically linked Qt 6.11 build; override with -DCMAKE_PREFIX_PATH=... if needed.
if(NOT DEFINED CMAKE_PREFIX_PATH)
    set(CMAKE_PREFIX_PATH "/opt/qt-static")
endif()

set(BUILD_SHARED_LIBS OFF)

find_package(Qt6 COMPONENTS
        Core
        Gui
        Network
        Svg
        Qml
        Quick
        QuickControls2
        QuickDialogs2
        REQUIRED)

qt_standard_project_setup(REQUIRES 6.4)

qt_policy(SET QTP0004 NEW)

qt_add_executable(euclid_rui main.cpp
        AppSettings.h AppSettings.cpp
        client/EuclidBaseClient.h client/EuclidBaseClient.cpp
        client/RequestSigner.h client/RequestSigner.cpp
        client/EamClient.h client/EamClient.cpp
        client/EmmClient.h client/EmmClient.cpp
        client/EqsClient.h client/EqsClient.cpp
        client/EsmClient.h client/EsmClient.cpp
        client/EtsClient.h client/EtsClient.cpp
        client/EapClient.h client/EapClient.cpp
        client/EnsClient.h client/EnsClient.cpp
        client/EkmClient.h client/EkmClient.cpp
        client/EmoClient.h client/EmoClient.cpp
)

set_source_files_properties(qml/components/DateFormat.qml PROPERTIES
        QT_QML_SINGLETON_TYPE TRUE
)
set_source_files_properties(qml/components/SizeFormat.qml PROPERTIES
        QT_QML_SINGLETON_TYPE TRUE
)

qt_add_qml_module(euclid_rui
        URI EuclidRui
        VERSION 1.0
        QML_FILES
        qml/Main.qml
        qml/LoginDialog.qml
        qml/pages/DashboardPage.qml
        qml/pages/AnalyticsPage.qml
        qml/pages/SettingsPage.qml
        qml/pages/ModulePage.qml
        qml/pages/EamAccountsPage.qml
        qml/pages/EamNamespacesPage.qml
        qml/pages/EamUsersPage.qml
        qml/pages/EamUserDetailsPage.qml
        qml/pages/EamUserGroupDetailsPage.qml
        qml/pages/EamAccountDetailsPage.qml
        qml/pages/EamNamespaceDetailsPage.qml
        qml/pages/EamUserGroupsPage.qml
        qml/pages/EqsQueuesPage.qml
        qml/pages/EqsQueueDetailsPage.qml
        qml/pages/EqsMessagesPage.qml
        qml/pages/EqsMessageDetailsPage.qml
        qml/pages/EsmBucketsPage.qml
        qml/pages/EsmBucketDetailsPage.qml
        qml/pages/EsmObjectsPage.qml
        qml/pages/EapApplicationsPage.qml
        qml/pages/EapApplicationDetailsPage.qml
        qml/pages/EtsServersPage.qml
        qml/pages/EtsServerDetailsPage.qml
        qml/pages/EsmObjectDetailsPage.qml
        qml/pages/EnsTopicsPage.qml
        qml/pages/EnsTopicDetailsPage.qml
        qml/pages/EnsMessagesPage.qml
        qml/pages/EnsMessageDetailsPage.qml
        qml/pages/EkmKeysPage.qml
        qml/pages/EmmModulesPage.qml
        qml/pages/EkmKeyDetailsPage.qml
        qml/components/SideNav.qml
        qml/components/NavButton.qml
        qml/components/SubNavButton.qml
        qml/components/StatCard.qml
        qml/components/DetailField.qml
        qml/components/EditableText.qml
        qml/components/ImageViewer.qml
        qml/components/DataTable.qml
        qml/components/DateFormat.qml
        qml/components/SizeFormat.qml
        qml/components/Gauge.qml
        qml/components/LineChart.qml
        qml/components/AboutDialog.qml
        qml/components/ObjectTree.qml
        qml/components/FoldableTile.qml
        qml/components/ImportExportDialog.qml
        qml/components/ServiceModuleTile.qml
        qml/components/ToggleSwitch.qml
        qml/components/SectionHeader.qml
        qml/components/ActivityRow.qml
        RESOURCES
        dist/branding/euclid-icon.svg
)

# Build against the Windows GUI subsystem rather than the console one. qt_add_executable() does
# NOT do this for you - it forwards to a plain add_executable() without WIN32 - so without this the
# linker produces a console application and Windows opens a CMD window behind the app every time it
# starts, including from the installer's shortcuts. Ignored on Linux and macOS.
#
# This also brings in Qt's entry point shim: Qt6::Core only pulls in Qt6::EntryPointPrivate (which
# provides WinMain and calls main) when WIN32_EXECUTABLE is set - see qtbase/src/corelib
# /CMakeLists.txt:1569-1581 - so the two have to be turned on together, and are.
set_target_properties(euclid_rui PROPERTIES WIN32_EXECUTABLE TRUE)

# version.txt is already the single source of the version (release-please updates it, and the
# Windows installer templates are filled from it above); this hands the same string to the app so
# the window title cannot drift from what was shipped.
target_compile_definitions(euclid_rui PRIVATE APP_VERSION="${VERSION_STRING}" BUILD_DATE="${RELEASE_DATE}")

target_link_libraries(euclid_rui
        PRIVATE
        Qt6::Core
        Qt6::Gui
        Qt6::Network
        Qt6::Qml
        Qt6::Quick
        Qt6::QuickControls2
        Qt6::QuickDialogs2
        # The branding mark is an SVG, and a static build only gets the SVG image-format plugin
        # if the module is linked - without it every Image pointing at it renders nothing.
        Qt6::Svg
)
