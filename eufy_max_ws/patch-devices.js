#!/usr/bin/env node
/**
 * Nachruesten neuer Eufy-Kameramodelle in eufy-security-client.
 *
 * Hintergrund: Die Bibliothek fuehrt feste Tabellen, welcher Geraetetyp
 * welche Befehle und Eigenschaften hat. Fehlt ein Typ, lehnt sie jeden
 * Befehl mit NotSupportedError ab - selbst wenn die Kamera protokollseitig
 * identisch zu einem bekannten Modell ist.
 *
 * Dieses Skript kopiert die Eintraege eines bekannten Referenzmodells auf
 * den neuen Typ. Es laeuft beim Bauen des Images, direkt nach npm install,
 * und wird bei jedem Neubau frisch angewandt.
 *
 * Angewandt wird der Patch nur, wenn der Typ wirklich fehlt - kommt der
 * Eintrag irgendwann von bropat selbst, passiert hier nichts mehr.
 */

const fs = require("fs");
const path = require("path");

// Neue Modelle: Typnummer -> Vorlage und Anzeigename
const MODELLE = [
  {
    typ: 10037,
    name: "CAMERA_C37",
    anzeige: "eufyCam C37 (T814X)",
    // eufyCam C35 - gleiche Familie, Akku plus Solar
    vorlage: 10035,
  },
];

const BASIS = process.argv[2] || "/opt/eufy/node_modules/eufy-security-client";
const TYPES = path.join(BASIS, "build/http/types.js");
const DEVICE = path.join(BASIS, "build/http/device.js");

const MARKER = "// ---- eufy_max_patch ----";

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

    // Enum in beide Richtungen ergaenzen
    exports.DeviceType[exports.DeviceType[m.name] = m.typ] = m.name;

    // Tabellen vom Referenzmodell uebernehmen
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
// 2. device.js - isCamera und Verwandte muessen den Typ kennen
// ---------------------------------------------------------------------

if (pruefen(DEVICE)) {
  const typen = JSON.stringify(MODELLE.map((m) => m.typ));

  const code = `
${MARKER}
// Nachgeruestete Kameramodelle als Kamera erkennen.
(function () {
  const neu = ${typen};
  const D = exports.Device;
  if (!D) return;

  // Diese Pruefungen entscheiden, ob ein Geraet ueberhaupt als Kamera
  // behandelt wird. Ohne sie bleibt das Geraet ein namenloses Objekt.
  for (const name of ["isCamera", "isBatteryDoorbell", "isWiredDoorbell"]) {
    if (typeof D[name] !== "function") continue;
    if (name !== "isCamera") continue;

    const original = D[name].bind(D);
    D[name] = function (type) {
      return neu.includes(type) || original(type);
    };
  }

  console.log("[eufy_max_patch] isCamera kennt jetzt: " + neu.join(", "));
})();
`;

  fs.appendFileSync(DEVICE, code);
  console.log("device.js gepatcht");
}

console.log("Patch abgeschlossen");
