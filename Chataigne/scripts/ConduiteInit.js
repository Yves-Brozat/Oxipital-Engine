// Generic Script consequence. Loading the file does not start playback.
// Restart the whole show at Meduse, including when Meduse is already current.
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
    var keys = ["meduse", "chute", "cascade", "tornade", "tourbillon", "cercle"];
    var sequences = child(root, "sequences");
    for (var i = 0; i < keys.length; i++) {
        var sequence = child(sequences, keys[i]);
        child(sequence, "stop").trigger();
    }
    child(conductor, "nextCue").set(1);
    child(conductor, "trigger").trigger();
    // Older Chataigne versions do not restart a cue that is already current.
    // Starting only when stopped avoids launching Meduse twice on newer ones.
    var first = child(sequences, "meduse");
    if (!child(first, "isPlaying").get()) child(first, "play").trigger();
}
