cmake_minimum_required(VERSION 3.16)
project(euclid-rui)

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
        client/EamClient.h client/EamClient.cpp
        client/EmmClient.h client/EmmClient.cpp
        client/EqsClient.h client/EqsClient.cpp
        client/EsmClient.h client/EsmClient.cpp
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
        qml/pages/EqsQueuesPage.qml
        qml/pages/EqsQueueDetailsPage.qml
        qml/pages/EqsMessagesPage.qml
        qml/pages/EsmBucketsPage.qml
        qml/pages/EsmBucketDetailsPage.qml
        qml/pages/EsmObjectsPage.qml
        qml/pages/EnsTopicsPage.qml
        qml/pages/EnsTopicDetailsPage.qml
        qml/pages/EnsMessagesPage.qml
        qml/pages/EkmKeysPage.qml
        qml/pages/EkmKeyDetailsPage.qml
        qml/components/SideNav.qml
        qml/components/NavButton.qml
        qml/components/SubNavButton.qml
        qml/components/StatCard.qml
        qml/components/DetailField.qml
        qml/components/DataTable.qml
        qml/components/DateFormat.qml
        qml/components/SizeFormat.qml
        qml/components/Gauge.qml
        qml/components/ToggleSwitch.qml
        qml/components/SectionHeader.qml
        qml/components/ActivityRow.qml
)

target_link_libraries(euclid_rui
        PRIVATE
        Qt6::Core
        Qt6::Gui
        Qt6::Network
        Qt6::Qml
        Qt6::Quick
        Qt6::QuickControls2
        Qt6::QuickDialogs2
)
