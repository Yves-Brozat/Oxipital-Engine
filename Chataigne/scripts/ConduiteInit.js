// Generic Script consequence. Loading the file does not start playback.
// Restart explicitly, including on Chataigne versions where Trigger Current
// does not rewind the current cue's linked sequence.
function child(parent, name) {
    var nodes = parent.getContainers();
    for (var i = 0; i < nodes.length; i++) if (nodes[i].name == name) return nodes[i];
    nodes = parent.getControllables();
    for (var j = 0; j < nodes.length; j++) if (nodes[j].name == name) return nodes[j];
    return null;
}
function trigger() {
    var conductor = child(child(child(root, "states"), "conduite"), "processors");
    conductor = child(conductor, "conductor");
    var currentName = child(conductor, "currentCueName").get();
    if (currentName == "") {
        child(conductor, "nextCue").set(1);
        child(conductor, "trigger").trigger();
        return;
    }
    var names = ["Meduse", "Chute", "Cascade", "Tornade", "Tourbillon", "Cercle"];
    var keys = ["meduse", "chute", "cascade", "tornade", "tourbillon", "cercle"];
    for (var i = 0; i < names.length; i++) {
        if (names[i] != currentName) continue;
        var sequence = child(child(root, "sequences"), keys[i]);
        child(sequence, "stop").trigger();
        child(sequence, "play").trigger();
        return;
    }
    script.logWarning("Conduite Init: unknown cue " + currentName);
}
