// Generic Script consequence: invoked only by native-page and Kinect-bank changes.
function child(parent, name) {
    if (parent == null) return null;
    var nodes = parent.getContainers();
    for (var i = 0; i < nodes.length; i++) if (nodes[i].name == name) return nodes[i];
    nodes = parent.getControllables();
    for (var j = 0; j < nodes.length; j++) if (nodes[j].name == name) return nodes[j];
    return null;
}
function trigger() {
    var midi = child(child(root, "modules"), "en16");
    var page = child(child(midi, "values"), "_16_CC115").get();
    var kinect = child(child(child(root, "customVariables"), "kinect"), "variables");
    var bank = child(child(kinect, "en16KinectBank"), "en16KinectBank").get();
    var name;
    if (page == 1) name = "showEN16Fluides";
    else if (page == 0) name = bank ? "showEN16Kinect" : "showEN16Abysses";
    else return;
    var dashboard = child(child(child(root, "states"), "dashboard"), "processors");
    child(child(dashboard, name), "trigger").trigger();
}
