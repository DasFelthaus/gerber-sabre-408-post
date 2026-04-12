/**
  Gerber Sabre 408 - SAB N.3 Controller
  Post processor for Autodesk Fusion

  Based on Autodesk Generic GRBL post processor.
  Adapted for SAB N.3 controller with 2.5-axis operation.
*/

description = "Gerber Sabre 408 - SAB N.3";
vendor = "Gerber Technology";
vendorUrl = "";
legal = "";
certificationLevel = 2;
minimumRevision = 45917;

longDescription = "Post processor for Gerber Sabre 408 router with SAB N.3 controller. " +
  "Outputs inch-mode G-code (G20) only. Default mode is 2.5-axis (XY and Z moves are split). " +
  "Enable 'Allow full 3-axis movement' for simultaneous XYZ interpolation and helical arcs. " +
  "All drilling cycles expanded to G00/G01 moves.";

extension = "nc";
setCodePage("ascii");


capabilities = CAPABILITY_MILLING;
tolerance = spatial(0.05, MM);

minimumChordLength = spatial(0.25, MM);
minimumCircularRadius = spatial(0.5, MM);
maximumCircularRadius = spatial(1000, MM);
minimumCircularSweep = toRad(0.01);
maximumCircularSweep = toRad(180);

// CRITICAL: Only allow XY plane arcs - no helical moves
allowHelicalMoves = false;
allowedCircularPlanes = (1 << PLANE_XY);
highFeedrate = toPreciseUnit(850, IN); // ipm - used internally by post engine

// user-defined properties
properties = {
  useLineNumbers: {
    title      : "Use line numbers",
    description: "Output N-word line numbers on each block.",
    group      : "formats",
    type       : "boolean",
    value      : true,
    scope      : "post"
  },
  lineNumberStart: {
    title      : "Start line number",
    description: "The number at which to start the line numbers.",
    group      : "formats",
    type       : "integer",
    value      : 10,
    scope      : "post"
  },
  lineNumberIncrement: {
    title      : "Line number increment",
    description: "The amount by which the line number is incremented by in each block.",
    group      : "formats",
    type       : "integer",
    value      : 10,
    scope      : "post"
  },
  linearizeArcs: {
    title      : "Linearize arcs",
    description: "Convert all arcs to G01 line segments. Enable if arcs cause issues on the SAB N.3.",
    group      : "preferences",
    type       : "boolean",
    value      : false,
    scope      : "post"
  },
  showComments: {
    title      : "Show comments",
    description: "Output comments in parentheses. Disable if the SAB N.3 rejects them.",
    group      : "formats",
    type       : "boolean",
    value      : true,
    scope      : "post"
  },
  showToolInfo: {
    title      : "Show tool info",
    description: "Output tool information as comments in the header (requires Show comments).",
    group      : "formats",
    type       : "boolean",
    value      : true,
    scope      : "post"
  },
  showOperationComments: {
    title      : "Show operation comments",
    description: "Output the operation name as a comment at the start of each section (e.g. (2D POCKET2)). Requires Show comments.",
    group      : "formats",
    type       : "boolean",
    value      : true,
    scope      : "post"
  },
  maxFeedrate: {
    title      : "Max feedrate (mm/min)",
    description: "Maximum feedrate in mm/min. SAB N.3 max positioning rate is 21590 mm/min (850 ipm).",
    group      : "preferences",
    type       : "number",
    value      : 10000,
    scope      : "post"
  },
  safeRetractHeight: {
    title      : "Safe retract height",
    description: "Safe Z retract height above work origin.",
    group      : "preferences",
    type       : "spatial",
    value      : spatial(12.7, MM),
    scope      : "post"
  },
  useM05ForSpindleStop: {
    title      : "Use M05 for spindle stop",
    description: "Use M05 for spindle stop. If false, uses M03 S0 instead (for firmware that rejects M05).",
    group      : "preferences",
    type       : "boolean",
    value      : true,
    scope      : "post"
  },
  splitFile: {
    title      : "Split file by tool",
    description: "Create separate NC files for each tool. Useful since SAB N.3 tool changes are manual.",
    group      : "preferences",
    type       : "boolean",
    value      : false,
    scope      : "post"
  },
  allow3AxisMovement: {
    title      : "Allow full 3-axis movement",
    description: "Allow simultaneous XYZ moves instead of splitting into separate XY and Z moves. " +
      "Default is off (2.5-axis mode). Enable only if your controller and toolpaths support true 3-axis interpolation.",
    group      : "preferences",
    type       : "boolean",
    value      : false,
    scope      : "post"
  },
  useG01ForRapids: {
    title      : "Use G01 for rapids",
    description: "Replace all G00 rapid moves with G01 linear moves at the configured max feedrate. " +
      "This lets you control the maximum traverse speed from the post dialog instead of using the machine's full rapid rate.",
    group      : "preferences",
    type       : "boolean",
    value      : false,
    scope      : "post"
  }
};

