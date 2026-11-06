var presetPushAt = -1, presetFinalAt = -1;
var numForceGroupsParam = local.parameters.setup.numForceGroups;
var numOrbGroupsParam = local.parameters.setup.numOrbGroups;
var numMacrosParam = local.parameters.setup.numMacros;

var macrosGroup = local.parameters.macros;
var forceGroupsGroup = local.parameters.forceGroups;
var orbGroupsGroup = local.parameters.orbGroups;

var forces = [];
var orbGroups = [];
var macros = [];

//Unity links
var unityBallet = null;
var unityForceGroupsParam = null;
var unityOrbGroupsParam = null;
var macroUpdateTimestamp = null; // Used to update macro when they stop moving

//Sync state : data is pushed to Unity only on connection and when Sync Data is pressed
var pushOnNextStructure = false; // Set when Sync Data is pressed, data is pushed once the new structure is received
var structureReceived = false; // Set when a structure is received, consumed by the websocket connection that follows it
var countResyncRequested = false; // Avoids looping if Unity doesn't apply the group counts
var syncRequestTime = -1; // Time at which a delayed Sync Data should be triggered, -1 if none

var danceGroupParameters = {
	"Transform":
	{
		"Position": { "type": "p3d", "default": [0, 0, 0], "customComponent": "Transform/position" },
		"Rotation": { "type": "p3d", "default": [0, 0, 0], "customComponent": "Transform/rotation" },
	},
	"Patterns": {
		"Count": { "type": "float", "default": 1, "min": 1, "max": 10, "noMacro": true },
		"Pattern Size": { "type": "float", "default": 1, "min": 0, "max": 20 },
		"Pattern Size Spread": { "type": "float", "default": 0, "min": 0, "max": 1 },
		"Pattern Axis Spread": { "type": "float", "default": 0, "min": 0, "max": 1 },
		"Line Pattern Weight": { "type": "float", "default": 0, "min": 0, "max": 1, "customComponent": "LineDancePattern/weight" },
		"Line Pattern Speed Weight": { "type": "float", "default": 0, "min": 0, "max": 1, "customComponent": "LineDancePattern/speedWeight" },
		"Circle Pattern Weight": { "type": "float", "default": 1, "min": 0, "max": 1, "customComponent": "CircleDancePattern/weight" },
		"Circle Pattern Speed Weight": { "type": "float", "default": 1, "min": 0, "max": 1, "customComponent": "CircleDancePattern/speedWeight" },
		"Manual Pattern Weight": { "type": "float", "default": 0, "min": 0, "max": 1, "customComponent": "ManualDancePattern/weight" }
	},
	"Animation": {
		"Pattern Speed": { "type": "float", "default": 0.1, "min": -1, "max": 1 },
		"Pattern Speed Random": { "type": "float", "default": 0, "min": 0, "max": 1 },
		"Pattern Time Offset": { "type": "float", "default": 0, "min": 0, "max": 1 }

	},
	"Dancer": {
		"Dancer Size": { "type": "float", "default": 1, "min": 0, "max": 20 },
		"Emitter Scale": { "type": "p3d", "default": [1, 1, 1] },
		"Dancer Hyper Size": { "type": "float", "default": 0, "min": 0, "max": 1 },
		"Dancer Size Spread": { "type": "float", "default": 0, "min": 0, "max": 1 },
		"Dancer Weight Size Factor": { "type": "float", "default": 0, "min": 0, "max": 1 },
		"Dancer Intensity": { "type": "float", "default": 1, "min": 0, "max": 1 },
		"Dancer Rotation": { "type": "p3d", "default": [0, 0, 0] },
		"Dancer Look At": { "type": "p3d", "default": [0, 1, 0] },
		"Dancer Look At Mode": { "type": "float", "default": 0, "min": 0, "max": 2 }
	}
};

