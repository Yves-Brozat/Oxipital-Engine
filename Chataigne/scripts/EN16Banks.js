// One native EN16 page, three software banks. Loading does not change the show.
var operation = script.addStringParameter("Operation", "cycle or apply", "apply");
function child(parent, name) {
    if (parent == null) return null;
    var items = parent.getContainers();
    for (var i = 0; i < items.length; i++) if (items[i].name == name) return items[i];
    items = parent.getControllables();
    for (var j = 0; j < items.length; j++) if (items[j].name == name) return items[j];
    return null;
}
function variable(group, name) {
    return child(child(child(child(root,"customVariables"),group),"variables"),name);
}
function control(group, name) { return child(variable(group,name),name); }
function trigger() {
    var bankControl = control("en16Banks","bank");
    var bank = bankControl.get();
    if (operation.get() == "cycle") { bankControl.set((bank + 1) % 3); return; }
    // Clear held inputs in every bank before the next physical event arrives.
    for (var i = 1; i <= 16; i++) {
        control("kinect","en16AbyssesButton"+i).set(0);
        control("kinect","en16KinectButton"+i).set(0);
        control("en16Banks","fluidButton"+i).set(0);
    }
    control("kinect","en16KinectBank").set(bank == 1);
    var names = ["showEN16Abysses","showEN16Kinect","showEN16Fluides"];
    if (bank < 0 || bank > 2) return;
    var processors = child(child(child(root,"states"),"dashboard"),"processors");
    child(child(processors,names[bank]),"trigger").trigger();
}