// --- Format Definitions ---

var gFormat = createFormat({prefix:"G", decimals:0, width:2, zeropad:true});
var mFormat = createFormat({prefix:"M", decimals:0, width:2, zeropad:true});
var nFormat = createFormat({prefix:"N", decimals:0});
var toolFormat = createFormat({decimals:0});

// Coordinate format: 4 decimal places for inches (0.0001" = 0.00254mm resolution)
var xyzFormat = createFormat({decimals:4, forceDecimal:true});
var feedFormat = createFormat({decimals:1, forceDecimal:true});
var ijkFormat = createFormat({decimals:4, forceDecimal:true});
var secFormat = createFormat({decimals:3, forceDecimal:true});
var rpmFormat = createFormat({decimals:0});
var mmFormat = createFormat({decimals:2, forceDecimal:true}); // for displaying tool dimensions in mm

// Output variables - using createOutputVariable (requires minimumRevision 45917)
var xOutput = createOutputVariable({prefix:"X"}, xyzFormat);
var yOutput = createOutputVariable({prefix:"Y"}, xyzFormat);
var zOutput = createOutputVariable({prefix:"Z"}, xyzFormat);
var iOutput = createOutputVariable({prefix:"I", control:CONTROL_FORCE}, ijkFormat);
var jOutput = createOutputVariable({prefix:"J", control:CONTROL_FORCE}, ijkFormat);
var feedOutput = createOutputVariable({prefix:"F"}, feedFormat);
var sOutput = createOutputVariable({prefix:"S", control:CONTROL_FORCE}, rpmFormat);

// Modal groups
var gMotionModal = createOutputVariable({}, gFormat);
var gUnitModal = createOutputVariable({}, gFormat);
var gAbsIncModal = createOutputVariable({}, gFormat);

// --- Machine Configuration ---

var receivedMachineConfiguration;

function defineMachine() {
  // No rotary axes - pure 3-axis (used as 2.5D)
  if (!receivedMachineConfiguration) {
    machineConfiguration.setHomePositionX(toPreciseUnit(0, IN));
    machineConfiguration.setHomePositionY(toPreciseUnit(0, IN));
    machineConfiguration.setRetractPlane(toPreciseUnit(0.5, IN));
  }
}

function activateMachine() {
  if (!machineConfiguration.isMultiAxisConfiguration()) {
    return; // 3-axis, nothing to configure
  }
}

// --- Line Numbering ---

var sequenceNumber;

function formatSequenceNumber() {
  var n = nFormat.format(sequenceNumber);
  sequenceNumber += getProperty("lineNumberIncrement");
  return n;
}

/** Writes the specified block, with optional N-word line number. */
function writeBlock() {
  var text = "";
  for (var i = 0; i < arguments.length; ++i) {
    if (arguments[i]) {
      if (text) {
        text += " ";
      }
      text += arguments[i];
    }
  }
  if (!text) {
    return;
  }
  if (getProperty("useLineNumbers")) {
    writeln(formatSequenceNumber() + " " + text);
  } else {
    writeln(text);
  }
}

// --- Comment Handling ---

function writeComment(text) {
  if (!getProperty("showComments")) {
    return;
  }
  // Strip parentheses from comment text, truncate, uppercase
  text = String(text).replace(/[()]/g, "");
  if (text.length > 70) {
    text = text.substring(0, 70);
  }
  if (text) {
    writeBlock("(" + text.toUpperCase() + ")");
  }
}

function onComment(text) {
  writeComment(text);
}

// --- Helper Functions ---

/** Force output of X, Y, and Z on next line. */
function forceXYZ() {
  xOutput.reset();
  yOutput.reset();
  zOutput.reset();
}

