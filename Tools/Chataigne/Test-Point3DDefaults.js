// Run with: cscript //nologo Test-Point3DDefaults.js <Oxipital.js>
var fileSystem = new ActiveXObject("Scripting.FileSystemObject");
var sourceFile = fileSystem.OpenTextFile(WScript.Arguments(0), 1);
var source = sourceFile.ReadAll();
sourceFile.Close();
var start = source.indexOf("function addPoint3DBaseValue(");
var end = source.indexOf("function addParametersToItem(", start);
if (start < 0 || end < 0) throw new Error("Point3D initializer missing");
eval(source.substring(start, end));

function require(condition, message) {
    if (!condition) throw new Error(message);
}

function containerWith(controllables) {
    return {
        getControllables: function () { return controllables; },
        addPoint3DParameter: function (name, description) {
            // Model Chataigne's actual API: no default value argument.
            require(arguments.length == 2, "Unsupported Point3D argument");
            var point = {
                name: "baseValue",
                value: [0, 0, 0],
                set: function (value) { this.value = value; }
            };
            controllables.push(point);
            return point;
        }
    };
}

var scaleContainer = containerWith([]);
var scale = addPoint3DBaseValue(scaleContainer, [1, 1, 1]);
require(scale.value.join(",") == "1,1,1", "Emitter scale collapsed to zero");
var lookAt = addPoint3DBaseValue(containerWith([]), [0, 1, 0]);
require(lookAt.value.join(",") == "0,1,0", "Nonzero vector default lost");
scale.set([2, 3, 4]);
require(addPoint3DBaseValue(scaleContainer, [1, 1, 1]) === scale, "Existing parameter recreated");
require(scale.value.join(",") == "2,3,4", "Saved value overwritten");
var zero = { name: "baseValue", value: [0, 0, 0] };
require(addPoint3DBaseValue(containerWith([{ name: "macroWeight1" }, zero]), [1, 1, 1]) === zero,
    "Intentional saved zero replaced or macro mistaken for Base Value");
WScript.Echo("POINT3D_DEFAULTS_PASS: emitter scale, vector defaults, saved values, saved zero and macro siblings.");