var forceGroupParameters = {
	"General": {
		"Force Factor Inside": { "type": "float", "default": 1, "min": 0, "max": 1 },
		"Force Factor Outside": { "type": "float", "default": 0, "min": 0, "max": 1 }
	},
	"Radial": {
		"Radial Intensity": { "type": "float", "default": 0, "min": 0, "max": 1 },
		"Radial Frequency": { "type": "float", "default": 0, "min": 0, "max": 1 },
		"Radial InOut": { "type": "float", "default": 0, "min": 0, "max": 1 },
		"Radial Speed Wave": { "type": "float", "default": 0, "min": 0, "max": 1 },
		"Radial Amplitude Wave": { "type": "float", "default": 0, "min": 0, "max": 1 }
	},
	"Axial": {
		"Axial Intensity": { "type": "float", "default": 0, "min": 0, "max": 1 },
		"Axis Multiplier": { "type": "p3d", "default": [0, 1, 0] },
		"Axial Factor": { "type": "float", "default": 1, "min": 1, "max": 3 },
		"Axial Frequency": { "type": "p3d", "default": [0, 0, 0] },
		"Axial Speed Wave": { "type": "float", "default": 0, "min": 0, "max": 1 },
		"Axial Amplitude Wave": { "type": "float", "default": 0, "min": 0, "max": 1 }
	},
	"Linear": {
		"Linear Intensity": { "type": "float", "default": 0, "min": 0, "max": 1 },
		"Linear Direction": { "type": "p3d", "default": [0, 0, 0] }
	},
	"Orthoradial": {
		"Ortho Intensity": { "type": "float", "default": 0, "min": 0, "max": 1 },
		"Ortho Inner Radius": { "type": "float", "default": 0.5, "min": 0, "max": 1 },
		"Ortho Factor": { "type": "float", "default": 2, "min": 1, "max": 3 },
		"Ortho Clockwise": { "type": "float", "default": 1, "min": -1, "max": 1 }
	},
	"Turbulence Curl": {
		"Curl Intensity": { "type": "float", "default": 0, "min": 0, "max": 1 },
		"Curl Frequency": { "type": "float", "default": 0, "min": 0, "max": 5 },
		"Curl Drag": { "type": "float", "default": 0, "min": 0, "max": 1 },
		"Curl Octaves": { "type": "float", "default": 1, "min": 1, "max": 8 },
		"Curl Roughness": { "type": "float", "default": 0, "min": 0, "max": 1 },
		"Curl Lacunarity": { "type": "float", "default": 0, "min": 0, "max": 1 },
		"Curl Scale": { "type": "float", "default": 0, "min": 0, "max": 1 },
		"Curl Translation": { "type": "float", "default": 0, "min": 0, "max": 1 }
	},
	"Perlin": {
		"Perlin Intensity": { "type": "float", "default": 0, "min": 0, "max": 1 },
		"Perlin Frequency": { "type": "float", "default": 0, "min": 0, "max": 5 },
		"Perlin Octaves": { "type": "float", "default": 1, "min": 1, "max": 8 },
		"Perlin Roughness": { "type": "float", "default": 0, "min": 0, "max": 1 },
		"Perlin Lacunarity": { "type": "float", "default": 0, "min": 0, "max": 1 },
		"Perlin Translation Speed": { "type": "float", "default": 0, "min": 0, "max": 1 }
	},
	"Orthoaxial": {
		"Orthoaxial Intensity": { "type": "float", "default": 0, "min": 0, "max": 1 },
		"Orthoaxial Inner Radius": { "type": "float", "default": 0, "min": 0, "max": 1 },
		"Orthoaxial Factor": { "type": "float", "default": 1, "min": 1, "max": 3 },
		"Orthoaxial Clockwise": { "type": "float", "default": 0, "min": -1, "max": 1 }
	},
	"Spiral": {
		"Spiral Intensity": { "type": "float", "default": 0, "min": 0, "max": 1 },
		"Spiral Frequency": { "type": "float", "default": 1, "min": 0, "max": 3 },
		"Spiral Vertical Force": { "type": "float", "default": 0.5, "min": 0, "max": 1 },
		"Spiral Direction": { "type": "float", "default": 0, "min": 0, "max": 1 }		
	}
};


