function Component() {}

Component.prototype.createOperations = function()
{
    component.createOperations();

    if (systemInfo.productType === "windows") {

        var targetExe = installer.value("TargetDir") + "/euclid-rui.exe";

        var startMenuDir =
            installer.value("StartMenuDir") + "/euclid";

        component.addOperation(
            "CreateShortcut",
            targetExe,
            startMenuDir + "/euclid-rui.lnk",
            "workingDirectory=" + installer.value("TargetDir"),
            "iconPath=" + targetExe,
            "description=Euclid RUI"
        );

        component.addOperation(
            "CreateShortcut",
            installer.value("TargetDir") + "/euclid-rui.exe",
            installer.value("DesktopDir") + "/euclid-rui.lnk",
            "workingDirectory=" + installer.value("TargetDir")
        );
    }
};