/** Force output of all modal/coordinate values. */
function forceAny() {
  forceXYZ();
  feedOutput.reset();
  gMotionModal.reset();
}

/** Clamp feed rate to the configured maximum. */
function clampFeed(feed) {
  var maxFeed = getProperty("maxFeedrate") / 25.4; // convert mm/min to ipm
  return Math.min(feed, maxFeed);
}

/** Write a rapid move block. Uses G01 at max feedrate when useG01ForRapids is enabled. */
function writeRapidBlock() {
  var args = Array.prototype.slice.call(arguments);
  if (getProperty("useG01ForRapids")) {
    var rapidFeed = clampFeed(1e10);
    writeBlock.apply(null, [gMotionModal.format(1)].concat(args).concat([feedOutput.format(rapidFeed)]));
  } else {
    writeBlock.apply(null, [gMotionModal.format(0)].concat(args));
  }
}

/** Stop the spindle using the configured method. */
function writeSpindleStop() {
  if (getProperty("useM05ForSpindleStop")) {
    writeBlock(mFormat.format(5));
  } else {
    writeBlock(mFormat.format(3), sOutput.format(0));
  }
}

// --- Split File Support ---

var subprograms = [];

// --- Main Callbacks ---

function onOpen() {
  // Enable helical moves if full 3-axis mode is selected
  if (getProperty("allow3AxisMovement")) {
    allowHelicalMoves = true;
  }

  // Machine configuration
  receivedMachineConfiguration = machineConfiguration.isReceived();
  if (typeof defineMachine == "function") {
    defineMachine();
  }
  activateMachine();

  // Force inch output regardless of what Fusion sends
  unit = IN;

  sequenceNumber = getProperty("lineNumberStart");

  // Program start delimiter (required by SAB N.3)
  writeln("%");

  if (programName) {
    writeComment("PROGRAM: " + programName);
  }
  if (programComment) {
    writeComment(programComment);
  }

  // Write tool list in header
  if (getProperty("showToolInfo") && getProperty("showComments")) {
    var tools = getToolTable();
    if (tools.getNumberOfTools() > 0) {
      writeComment("TOOLS:");
      for (var i = 0; i < tools.getNumberOfTools(); ++i) {
        var t = tools.getTool(i);
        var comment = "T" + toolFormat.format(t.number) + " " +
          "D=" + mmFormat.format(t.diameter * 25.4) + "MM " +
          getToolTypeName(t.type);
        writeComment(comment);
      }
    }
  }

  if (getProperty("splitFile")) {
    writeComment("***THIS FILE DOES NOT CONTAIN NC CODE***");
    writeComment("SEPARATE FILES CREATED FOR EACH TOOL");
    return;
  }

  // Modal setup: inch mode, absolute positioning
  writeBlock(gUnitModal.format(20), gAbsIncModal.format(90));
}