var orbGroupParameters = {
	"General": {
		"Life": { "type": "float", "default": 20, "min": 0, "max": 120 },
		"Infinite Life": { "type": "bool", "default": false },
		"Emitter Shape": { "type": "enum", "default": "Sphere", "values": ["Sphere", "Plane", "Torus", "Cube", "Pipe", "Egg", "Line", "Circle", "Merkaba", "Pyramid", "Custom", "Augmenta"] },
		"Render Type": {"type": "enum", "default" : "UnlitAdditive", "values":["UnlitOpaque", "UnlitAdditive", "LitQuad", "LitMesh"]},
		"Emitter Surface Factor": { "type": "float", "default": 0, "min": 0, "max": 1 },
		"Emitter Volume Factor": { "type": "float", "default": 0, "min": 0, "max": 1 },
		"Emitter Position Noise": { "type": "float", "default": 0, "min": 0, "max": 1 },
		"Emitter Position Noise Frequency": { "type": "float", "default": 1, "min": 0, "max": 5 },
		"Emitter Position Noise Radius": { "type": "float", "default": 0.1, "min": 0, "max": 1 },
		"Custom Mesh Name":{"type":"string", "default":"sphere"},
	},
	"Appearance": {
		"Color": { "type": "color", "default": [.8, 2, .05] },
		"Color Life": { "type": "color", "default": [0, 0, 0] },
		"Color Life Range": { "type": "float", "default": 1, "min": 0, "max": 1 },
		"Color Life Blend": { "type": "float", "default": 0, "min": 0, "max": 1 },
		"Color Speed": { "type": "color", "default": [0, 0, 0] },
		"Color Speed Range": { "type": "float", "default": 1, "min": 0, "max": 1 },
		"Color Speed Blend": { "type": "float", "default": 0, "min": 0, "max": 1 },
		"Color Max Speed": { "type": "float", "default": 1	, "min": 0, "max": 1 },
		"Alpha": { "type": "float", "default": 0.2, "min": 0, "max": 1 },
		"HDR Multiplier": { "type": "float", "default": 0, "min": 0, "max": 1 },
		"Alpha Speed Threshold": { "type": "float", "default": 0, "min": 0, "max": 1 },
		"Texture Opacity": { "type": "float", "default": 0, "min": 0, "max": 1 },
		"Particle Size": { "type": "float", "default": 0, "min": 0, "max": 1 },
	},
	"Physics": {
		"Force Weight": { "type": "float", "default": 1, "min": 0, "max": 1 },
		"Drag": { "type": "float", "default": 0.5, "min": 0, "max": 1 },
		"Velocity Drag": { "type": "float", "default": 0, "min": 0, "max": 1 },
		"Noisy Drag": { "type": "float", "default": 0, "min": 0, "max": 1 },
		"Noisy Drag Frequency": { "type": "float", "default": 0, "min": 0, "max": 1 },
		"Activate Collision": { "type": "bool", "default": false }
	}
};


//CALLBACKS
function init() {
	linkUnity();
	setup();

	macroUpdateTimestamp = util.getTimestamp();
	presetPushAt = util.getTime() + 0.2;
}

function update(deltaTime)
{
	processPresetPushes();
	if (syncRequestTime >= 0 && util.getTime() >= syncRequestTime) {
		syncRequestTime = -1;
		structureReceived = false;
		local.parameters.syncData.trigger();
		return;
	}
	// Structure and connection callbacks can arrive in either order.
	// Push once, from update, after the final structure has been applied.
	if (pushOnNextStructure && structureReceived && syncRequestTime < 0) {
		pushOnNextStructure = false;
		pushAllToUnity();
	}
}


function moduleParameterChanged(param) {
	if (handleShowSyncControl(param)) return;

	if (param.is(local.parameters.syncData)) {
		pushOnNextStructure = true;
		structureReceived = false;
	} else if (param.is(local.parameters.isConnected)) {
		if (param.get()) onConnected();
		else structureReceived = false;
	} else if (param.is(numForceGroupsParam)) {
		if (unityForceGroupsParam) unityForceGroupsParam.set(numForceGroupsParam.get());
		setupForces();
		linkArrays();
	} else if (param.is(numOrbGroupsParam)) {
		if (unityOrbGroupsParam) unityOrbGroupsParam.set(numOrbGroupsParam.get());
		setupOrbs();
		linkArrays();
	} else if (param.is(numMacrosParam)) {
		setup();
	} else if (param.getParent().is(macrosGroup)) {
		updateAllParametersForMacro(param);
		macroUpdateTimestamp = util.getTimestamp();
	} else if (param.is(local.parameters.setup.resetAllMacro)) {
		resetGroupMacro(orbGroups);
		resetGroupMacro(forces);
	} else if (param.is(local.parameters.setup.sendDataToUnity)) {
		requestSync(0); // Same as pressing Sync Data
	} else {
		var p4 = param.getParent(4);
		if (p4 == forceGroupsGroup) {
			var forceIndex = parseInt(param.getParent(3).niceName.split(" ")[2]) - 1;
			var groupName = param.getParent(2).niceName;
			var paramName = param.getParent().niceName;
			updateParam(forceIndex, groupName, paramName, param, forceGroupParameters, forces);
		} else if (p4 == orbGroupsGroup) {
			var orbGroupIndex = parseInt(param.getParent(3).niceName.split(" ")[2]) - 1;
			var groupName = param.getParent(2).niceName;
			var paramName = param.getParent().niceName;
			updateParam(orbGroupIndex, groupName, paramName, param, orbGroupParameters, orbGroups);
		}
	}
}

