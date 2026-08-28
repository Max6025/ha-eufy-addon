#!/usr/bin/env node
/**
 * Nachruesten und Korrigieren von Eufy-Geraetelogik in
 * eufy-security-client.
 *
 * Drei Baustellen:
 *
 * 1. Unbekannte Modelle. Die Bibliothek fuehrt feste Tabellen, welcher
 *    Geraetetyp welche Befehle und Eigenschaften hat. Fehlt ein Typ,
 *    lehnt sie jeden Befehl mit NotSupportedError ab.
 *
 * 2. Geraeteklasse. Nur bestimmte Klassen verarbeiten die Push-Ereignisse
 *    3101 (Bewegung), 3102 (Person), 3106 (Tier) und 3107 (Fahrzeug).
 *    Ein unbekannter Typ landet in der einfachen Camera-Klasse, die
 *    diese Ereignisse ignoriert.
 *
 * 3. Guard Mode. Station.setGuardMode() kennt zwei Befehlsformate:
 *    das aktuelle (CMD_SET_PAYLOAD) und ein altes (CMD_SET_ARMING mit
 *    Integer). Welches genommen wird, entscheidet unter anderem ein
 *    Vergleich der Firmware-Version gegen 2.0.7.9. Diese Schwelle passt
 *    nur fuer aeltere Modellreihen - neuere Kameras zaehlen ihre
 *    Firmware wieder ab 1.x, fallen deshalb faelschlich in den alten
 *    Zweig und ignorieren den Befehl stillschweigend. Der Ausweg:
 *    Die Seriennummer in isSoloCameraBySn aufnehmen. Diese Funktion
 *    wird in der ganzen Bibliothek NUR an dieser einen Stelle benutzt,
 *    ist also ein sicherer Schalter fuer das moderne Befehlsformat.
 *
 * Laeuft beim Bauen des Images, direkt nach npm install.
 */

const fs = require("fs");
const path = require("path");

// ---------------------------------------------------------------------
// Was gepatcht wird
// ---------------------------------------------------------------------

// Neue Modelle: Typnummer -> Vorlage und Anzeigename
const MODELLE = [
  {
    typ: 10037,
    name: "CAMERA_C37",
    anzeige: "eufyCam C37 (T814X)",
    // eufyCam C35 - gleiche Familie, Akku plus Solar.
    vorlage: 10035,
    // isSoloCameras  -> Geraeteklasse SoloCamera (Personenerkennung)
    // isCameraC35    -> Eigenschaftsauswertung der Familie
    // isOutdoorPanAndTiltCamera -> Befehlsformat fuer Schwenkkameras,
    //                   noetig fuer Licht und Schwenken
    pruefungen: [
      "isCamera",
      "isSoloCameras",
      "isCameraC35",
      "isOutdoorPanAndTiltCamera",
    ],
  },
];

// Seriennummern-Praefixe, die das aktuelle Guard-Mode-Befehlsformat
// benutzen sollen. Alles, was hier steht, schaltet zuverlaessig um.
const GUARD_MODE_PRAEFIXE = [
  "T814X", // eufyCam C37
  "T8423", // Floodlight Cam 2 Pro
  "T8417", // Indoor Cam
  "T8170", // SoloCam S340
];

const BASIS = process.argv[2] || "/opt/eufy/node_modules/eufy-security-client";
const TYPES = path.join(BASIS, "build/http/types.js");
const DEVICE = path.join(BASIS, "build/http/device.js");

const MARKER = "// ---- eufy_max_patch v4 ----";

function pruefen(datei) {
  if (!fs.existsSync(datei)) {
    console.error(`FEHLER: ${datei} nicht gefunden`);
    process.exit(1);
  }
  if (fs.readFileSync(datei, "utf8").includes(MARKER)) {
    console.log(`${path.basename(datei)}: Patch bereits vorhanden`);
    return false;
  }
  return true;
}

// ---------------------------------------------------------------------
// 1. types.js - Enum, Modellname und die vier Tabellen
// ---------------------------------------------------------------------

