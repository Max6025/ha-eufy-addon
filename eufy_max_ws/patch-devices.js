#!/usr/bin/env node
/**
 * Nachruesten neuer Eufy-Kameramodelle in eufy-security-client.
 *
 * Hintergrund: Die Bibliothek fuehrt feste Tabellen, welcher Geraetetyp
 * welche Befehle und Eigenschaften hat. Fehlt ein Typ, lehnt sie jeden
 * Befehl mit NotSupportedError ab - selbst wenn die Kamera protokollseitig
 * identisch zu einem bekannten Modell ist.
 *
 * Zweiter, ebenso wichtiger Punkt: Die Bibliothek waehlt anhand des Typs
 * die Geraeteklasse aus. Nur bestimmte Klassen verarbeiten die
 * Push-Ereignisse 3101 (Bewegung), 3102 (Person), 3106 (Tier) und 3107
 * (Fahrzeug). Ein unbekannter Typ landet in der einfachen Camera-Klasse,
 * die diese Ereignisse ignoriert - die Kamera meldet dann nie eine
 * Erkennung, obwohl die Nachricht ankommt.
 *
 * Ebenso haengen Befehle wie das Schalten des Lichts an Typpruefungen:
 * station.switchLight() geht eine lange Fallunterscheidung durch und
 * wirft am Ende NotSupportedError, wenn keine passt.
 *
 * Dieses Skript kopiert die Tabelleneintraege eines bekannten
 * Referenzmodells auf den neuen Typ UND sorgt dafuer, dass der Typ
 * dieselben Pruefungen besteht wie die Vorlage.
 *
 * Es laeuft beim Bauen des Images, direkt nach npm install, und wird bei
 * jedem Neubau frisch angewandt. Angewandt wird nur, was wirklich fehlt -
 * kommt der Eintrag irgendwann von bropat selbst, passiert nichts mehr.
 */

const fs = require("fs");
const path = require("path");

// Neue Modelle: Typnummer -> Vorlage und Anzeigename
const MODELLE = [
  {
    typ: 10037,
    name: "CAMERA_C37",
    anzeige: "eufyCam C37 (T814X)",
    // eufyCam C35 - gleiche Familie, Akku plus Solar.
    // Wichtig: Der C35 gehoert zu isSoloCameras und bekommt damit die
    // SoloCamera-Klasse, die Personenerkennung verarbeitet. Ausserdem
    // gibt es fuer isCameraC35 einen eigenen Lichtbefehl - genau den,
    // den Kameras ohne HomeBase brauchen.
    vorlage: 10035,
    pruefungen: ["isCamera", "isSoloCameras", "isCameraC35"],
  },
];

const BASIS = process.argv[2] || "/opt/eufy/node_modules/eufy-security-client";
const TYPES = path.join(BASIS, "build/http/types.js");
const DEVICE = path.join(BASIS, "build/http/device.js");

const MARKER = "// ---- eufy_max_patch v2 ----";

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
// 2. device.js - Typpruefungen erweitern
// ---------------------------------------------------------------------
//
// Entscheidend ist isSoloCameras: eufysecurity.js waehlt darueber die
// SoloCamera-Klasse aus, und nur die verarbeitet die Push-Ereignisse
// 3101/3102/3106/3107. Ohne diese Zeile bleibt personDetected fuer immer
// auf false, egal was Eufy schickt.
//
// isCameraC35 wiederum schaltet in station.switchLight() den Zweig frei,
// der fuer Kameras ohne HomeBase gedacht ist.

if (pruefen(DEVICE)) {
  const liste = JSON.stringify(
    MODELLE.map((m) => ({ typ: m.typ, pruefungen: m.pruefungen || ["isCamera"] }))
  );

  const code = `
${MARKER}
// Nachgeruestete Kameramodelle in den Typpruefungen bekannt machen.
(function () {
  const modelle = ${liste};
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
})();
`;

  fs.appendFileSync(DEVICE, code);
  console.log("device.js gepatcht");
}

console.log("Patch abgeschlossen");