function dataStructureEvent() {
	// This response satisfies a reconnect request even when the socket
	// opened before Chataigne dispatched the structure callback.
	syncRequestTime = -1;
	structureReceived = false;
	var countsChanged = linkUnity();
	if (countsChanged) {
		if (!countResyncRequested) {
			countResyncRequested = true;
			requestSync(0.5);
		} else {
			script.logWarning("Unity group counts are not ready; use Sync Data to retry");
		}
		return;
	}
	countResyncRequested = false;
	structureReceived = true;
	pushOnNextStructure = true;
}

function onConnected() {
	// requestStructure() dispatches its result asynchronously, while the
	// WebSocket opens independently. Give that callback time to arrive.
	if (!structureReceived && syncRequestTime < 0) requestSync(0.5);
}

function requestSync(delay) {
	syncRequestTime = util.getTime() + delay;
}


//UPDATE
function updateAllParametersForMacro(macroParam) {
	var index = macrosGroup.getControllables().indexOf(macroParam);

	updateAllParameters(index, forces, forceGroupParameters);
	updateAllParameters(index, orbGroups, orbGroupParameters);
}

function updateAllParameters(index, items, parameters) {
	for (var i = 0; i < items.length; i++) {
		var item = items[i];
		var itemGroups = item.getContainers();

		for (var j = 0; j < itemGroups.length; j++) {
			var itemGroup = itemGroups[j];
			var itemParams = itemGroup.getContainers();
			for (var k = 0; k < itemParams.length; k++) {
				var itemParamGroup = itemParams[k];

				var macroParam = findControllable(itemParamGroup, "macroWeight" + (index + 1));
				if (macroParam == null || macroParam.get() == 0) continue;

				updateParam(i, itemGroup.niceName, itemParamGroup.niceName, macroParam, parameters, items);
			}
		}
	}
}



function pushAllParameters(items, parameters, forceSend) {
	for (var i = 0; i < items.length; i++) {
		var itemGroups = items[i].getContainers();

		for (var j = 0; j < itemGroups.length; j++) {
			var itemGroup = itemGroups[j];
			var itemParams = itemGroup.getContainers();

			for (var k = 0; k < itemParams.length; k++) {
				updateParam(i, itemGroup.niceName, itemParams[k].niceName, null, parameters, items, forceSend);
			}
		}
	}
}

function updateParam(index, groupName, paramName, sourceParam, parameters, items, forceSend) {
	/*if (sourceParam != null) {
		var macroIndex = sourceParam.getParent().getControllables().indexOf(sourceParam);
		if (macroIndex > 0 && macros[macroIndex - 1].get() == 0) {
			return;
		}
	}*/

	var targetParams = danceGroupParameters[groupName] ? danceGroupParameters : parameters;
	if (targetParams[groupName] == null) return;

	var paramProps = targetParams[groupName][paramName];
	if (paramProps == null) return;

	var item = items[index];
	if (item == null) return;
	var itemGroup = item.getChild(groupName);
	if (itemGroup == null) return;
	var itemParamGroup = itemGroup.getChild(paramName);
	if (itemParamGroup == null) return;
	var itemParam = findControllable(itemParamGroup, "baseValue");
	if (itemParam == null) {
		script.logWarning("No Base Value for " + item.niceName + " > " + groupName + " > " + paramName);
		return;
	}
	var paramMin = paramProps.min;
	var paramMax = paramProps.max;

	//script.log("Updating " + groupName + "/" + paramName + " for " + item.niceName + "," + index);

	var managerName = item.getParent().niceName;

	var finalValue = itemParam.get();

	if (!paramProps.noMacro) {
		if (paramMin != null && paramMax != null) {
			for (var i = 0; i < numMacrosParam.get(); i++) {
				var macroWeightParam = findControllable(itemParamGroup, "macroWeight" + (i + 1));
				if (macroWeightParam == null || macros[i] == null) continue;
				var macroWeight = macroWeightParam.get();
				var macroValue = macros[i].get();
				var macroInfluence = macroValue * macroWeight * (paramMax - paramMin);
				finalValue += macroInfluence;
			}
		}
	}

	if (paramMin != null && paramMax != null) finalValue = Math.min(paramMax, Math.max(paramMin, finalValue));


	var paramPath = "";
	if (paramProps.customComponent != null) {
		// script.log("Using custom component : " + paramProps.customComponent);
		paramPath = paramProps.customComponent;
	} else {
		var unityComponentName = parameters == forceGroupParameters ? "StandardForceGroup" : "OrbGroup";
		paramPath = unityComponentName + "/" + itemParamGroup.name;
	}


	updateUnityParam(managerName, item.niceName, paramPath, finalValue, forceSend);
}