function onSection() {
  // Verify tool orientation is Z-down only (no 3+2 or 5-axis)
  var remaining = currentSection.workPlane;
  if (!isSameDirection(remaining.forward, new Vector(0, 0, 1))) {
    error(localize("Tool orientation is not supported. The Sabre 408 is 2.5-axis only."));
    return;
  }
  setRotation(remaining);

  var insertToolCall = !isFirstSection() &&
    (tool.number != getPreviousSection().getTool().number);

  // Handle split file mode
  if (getProperty("splitFile") && insertToolCall) {
    if (!isFirstSection()) {
      // Close previous split file
      writeRapidBlock(zOutput.format(toPreciseUnit(getProperty("safeRetractHeight"), MM)));
      writeSpindleStop();
      writeRapidBlock(xOutput.format(0), yOutput.format(0));
      writeln("%");
      closeRedirection();
    }

    // Open new file for this tool
    var subprogram = programName + "_T" + tool.number;
    subprograms.push(subprogram);
    var path = FileSystem.getCombinedPath(
      FileSystem.getFolderPath(getOutputPath()),
      String(subprogram).replace(/[<>:"/\\|?*]/g, "") + "." + extension
    );
    writeComment("Load tool " + tool.number + " and run " + subprogram);
    redirectToFile(path);

    writeln("%");
    if (programName) {
      writeComment("PROGRAM: " + programName);
    }
    writeBlock(gUnitModal.format(20), gAbsIncModal.format(90));
  }

  // Operation comment
  if (getProperty("showOperationComments") && hasParameter("operation-comment")) {
    writeComment(getParameter("operation-comment"));
  }

  // Tool change
  if (insertToolCall) {
    writeBlock(mFormat.format(6), "T" + toolFormat.format(tool.number));
    if (tool.comment) {
      writeComment(tool.comment);
    }
  }

  // Spindle on
  writeBlock(mFormat.format(3), sOutput.format(spindleSpeed));

  // Move to initial position
  var initialPosition = getFramePosition(currentSection.getInitialPosition());

  if (getProperty("allow3AxisMovement")) {
    // Full 3-axis: retract then move to initial position in one rapid
    writeRapidBlock(zOutput.format(toPreciseUnit(getProperty("safeRetractHeight"), MM)));
    forceXYZ();
    writeRapidBlock(
      xOutput.format(initialPosition.x),
      yOutput.format(initialPosition.y),
      zOutput.format(initialPosition.z)
    );
  } else {
    // 2.5D: Z first if retracting, then XY, then Z approach
    writeRapidBlock(zOutput.format(toPreciseUnit(getProperty("safeRetractHeight"), MM)));

    forceXYZ();
    writeRapidBlock(
      xOutput.format(initialPosition.x),
      yOutput.format(initialPosition.y)
    );

    writeRapidBlock(zOutput.format(initialPosition.z));
  }
}

function onDwell(seconds) {
  // SAB N.3 G04 dwell is UNCONFIRMED - output as comment
  writeComment("DWELL " + secFormat.format(seconds) + "S - G04 UNCONFIRMED ON SAB N.3");
}

function onSpindleSpeed(spindleSpeed) {
  writeBlock(sOutput.format(spindleSpeed));
}

function onRapid(_x, _y, _z) {
  var x = _x;
  var y = _y;
  var z = _z;

  if (getProperty("allow3AxisMovement")) {
    // Full 3-axis: output XYZ together
    var xStr = xOutput.format(x);
    var yStr = yOutput.format(y);
    var zStr = zOutput.format(z);
    if (xStr || yStr || zStr) {
      writeRapidBlock(xStr, yStr, zStr);
    }
    return;
  }

  // ENFORCE 2.5D: Split into separate Z and XY moves
  var current = getCurrentPosition();
  var zChanging = (Math.abs(z - current.z) > 0.0001);
  var xyChanging = (Math.abs(x - current.x) > 0.0001) || (Math.abs(y - current.y) > 0.0001);

  if (zChanging && xyChanging) {
    if (z > current.z) {
      // Retract Z first, then move XY
      writeRapidBlock(zOutput.format(z));
      writeRapidBlock(xOutput.format(x), yOutput.format(y));
    } else {
      // Move XY first, then plunge Z
      writeRapidBlock(xOutput.format(x), yOutput.format(y));
      writeRapidBlock(zOutput.format(z));
    }
  } else {
    // Only Z or only XY is changing, output normally
    var xStr = xOutput.format(x);
    var yStr = yOutput.format(y);
    var zStr = zOutput.format(z);
    if (xStr || yStr || zStr) {
      writeRapidBlock(xStr, yStr, zStr);
    }
  }
}

function onLinear(_x, _y, _z, feed) {
  if (radiusCompensation != RADIUS_COMPENSATION_OFF) {
    error("Cutter radius compensation (G41/G42) is not supported on the Gerber Sabre 408.");
    return;
  }

  var x = _x;
  var y = _y;
  var z = _z;
  feed = clampFeed(feed);

  if (getProperty("allow3AxisMovement")) {
    // Full 3-axis: output XYZ together
    var xStr = xOutput.format(x);
    var yStr = yOutput.format(y);
    var zStr = zOutput.format(z);
    var fStr = feedOutput.format(feed);
    if (xStr || yStr || zStr) {
      writeBlock(gMotionModal.format(1), xStr, yStr, zStr, fStr);
    } else if (fStr) {
      if (getNextRecord().isMotion()) {
        feedOutput.reset();
      } else {
        writeBlock(gMotionModal.format(1), fStr);
      }
    }
    return;
  }

  // ENFORCE 2.5D: Split simultaneous XY+Z cutting moves
  var current = getCurrentPosition();
  var zChanging = (Math.abs(z - current.z) > 0.0001);
  var xyChanging = (Math.abs(x - current.x) > 0.0001) || (Math.abs(y - current.y) > 0.0001);

  if (zChanging && xyChanging) {
    // Split: Z plunge first at feed, then XY cut
    writeBlock(gMotionModal.format(1), zOutput.format(z), feedOutput.format(feed));
    writeBlock(gMotionModal.format(1),
      xOutput.format(x), yOutput.format(y), feedOutput.format(feed));
  } else {
    var xStr = xOutput.format(x);
    var yStr = yOutput.format(y);
    var zStr = zOutput.format(z);
    var fStr = feedOutput.format(feed);
    if (xStr || yStr || zStr) {
      writeBlock(gMotionModal.format(1), xStr, yStr, zStr, fStr);
    } else if (fStr) {
      if (getNextRecord().isMotion()) {
        feedOutput.reset(); // force feed on next line
      } else {
        writeBlock(gMotionModal.format(1), fStr);
      }
    }
  }
}

function onCircular(clockwise, cx, cy, cz, x, y, z, feed) {
  // If user wants all arcs linearized, do it
  if (getProperty("linearizeArcs")) {
    linearize(tolerance);
    return;
  }

  // SAFETY: Reject any arc that has Z movement (helical) unless 3-axis mode
  if (isHelical() && !getProperty("allow3AxisMovement")) {
    linearize(tolerance);
    return;
  }

  // Only XY plane arcs are allowed
  if (getCircularPlane() != PLANE_XY) {
    linearize(tolerance);
    return;
  }

  feed = clampFeed(feed);
  var start = getCurrentPosition();

  if (isFullCircle()) {
    // Full circles are risky on basic controllers - linearize for safety
    linearize(tolerance);
    return;
  } else {
    // Partial arc
    xOutput.reset();
    yOutput.reset();
    iOutput.reset();
    jOutput.reset();
    if (isHelical()) {
      zOutput.reset();
    }
    writeBlock(
      gMotionModal.format(clockwise ? 2 : 3),
      xOutput.format(x),
      yOutput.format(y),
      isHelical() ? zOutput.format(z) : "",
      iOutput.format(cx - start.x),
      jOutput.format(cy - start.y),
      feedOutput.format(feed)
    );
  }
}

function onMovement(movement) {
  // Force coordinate output after linking moves to ensure correct position tracking
  switch (movement) {
  case MOVEMENT_LEAD_IN:
  case MOVEMENT_LEAD_OUT:
  case MOVEMENT_LINK_TRANSITION:
  case MOVEMENT_LINK_DIRECT:
  case MOVEMENT_RAPID:
    forceXYZ();
    break;
  }
}

// --- Expanded Drilling Cycles ---
// The SAB N.3 does NOT support canned drilling cycles (G81-G89).
// All drilling is expanded to explicit G00/G01 moves with strict 2.5D sequencing.

function onCycle() {
  // Reject tapping cycles entirely
  if (cycleType == "tapping" || cycleType == "right-tapping" || cycleType == "left-tapping") {
    error("Tapping cycles are not supported on the Gerber Sabre 408. " +
      "The SAB N.3 controller cannot synchronize spindle reversal for tapping.");
    return;
  }
}

function onCyclePoint(x, y, z) {
  // All values are already in inches because unit = IN

  // STEP 1: Rapid to clearance height (Z alone, 2.5D)
  writeRapidBlock(zOutput.format(cycle.clearance));

  // STEP 2: Rapid to hole XY position (XY alone, 2.5D)
  writeRapidBlock(xOutput.format(x), yOutput.format(y));

  // STEP 3: Rapid down to retract plane (Z alone)
  writeRapidBlock(zOutput.format(cycle.retract));

  // STEP 4: Execute the appropriate drilling motion
  var drillingFeed = clampFeed(cycle.feedrate);

  switch (cycleType) {

  case "drilling": // G81 equivalent: simple drill to depth
    writeBlock(gMotionModal.format(1), zOutput.format(z), feedOutput.format(drillingFeed));
    writeRapidBlock(zOutput.format(cycle.retract));
    break;

  case "counter-boring": // G82 equivalent: drill to depth + dwell
    writeBlock(gMotionModal.format(1), zOutput.format(z), feedOutput.format(drillingFeed));
    if (cycle.dwell > 0) {
      writeComment("DWELL " + secFormat.format(cycle.dwell) + "S");
    }
    writeRapidBlock(zOutput.format(cycle.retract));
    break;

  case "chip-breaking": // G73 equivalent: peck with partial retract
    var bottomZ = z;
    var currentZ = cycle.stock;
    var peck = cycle.incrementalDepth;
    while (currentZ > (bottomZ + 0.0001)) {
      currentZ -= peck;
      if (currentZ < bottomZ) {
        currentZ = bottomZ;
      }
      writeBlock(gMotionModal.format(1), zOutput.format(currentZ), feedOutput.format(drillingFeed));
      // Partial retract for chip break (~1mm / 0.039")
      var chipBreakRetract = currentZ + toPreciseUnit(1.0, MM);
      writeRapidBlock(zOutput.format(chipBreakRetract));
    }
    writeRapidBlock(zOutput.format(cycle.retract));
    break;

  case "deep-drilling": // G83 equivalent: full-retract peck drilling
    var bottomZ = z;
    var currentZ = cycle.stock;
    var peck = cycle.incrementalDepth;
    while (currentZ > (bottomZ + 0.0001)) {
      currentZ -= peck;
      if (currentZ < bottomZ) {
        currentZ = bottomZ;
      }
      writeBlock(gMotionModal.format(1), zOutput.format(currentZ), feedOutput.format(drillingFeed));
      // Full retract to retract plane
      writeRapidBlock(zOutput.format(cycle.retract));
      // Rapid back down to just above previous depth if not done
      if (currentZ > (bottomZ + 0.0001)) {
        writeRapidBlock(zOutput.format(currentZ + toPreciseUnit(0.5, MM)));
      }
    }
    writeRapidBlock(zOutput.format(cycle.retract));
    break;

  case "boring": // G85 equivalent: plunge + feed retract (not rapid)
  case "reaming":
    writeBlock(gMotionModal.format(1), zOutput.format(z), feedOutput.format(drillingFeed));
    writeBlock(gMotionModal.format(1), zOutput.format(cycle.retract), feedOutput.format(drillingFeed));
    break;

  default:
    // Expand unrecognized cycles as simple drill
    writeComment("WARNING: CYCLE " + cycleType + " EXPANDED AS SIMPLE DRILL");
    writeBlock(gMotionModal.format(1), zOutput.format(z), feedOutput.format(drillingFeed));
    writeRapidBlock(zOutput.format(cycle.retract));
    break;
  }
}

function onCycleEnd() {
  // Retract to clearance after all holes in this cycle are done
  writeRapidBlock(zOutput.format(cycle.clearance));
}

function onSectionEnd() {
  forceAny();
}

function onClose() {
  // Retract Z to safe height
  writeRapidBlock(zOutput.format(toPreciseUnit(getProperty("safeRetractHeight"), MM)));

  // Spindle off
  writeSpindleStop();

  // Return to origin
  forceXYZ();
  writeRapidBlock(xOutput.format(0), yOutput.format(0));

  // Program end delimiter
  writeln("%");

  if (getProperty("splitFile") && isRedirecting()) {
    closeRedirection();
  }
}

// --- Unsupported Feature Handlers ---

function onCommand(command) {
  switch (command) {
  case COMMAND_STOP_SPINDLE:
    writeSpindleStop();
    return;
  case COMMAND_START_SPINDLE:
    writeBlock(mFormat.format(3), sOutput.format(spindleSpeed));
    return;
  case COMMAND_COOLANT_OFF:
  case COMMAND_COOLANT_ON:
    // SAB N.3 has no coolant system - suppress silently
    return;
  case COMMAND_STOP:
    writeBlock(mFormat.format(0));
    return;
  case COMMAND_OPTIONAL_STOP:
    writeBlock(mFormat.format(1));
    return;
  case COMMAND_LOAD_TOOL:
    // Tool change already handled in onSection - suppress duplicate M06
    return;
  }
}

function onPassThrough(text) {
  writeln(text);
}

function setCoolant(coolant) {
  // SAB N.3 has no coolant system. Suppress all coolant commands.
  return;
}
