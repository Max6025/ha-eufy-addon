#!/usr/bin/with-contenv bashio
# shellcheck shell=bash
set -e

bashio::log.info "Eufy Max WS wird gestartet"

USERNAME=$(bashio::config 'username')
PASSWORD=$(bashio::config 'password')

if bashio::var.is_empty "${USERNAME}" || bashio::var.is_empty "${PASSWORD}"; then
    bashio::exit.nok "Benutzername und Passwort muessen in der Konfiguration gesetzt sein"
fi

CONFIG_FILE="/data/config.json"
CLIENT_DIR="/opt/eufy/node_modules/eufy-security-client"
PATCH_CONFIG="/tmp/eufy_patch.json"

# ---------------------------------------------------------------------
# Gespeicherte Sitzung verwerfen
# ---------------------------------------------------------------------

if bashio::config.true 'reset_session'; then
    bashio::log.warning "reset_session ist aktiv - gespeicherte Sitzung wird geloescht"
    rm -f /data/persistent.json
    rm -f /data/*.db 2>/dev/null || true
    bashio::log.info "Sitzung geloescht. Bitte reset_session danach wieder ausschalten"
fi

# ---------------------------------------------------------------------
# Einstellungen fuer den Patch
# ---------------------------------------------------------------------
#
# guard_mode_altes_format: Seriennummern, die den Moduswechsel im alten
# Befehlsformat bekommen sollen (CMD_SET_ARMING statt CMD_SET_PAYLOAD).
#
# Welches Format eine Kamera versteht, laesst sich von aussen nicht
# erkennen. Die Bibliothek entscheidet anhand der Firmware-Version -
# eine Annahme, die bei neueren Modellen nicht mehr stimmt. Sogar zwei
# Kameras desselben Modells koennen sich unterschiedlich verhalten. Wer
# eine Kamera hat, die ihren Modus zwar meldet, einen Wechsel aber nicht
# annimmt, traegt ihre Seriennummer hier ein.

LEGACY="[]"
if bashio::config.has_value 'guard_mode_altes_format'; then
    LEGACY=$(bashio::config 'guard_mode_altes_format' \
        | jq -R -s 'split("\n") | map(select(length > 0))')
    bashio::log.info "Altes Guard-Mode-Format fuer: ${LEGACY}"
fi

jq -n --argjson legacy "${LEGACY}" '{legacy: $legacy}' > "${PATCH_CONFIG}"

# ---------------------------------------------------------------------
# Bibliothek patchen - BEIM START, nicht beim Bauen
# ---------------------------------------------------------------------
#
# Frueher lief der Patch im Dockerfile. Das ist unzuverlaessig, weil
# Docker Schichten zwischenspeichert und dann stillschweigend eine alte
# Fassung weiterlaeuft. Beim Start gibt es das Problem nicht.

cat > /tmp/eufy_patch.js <<'PATCH_EOF'
const fs = require("fs");
const path = require("path");

const BASIS = process.argv[2] || "/opt/eufy/node_modules/eufy-security-client";
const TYPES = path.join(BASIS, "build/http/types.js");
const DEVICE = path.join(BASIS, "build/http/device.js");
const API = path.join(BASIS, "build/http/api.js");

const MARKER = "// ---- eufy_max_patch v6 ----";

// Neue Modelle: Typnummer, Vorlage, betroffene Typpruefungen
const MODELLE = [
  {
    typ: 10037,
    name: "CAMERA_C37",
    anzeige: "eufyCam C37 (T814X)",
    vorlage: 10035,
    pruefungen: [
      "isCamera",
      "isSoloCameras",
      "isCameraC35",
      "isOutdoorPanAndTiltCamera",
    ],
  },
];

// Seriennummern-Praefixe, die das aktuelle Guard-Mode-Format bekommen
const PRAEFIXE = ["T814X", "T8423", "T8417", "T8170"];

// Seriennummern, die ausdruecklich das ALTE Format bekommen sollen
let LEGACY = [];
try {
  const cfg = JSON.parse(fs.readFileSync("/tmp/eufy_patch.json", "utf8"));
  LEGACY = Array.isArray(cfg.legacy) ? cfg.legacy : [];
} catch (err) {
  LEGACY = [];
}

function pruefen(datei) {
  if (!fs.existsSync(datei)) {
    console.log("[eufy_max_patch] FEHLT: " + datei);
    return false;
  }
  if (fs.readFileSync(datei, "utf8").indexOf(MARKER) !== -1) {
    console.log("[eufy_max_patch] " + path.basename(datei) + ": bereits gepatcht");
    return false;
  }
  return true;
}

// ---------------------------------------------------------------------
// 1. types.js - Enum und Tabellen
// ---------------------------------------------------------------------

if (pruefen(TYPES)) {
  var codeTypes = "\n" + MARKER + "\n" +
    "(function () {\n" +
    "  var modelle = " + JSON.stringify(MODELLE) + ";\n" +
    "  for (var i = 0; i < modelle.length; i++) {\n" +
    "    var m = modelle[i];\n" +
    "    if (exports.DeviceType[m.typ] !== undefined) {\n" +
    "      console.log('[eufy_max_patch] Typ ' + m.typ + ' ist bereits bekannt');\n" +
    "      continue;\n" +
    "    }\n" +
    "    exports.DeviceType[m.name] = m.typ;\n" +
    "    exports.DeviceType[m.typ] = m.name;\n" +
    "    var tabellen = [\n" +
    "      ['DeviceProperties', exports.DeviceProperties],\n" +
    "      ['StationProperties', exports.StationProperties],\n" +
    "      ['DeviceCommands', exports.DeviceCommands],\n" +
    "      ['StationCommands', exports.StationCommands]\n" +
    "    ];\n" +
    "    for (var t = 0; t < tabellen.length; t++) {\n" +
    "      var bezeichnung = tabellen[t][0];\n" +
    "      var tabelle = tabellen[t][1];\n" +
    "      if (!tabelle) continue;\n" +
    "      var vorlage = tabelle[m.vorlage];\n" +
    "      if (vorlage === undefined) {\n" +
    "        console.log('[eufy_max_patch] ' + bezeichnung + ': keine Vorlage ' + m.vorlage);\n" +
    "        continue;\n" +
    "      }\n" +
    "      tabelle[m.typ] = Array.isArray(vorlage) ? vorlage.slice() : Object.assign({}, vorlage);\n" +
    "    }\n" +
    "    console.log('[eufy_max_patch] Typ ' + m.typ + ' (' + m.anzeige + ') nach Vorlage ' + m.vorlage + ' ergaenzt');\n" +
    "  }\n" +
    "})();\n";

  fs.appendFileSync(TYPES, codeTypes);
  console.log("[eufy_max_patch] types.js gepatcht");
}

// ---------------------------------------------------------------------
// 2. device.js - Typpruefungen und Guard-Mode-Format
// ---------------------------------------------------------------------

if (pruefen(DEVICE)) {
  var kurz = MODELLE.map(function (m) {
    return { typ: m.typ, pruefungen: m.pruefungen };
  });

  var codeDevice = "\n" + MARKER + "\n" +
    "(function () {\n" +
    "  var modelle = " + JSON.stringify(kurz) + ";\n" +
    "  var praefixe = " + JSON.stringify(PRAEFIXE) + ";\n" +
    "  var legacy = " + JSON.stringify(LEGACY) + ";\n" +
    "  var D = exports.Device;\n" +
    "  if (!D) return;\n" +
    "  for (var i = 0; i < modelle.length; i++) {\n" +
    "    var m = modelle[i];\n" +
    "    var uebernommen = [];\n" +
    "    for (var p = 0; p < m.pruefungen.length; p++) {\n" +
    "      var name = m.pruefungen[p];\n" +
    "      if (typeof D[name] !== 'function') {\n" +
    "        console.log('[eufy_max_patch] Pruefung ' + name + ' gibt es nicht');\n" +
    "        continue;\n" +
    "      }\n" +
    "      (function (name, typ) {\n" +
    "        var original = D[name].bind(D);\n" +
    "        D[name] = function (type) { return type === typ || original(type); };\n" +
    "      })(name, m.typ);\n" +
    "      uebernommen.push(name);\n" +
    "    }\n" +
    "    console.log('[eufy_max_patch] Typ ' + m.typ + ' gilt jetzt fuer: ' + uebernommen.join(', '));\n" +
    "  }\n" +
    "  if (typeof D.isSoloCameraBySn === 'function') {\n" +
    "    var originalSn = D.isSoloCameraBySn.bind(D);\n" +
    "    D.isSoloCameraBySn = function (sn) {\n" +
    "      if (typeof sn === 'string') {\n" +
    "        for (var l = 0; l < legacy.length; l++) {\n" +
    "          if (sn.indexOf(legacy[l]) === 0) return false;\n" +
    "        }\n" +
    "        for (var q = 0; q < praefixe.length; q++) {\n" +
    "          if (sn.indexOf(praefixe[q]) === 0) return true;\n" +
    "        }\n" +
    "      }\n" +
    "      return originalSn(sn);\n" +
    "    };\n" +
    "    console.log('[eufy_max_patch] Guard Mode aktuelles Format fuer: ' + praefixe.join(', '));\n" +
    "    if (legacy.length) {\n" +
    "      console.log('[eufy_max_patch] Guard Mode ALTES Format fuer: ' + legacy.join(', '));\n" +
    "    }\n" +
    "  }\n" +
    "})();\n";

  fs.appendFileSync(DEVICE, codeDevice);
  console.log("[eufy_max_patch] device.js gepatcht");
}

// ---------------------------------------------------------------------
// 3. api.js - Erfolgscode 200 zusaetzlich zu 0 akzeptieren
// ---------------------------------------------------------------------

if (pruefen(API)) {
  var alt = "result.code == types_1.ResponseErrorCode.CODE_OK";
  var neu = "(result.code == types_1.ResponseErrorCode.CODE_OK || result.code == 200)";
  var inhalt = fs.readFileSync(API, "utf8");
  var treffer = inhalt.split(alt).length - 1;

  if (treffer === 0) {
    console.log("[eufy_max_patch] api.js: Erfolgspruefung nicht gefunden");
  } else {
    inhalt = inhalt.split(alt).join(neu) + "\n" + MARKER + "\n";
    fs.writeFileSync(API, inhalt);
    console.log("[eufy_max_patch] api.js: " + treffer + " Erfolgspruefungen akzeptieren jetzt auch code 200");
  }
}
PATCH_EOF

if [ -d "${CLIENT_DIR}" ]; then
    node /tmp/eufy_patch.js "${CLIENT_DIR}" || \
        bashio::log.warning "Patch konnte nicht angewandt werden"
else
    bashio::log.warning "eufy-security-client nicht unter ${CLIENT_DIR} gefunden"
fi

# ---------------------------------------------------------------------
# Konfiguration
# ---------------------------------------------------------------------

STATION_IPS="{}"
if bashio::config.has_value 'station_ip_addresses'; then
    STATION_IPS=$(bashio::config 'station_ip_addresses' \
        | jq -R -s 'split("\n")
                    | map(select(length > 0))
                    | map(split(":"))
                    | map(select(length == 2))
                    | map({(.[0] | ltrimstr(" ") | rtrimstr(" ")):
                           (.[1] | ltrimstr(" ") | rtrimstr(" "))})
                    | add // {}')
    bashio::log.info "Feste Stations-IPs: ${STATION_IPS}"
fi

jq -n \
    --arg username "${USERNAME}" \
    --arg password "${PASSWORD}" \
    --arg country "$(bashio::config 'country')" \
    --arg language "$(bashio::config 'language')" \
    --arg device "$(bashio::config 'trusted_device_name')" \
    --argjson event "$(bashio::config 'event_duration_seconds')" \
    --argjson invitations "$(bashio::config 'accept_invitations')" \
    --argjson polling "$(bashio::config 'polling_interval_minutes')" \
    --argjson p2p "$(bashio::config 'p2p_connection_setup')" \
    --argjson stations "${STATION_IPS}" \
    '{
        username: $username,
        password: $password,
        country: $country,
        language: $language,
        trustedDeviceName: $device,
        eventDurationSeconds: $event,
        acceptInvitations: $invitations,
        pollingIntervalMinutes: $polling,
        p2pConnectionSetup: $p2p,
        stationIPAddresses: $stations,
        persistentDir: "/data"
    }' > "${CONFIG_FILE}"

chmod 600 "${CONFIG_FILE}"
bashio::log.info "Konfiguration geschrieben nach ${CONFIG_FILE}"

SERVER="/opt/eufy/node_modules/eufy-security-ws/dist/bin/server.js"

if [ ! -f "${SERVER}" ]; then
    bashio::log.warning "Server nicht am erwarteten Ort, suche im Dateisystem"
    SERVER=$(find / -path /proc -prune -o -name "server.js" -path "*eufy-security-ws*" -print 2>/dev/null | head -n 1)
fi

if [ -z "${SERVER}" ] || [ ! -f "${SERVER}" ]; then
    bashio::exit.nok "eufy-security-ws wurde im Image nicht gefunden - Add-on neu bauen"
fi

PKG="/opt/eufy/node_modules/eufy-security-ws/package.json"
if [ -f "${PKG}" ]; then
    bashio::log.info "eufy-security-ws $(jq -r '.version' "${PKG}")"
fi
PKG_CLIENT="${CLIENT_DIR}/package.json"
if [ -f "${PKG_CLIENT}" ]; then
    bashio::log.info "eufy-security-client $(jq -r '.version' "${PKG_CLIENT}")"
fi

(
    sleep 12
    DISCOVERY_CONFIG=$(bashio::var.json host "$(hostname)" port "^3000")
    if bashio::discovery "eufy_max" "${DISCOVERY_CONFIG}" > /dev/null; then
        bashio::log.info "Integration ueber Discovery benachrichtigt"
    else
        bashio::log.warning "Discovery fehlgeschlagen - Integration von Hand einrichten"
    fi
) &

bashio::log.info "Starte Server auf 0.0.0.0:3000 (Host: $(hostname))"

ARGS=(--config "${CONFIG_FILE}" --host 0.0.0.0 --port 3000)

if bashio::config.true 'event_log'; then
    bashio::log.info "Ereignisfilter aktiv - es werden nur Erkennungen angezeigt"

    node "${SERVER}" "${ARGS[@]}" --verbose 2>&1 | awk '
        BEGIN { IGNORECASE = 1 }
        /heartbeat|Heartbeat|Sending ping|checkin|Checkin/ { next }
        /detected|Detected|onPerson|onMotion|onPet|onVehicle|onRing/ { print; fflush(); next }
        /person|Person|human|Human|motion|Motion|vehicle|Vehicle/ { print; fflush(); next }
        /rings|ringing|Ringing|package|Package/ { print; fflush(); next }
        /PushMessage|push message|onMessage|CusPush|received message/ { print; fflush(); next }
        /event_type|eventType|alarm|Alarm/ { print; fflush(); next }
    '
    exit 0
fi

if bashio::config.true 'debug'; then
    bashio::log.info "Debug-Modus aktiv - sehr ausfuehrliches Protokoll"
    ARGS+=(--verbose)
fi

exec node "${SERVER}" "${ARGS[@]}"