// SETUP

function setup() {
	script.log("Setting up");
	setupMacros(); //setupMacros sets up the other ones
	linkArrays();
}

function clearItems(group) {
	group.clear();
}

function linkArrays() {
	macros = macrosGroup.getControllables();
	forces = forceGroupsGroup.getContainers();
	orbGroups = orbGroupsGroup.getContainers();
}

// Returns true if Unity's group counts had to be changed
function linkUnity() {
	unityBallet = local.values.getChild("ballet");
	unityOrbGroupsParam = null;
	unityForceGroupsParam = null;

	if (unityBallet == null) {
		script.log("No ballet found");
		return false;
	}

	var unityOrbs = unityBallet.getChild(orbGroupsGroup.niceName);
	var unityForces = unityBallet.getChild(forceGroupsGroup.niceName);

	if (unityOrbs != null) unityOrbGroupsParam = unityOrbs.OrbManager.count;
	if (unityForces != null) unityForceGroupsParam = unityForces.StandardForceManager.count;

	var countsChanged = false;
	if (unityOrbGroupsParam && unityOrbGroupsParam.get() != numOrbGroupsParam.get()) {
		unityOrbGroupsParam.set(numOrbGroupsParam.get());
		countsChanged = true;
	}
	if (unityForceGroupsParam && unityForceGroupsParam.get() != numForceGroupsParam.get()) {
		unityForceGroupsParam.set(numForceGroupsParam.get());
		countsChanged = true;
	}

	return countsChanged;
}

function setupMacros() {

	var group = macrosGroup;

	while (group.getControllables().length > numMacrosParam.get()) {
		group.removeParameter("macro" + (group.getControllables().length));
	}

	while (group.getControllables().length < numMacrosParam.get()) {
		var macro = group.addFloatParameter("Macro " + (group.getControllables().length + 1), "Macro value", 0, 0, 1);
	}

	macrosGroup = local.parameters.getChild("macros");
	macros = macrosGroup.getControllables();

	setupForces();
	setupOrbs();

	linkArrays();
}

function setupForces() {
	if (numForceGroupsParam == null) return;
	setupParameters(forceGroupsGroup, numForceGroupsParam, forceGroupParameters, forces, "Force Group");
}

function setupOrbs() {
	if (numOrbGroupsParam == null) return;
	setupParameters(orbGroupsGroup, numOrbGroupsParam, orbGroupParameters, orbGroups, "Orb Group");
}

function setupParameters(group, numParam, parameters, items, prefix) {

	var numItems = numParam.get();

	var existingItems = group.getContainers();
	var numExistingItems = existingItems ? existingItems.length : 0;

	while (numExistingItems > numItems) {
		group.removeContainer(existingItems[numExistingItems - 1].name);
		numExistingItems--;
		items.splice(items.length - 1);
	}

	for (var i = 0; i < Math.min(numExistingItems, numItems); i++) {
		// Saved sessions can contain parameters that were removed from the definitions, and miss
		// parameters that were added since or that were not saved because they had their default value
		removeUnknownParameters(existingItems[i], parameters);
		addParametersToItem(existingItems[i], danceGroupParameters);
		addParametersToItem(existingItems[i], parameters);
		setupMacrosToItem(existingItems[i]);
	}

	for (var i = numExistingItems; i < numItems; i++) {
		createItem(i, group, parameters, prefix);
	}
}

function createItem(index, group, parameters, prefix) {
	var item = group.addContainer(prefix + " " + (index + 1));
	item.setCollapsed(true);

	addParametersToItem(item, danceGroupParameters);
	addParametersToItem(item, parameters);

	setupMacrosToItem(item);

	return item;
}