if (pruefen(TYPES)) {
  const liste = JSON.stringify(MODELLE);

  const code = `
${MARKER}
// Nachgeruestete Kameramodelle. Siehe patch-devices.js im Add-on-Repo.
(function () {
  const modelle = ${liste};

  for (const m of modelle) {
    if (exports.DeviceType[m.typ] !== undefined) {
      console.log("[eufy_max_patch] Typ " + m.typ + " ist bereits bekannt");
      continue;
    }

    exports.DeviceType[exports.DeviceType[m.name] = m.typ] = m.name;

    const tabellen = [
      ["DeviceProperties", exports.DeviceProperties],
      ["StationProperties", exports.StationProperties],
      ["DeviceCommands", exports.DeviceCommands],
      ["StationCommands", exports.StationCommands],
    ];

    for (const [bezeichnung, tabelle] of tabellen) {
      if (!tabelle) continue;
      const vorlage = tabelle[m.vorlage];
      if (vorlage === undefined) {
        console.log(
          "[eufy_max_patch] " + bezeichnung + ": keine Vorlage " + m.vorlage
        );
        continue;
      }
      tabelle[m.typ] = Array.isArray(vorlage)
        ? vorlage.slice()
        : Object.assign({}, vorlage);
    }

    console.log(
      "[eufy_max_patch] Typ " + m.typ + " (" + m.anzeige +
      ") nach Vorlage " + m.vorlage + " ergaenzt"
    );
  }
})();
`;

  fs.appendFileSync(TYPES, code);
  console.log("types.js gepatcht");
}

// ---------------------------------------------------------------------
// 2. device.js - Typpruefungen und Guard-Mode-Format
// ---------------------------------------------------------------------

if (pruefen(DEVICE)) {
  const liste = JSON.stringify(
    MODELLE.map((m) => ({ typ: m.typ, pruefungen: m.pruefungen || ["isCamera"] }))
  );
  const praefixe = JSON.stringify(GUARD_MODE_PRAEFIXE);

  const code = `
${MARKER}
// Nachgeruestete Kameramodelle in den Typpruefungen bekannt machen.
(function () {
  const modelle = ${liste};
  const praefixe = ${praefixe};
  const D = exports.Device;
  if (!D) return;

  for (const m of modelle) {
    const uebernommen = [];

    for (const name of m.pruefungen) {
      if (typeof D[name] !== "function") {
        console.log("[eufy_max_patch] Pruefung " + name + " gibt es nicht");
        continue;
      }

      const original = D[name].bind(D);
      D[name] = function (type) {
        return type === m.typ || original(type);
      };
      uebernommen.push(name);
    }

    console.log(
      "[eufy_max_patch] Typ " + m.typ + " gilt jetzt fuer: " +
      uebernommen.join(", ")
    );
  }

  // Guard Mode: aktuelles Befehlsformat erzwingen.
  // isSoloCameraBySn wird in der Bibliothek ausschliesslich in
  // Station.setGuardMode() ausgewertet und entscheidet dort zwischen
  // CMD_SET_PAYLOAD (aktuell) und CMD_SET_ARMING (alt). Die sonst
  // ebenfalls geprueften Firmware-Versionen passen bei neueren
  // Kameras nicht mehr, weil deren Zaehlung wieder bei 1.x beginnt.
  if (typeof D.isSoloCameraBySn === "function") {
    const originalSn = D.isSoloCameraBySn.bind(D);
    D.isSoloCameraBySn = function (sn) {
      if (typeof sn === "string") {
        for (const p of praefixe) {
          if (sn.startsWith(p)) return true;
        }
      }
      return originalSn(sn);
    };
    console.log(
      "[eufy_max_patch] Guard Mode nutzt aktuelles Format fuer: " +
      praefixe.join(", ")
    );
  } else {
    console.log("[eufy_max_patch] isSoloCameraBySn gibt es nicht");
  }
})();
`;

  fs.appendFileSync(DEVICE, code);
  console.log("device.js gepatcht");
}

console.log("Patch abgeschlossen");
