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

        // Same iconPath as the start menu entry above. A .lnk with no icon of its own already
        // falls back to the target's, so this changes nothing about which icon is shown - it
        // writes the choice into the shortcut rather than leaving it to that fallback, which is
        // what keeps the two shortcuts from drifting apart.
        component.addOperation(
            "CreateShortcut",
            targetExe,
            installer.value("DesktopDir") + "/euclid-rui.lnk",
            "workingDirectory=" + installer.value("TargetDir"),
            "iconPath=" + targetExe,
            "description=Euclid RUI"
        );
    }
};