// Chataigne's addPoint3DParameter only accepts name and description.
// Set new values explicitly; keep values restored from a saved session.
function addPoint3DBaseValue(container, initialValue) {
	var existing = container.getControllables();
	for (var i = 0; i < existing.length; i++) {
		if (existing[i].name == "baseValue") return existing[i];
	}
	var point = container.addPoint3DParameter("Base Value", "Base value for this parameter");
	point.set(initialValue);
	return point;
}

function addParametersToItem(item, parameters) {
	var paramGroupProps = util.getObjectProperties(parameters);
	for (var i = 0; i < paramGroupProps.length; i++) {
		var groupName = paramGroupProps[i];
		var groupParams = parameters[groupName];
		var paramGroup = item.addContainer(groupName); // returns the existing container if any
		var paramProps = util.getObjectProperties(groupParams);
		for (var j = 0; j < paramProps.length; j++) {
			var paramName = paramProps[j];
			var paramContainer = paramGroup.addContainer(paramName);
			if (findControllable(paramContainer, "baseValue") != null) continue;

			var paramConfig = groupParams[paramName];
			var paramType = paramConfig.type;
			var paramDefault = paramConfig.default;
			var paramMin = paramConfig.min;
			var paramMax = paramConfig.max;

			if (paramType == "float") {
				if (paramMin != null && paramMax != null) paramContainer.addFloatParameter("Base Value", "Base value for this parameter", paramDefault, paramMin, paramMax);
				else if (paramMin != null) paramContainer.addFloatParameter("Base Value", "Base value for this parameter", paramDefault, paramMin);
				else paramContainer.addFloatParameter("Base Value", "Base value for this parameter", paramDefault);
			} else if (paramType == "int") {
				if (paramMin != null && paramMax != null) paramContainer.addIntParameter("Base Value", "Base value for this parameter", paramDefault, paramMin, paramMax);
				else if (paramMin != null) paramContainer.addIntParameter("Base Value", "Base value for this parameter", paramDefault, paramMin);
				else paramContainer.addIntParameter("Base Value", "Base value for this parameter", paramDefault);
			} else if (paramType == "p3d") {
				addPoint3DBaseValue(paramContainer, paramDefault);
			} else if (paramType == "color") {
				paramContainer.addColorParameter("Base Value", "Base value for this parameter", paramDefault);
			} else if (paramType == "enum") {
				var ep = paramContainer.addEnumParameter("Base Value", "Base value for this parameter", paramDefault);
				for (var v = 0; v < paramConfig.values.length; v++) {
					ep.addOption(paramConfig.values[v], paramConfig.values[v]);
				}
			} else if (paramType == "bool") {
				paramContainer.addBoolParameter("Base Value", "Base value for this parameter", paramDefault);
			} else if (paramType == "string") {
				paramContainer.addStringParameter("Base Value", "Base value for this parameter", paramDefault);
			}
		}
	}
}

function setupMacrosToItem(item) {
	var paramGroups = item.getContainers();
	for (var i = 0; i < paramGroups.length; i++) {
		var paramGroup = paramGroups[i];
		// script.log('> ' + paramGroup.niceName);;
		var params = paramGroup.getContainers();
		for (var j = 0; j < params.length; j++) {
			var paramContainer = params[j];

			var paramProp = getPropForParam(paramContainer);
			if (paramProp == null) continue;

			// Macros only apply to numeric parameters with a range, see updateParam
			var hasMacros = !paramProp.noMacro && (paramProp.type == "float" || paramProp.type == "int") && paramProp.min != null && paramProp.max != null;
			var numMacros = hasMacros ? numMacrosParam.get() : 0;

			// Weights are checked by name, as weights left at 0 are not saved in the session
			var controllables = paramContainer.getControllables();
			for (var k = 0; k < controllables.length; k++) {
				var cName = controllables[k].name;
				if (cName.indexOf("macroWeight") == 0 && parseInt(cName.substring(11)) > numMacros) paramContainer.removeParameter(cName);
			}

			for (var k = 1; k <= numMacros; k++) {
				if (findControllable(paramContainer, "macroWeight" + k) != null) continue;
				paramContainer.addFloatParameter("Macro Weight " + k, "Macro influence for this parameter, relative to the parameters range if it has any", 0, -1, 1);
			}
		}
	}
}

function getPropForParam(param) {
	var paramName = param.niceName;
	var paramGroupName = param.getParent().niceName;

	var group = param.getParent(3);

	var isDanceGroup = danceGroupParameters[paramGroupName] != null;
	var items = isDanceGroup ? danceGroupParameters : (group.is(forceGroupsGroup) ? forceGroupParameters : orbGroupParameters);

	var groupProps = items[paramGroupName];
	if (groupProps == null) return null;
	return groupProps[paramName];
}

// Removes categories and parameters that are not in the definitions anymore
function removeUnknownParameters(item, parameters) {
	var paramGroups = item.getContainers();
	for (var i = 0; i < paramGroups.length; i++) {
		var paramGroup = paramGroups[i];
		var groupProps = danceGroupParameters[paramGroup.niceName];
		if (groupProps == null) groupProps = parameters[paramGroup.niceName];

		if (groupProps == null) {
			script.log("Removing unknown category " + item.niceName + " > " + paramGroup.niceName);
			item.removeContainer(paramGroup.name);
			continue;
		}

		var params = paramGroup.getContainers();
		for (var j = 0; j < params.length; j++) {
			if (groupProps[params[j].niceName] != null) continue;
			script.log("Removing unknown parameter " + item.niceName + " > " + paramGroup.niceName + " > " + params[j].niceName);
			paramGroup.removeContainer(params[j].name);
		}
	}
}

// Same as getChild but without logging when the child doesn't exist
function findControllable(container, shortName) {
	var controllables = container.getControllables();
	for (var i = 0; i < controllables.length; i++) {
		if (controllables[i].name == shortName) return controllables[i];
	}
	return null;
}

function resetGroupMacro(groups) {
	script.log("Resetting all macros");

	for (var i = 0; i < groups.length; i++) { // Orb or Force Groups
		var group = groups[i];
		var groupContainers = group.getContainers();

		for (var j = 0; j < groupContainers.length; j++) { // Parameter containers
			var groupContainer = groupContainers[j];
			var groupChildren = groupContainer.getContainers();

			for( var k = 0; k < groupChildren.length; k++) { // Item in each parameter container
				var itemParamGroup = groupChildren[k];
				var itemParamChildren = itemParamGroup.getControllables();

				for( var l = 0; l < itemParamChildren.length; l++) { // Macro weight params
					var macroWeightParam = itemParamChildren[l];
					if (macroWeightParam.name.indexOf("macroWeight") == 0) macroWeightParam.set(0);
				}
			}
		}
	}
}

// Helpers installed into the existing Oxipital bridge by Add-ShowSynchronization.ps1.
function isUnityEditing() {
    return local.parameters.setup && local.parameters.setup.unityEditMode && local.parameters.setup.unityEditMode.get();
}

function processPresetPushes() {
    if (isUnityEditing()) return;
    var now = util.getTime();
    if (presetPushAt >= 0 && now >= presetPushAt) {
        presetPushAt = -1;
        pushAllToUnity();
    }
    if (presetFinalAt >= 0 && now >= presetFinalAt) {
        presetFinalAt = -1;
        pushAllToUnity();
    }
}

function handleShowSyncControl(param) {
    var setup = local.parameters.setup;
    if (!setup) return false;
    if (setup.applyCurrentValues && param.is(setup.applyCurrentValues)) {
        if (!isUnityEditing()) {
            var duration = setup.presetApplyDuration ? setup.presetApplyDuration.get() : 0;
            presetPushAt = util.getTime() + 0.1;
            presetFinalAt = util.getTime() + Math.max(0, duration) + 0.2;
        }
        return true;
    }
    if (setup.unityEditMode && param.is(setup.unityEditMode)) {
        presetPushAt = isUnityEditing() ? -1 : util.getTime() + 0.2;
        presetFinalAt = -1;
        return true;
    }
    return false;
}

function unityOSCName(name) {
    return name.split(" ").join("_").split("(").join("").split(")").join("");
}

function updateUnityParam(managerName, itemName, paramPath, value, forceSend) {
    if (value == null || isUnityEditing()) return;
    // Preset transforms must still reach Unity when its OSCQuery tree is
    // missing or stale. These two addresses are fixed by the bridge schema.
    if (forceSend && (paramPath == "Transform/position" || paramPath == "Transform/rotation")) {
        var balletName = unityBallet == null ? "Ballet" : unityBallet.niceName;
        local.send("/" + unityOSCName(balletName) + "/" + unityOSCName(managerName) +
            "/" + unityOSCName(itemName) + "/" + paramPath, value);
        return;
    }
    if (unityBallet == null) return;
    var manager = unityBallet.getChild(managerName);
    if (manager == null) return;
    var item = manager.getChild(itemName);
    if (item == null) return;
    var param = item.getChild(paramPath);
    if (param == null) return;
    if (forceSend) {
        // The resolved OSCQuery control retains Unity's exact field spelling
        // (e.g. hdrMultiplier vs the bridge UI's hDRMultiplier).
        var parts = paramPath.split("/");
        if (param.name) parts[parts.length - 1] = param.name;
        var oscPath = parts.join("/");
        // OSCQuery's explicit send bypasses unchanged-value suppression in
        // Chataigne's local parameter cache. Arrays are OSC argument lists.
        local.send("/" + unityOSCName(unityBallet.niceName) + "/" + unityOSCName(managerName) +
            "/" + unityOSCName(itemName) + "/" + oscPath, value);
    } else param.set(value);
}

function getKinectShowValue(name) {
    if (typeof root == "undefined") return null;
    var control = root.getChild("customVariables/kinect/variables/" + name + "/" + name);
    return control == null ? null : control.get();
}

function pushKinectToUnity() {
    if (isUnityEditing()) return;
    var prefix = "/Ballet/Optical_Flow/";
    var fields = [
        ["brushEnabled", "brushEnabled"], ["sendForcesPosition", "controlForcePosition"],
        ["sendOrbsPosition", "controlOrbPosition"], ["controlIntensityRadius", "controlBrushParameters"],
        ["controlOrientation", "controlForceOrientation"], ["controlOrbRadius", "controlOrbRadius"],
        ["controlOrbOrientation", "controlOrbOrientation"], ["strength", "strength"],
        ["radiusMultiplier", "radiusMultiplier"], ["sizeMultiplier", "sizeMultiplier"],
        ["orbRadiusMultiplier", "orbRadiusMultiplier"], ["minimumRadius", "minimumRadius"],
        ["maximumRadius", "maximumRadius"], ["smoothingSeconds", "smoothingSeconds"],
        ["activationFadeSeconds", "activationFadeSeconds"], ["forceGroupNumber", "forceGroupNumber"],
        ["orbGroupNumber", "orbGroupNumber"], ["unityBrushIndex", "selectedBrush"],
        ["interactionDepth", "interactionDepth"], ["useTargetDepth", "useTargetDepth"],
        ["minimumAxisDistance", "minimumAxisDistance"], ["showMonitor", "showMonitor"],
        ["showHandOverlay", "showHandOverlay"], ["invertGestureIntensity", "invertGestureIntensity"],
        ["twoHandOrbs", "twoHandOrbs"], ["monitorScale", "monitorScale"]
    ];
    for (var i = 0; i < fields.length; i++) {
        var value = getKinectShowValue(fields[i][0]);
        if (value != null) local.send(prefix + "TwoHandForceBrush/" + fields[i][1], value);
    }
    var x = getKinectShowValue("orientationOffsetX"), y = getKinectShowValue("orientationOffsetY"), z = getKinectShowValue("orientationOffsetZ");
    if (x != null && y != null && z != null) local.send(prefix + "TwoHandForceBrush/orientationOffset", [x, y, z]);
    var flow = [["debugOverlayOpacity", "OpticalFlowDebugView/overlayOpacity"],
        ["opticalFlowIntensity", "OpticalFlowManager/intensity"], ["opticalFlowStrength", "OpticalFlowManager/strength"]];
    for (var j = 0; j < flow.length; j++) {
        var flowValue = getKinectShowValue(flow[j][0]);
        if (flowValue != null) local.send(prefix + flow[j][1], flowValue);
    }
    // Enable only after the independent switches and target group numbers.
    var enabled = getKinectShowValue("kinectEnabled");
    if (enabled != null) local.send(prefix + "TwoHandForceBrush/remoteControlEnabled", enabled);
}

function pushAllToUnity() {
    if (isUnityEditing()) return;
    // OnDisable restores owned group settings. Release before applying the
    // scene snapshot so it cannot overwrite the newly recalled preset.
    if (getKinectShowValue("kinectEnabled") != null)
        local.send("/Ballet/Optical_Flow/TwoHandForceBrush/remoteControlEnabled", false);
    linkArrays();
    pushAllParameters(forces, forceGroupParameters, true);
    pushAllParameters(orbGroups, orbGroupParameters, true);
    pushKinectToUnity();
}
