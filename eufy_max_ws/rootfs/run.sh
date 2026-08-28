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
# Bibliothek patchen - BEIM START, nicht beim Bauen
# ---------------------------------------------------------------------
#
# Frueher lief der Patch im Dockerfile. Das ist unzuverlaessig, weil
# Docker Schichten zwischenspeichert: Aendert sich das Patch-Skript,
# baut der Supervisor das Image trotzdem nicht immer neu, und es laeuft
# stillschweigend eine veraltete Fassung weiter.
#
# Beim Start ausgefuehrt gibt es dieses Problem nicht. Der Container
# wird bei jedem Start aus dem Image neu erzeugt, der Patch also frisch
# angewandt. Ein Marker in den Dateien verhindert doppeltes Anwenden,
# falls das Image schon gepatcht ist.

cat > /tmp/eufy_patch.js <<'PATCH_EOF'
const fs = require("fs");
const path = require("path");

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

const GUARD_MODE_PRAEFIXE = ["T814X", "T8423", "T8417", "T8170"];

const BASIS = process.argv[2] || "/opt/eufy/node_modules/eufy-security-client";
const TYPES = path.join(BASIS, "build/http/types.js");
const DEVICE = path.join(BASIS, "build/http/device.js");
const API = path.join(BASIS, "build/http/api.js");

const MARKER = "// ---- eufy_max_patch v5 ----";

function pruefen(datei) {
  if (!fs.existsSync(datei)) {
    console.log("[eufy_max_patch] FEHLT: " + datei);
    return false;
  }
  if (fs.readFileSync(datei, "utf8").includes(MARKER)) {
    console.log("[eufy_max_patch] " + path.basename(datei) + ": bereits gepatcht");
    return false;
  }
  return true;
}

if (pruefen(TYPES)) {
  const liste = JSON.stringify(MODELLE);
  fs.appendFileSync(TYPES, `
${MARKER}
(function () {
  const modelle = ${liste};
  for (const m of modelle) {
    if (exports.DeviceType[m.typ] !== undefined) {
      console.log("[eufy_max_patch] Typ " + m.typ + " ist bereits bekannt");
      continue;
    }
    exports.DeviceType[m.name] = m.typ;
    exports.DeviceType[m.typ] = m.name;
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
        console.log("[eufy_max_patch] " + bezeichnung + ": keine Vorlage " + m.vorlage);
        continue;
      }
      tabelle[m.typ] = Array.isArray(vorlage) ? vorlage.slice() : Object.assign({}, vorlage);
    }
    console.log("[eufy_max_patch] Typ " + m.typ + " (" + m.anzeige + ") nach Vorlage " + m.vorlage + " ergaenzt");
  }
})();
`);
  console.log("[eufy_max_patch] types.js gepatcht");
}

if (pruefen(DEVICE)) {
  const liste = JSON.stringify(
    MODELLE.map((m) => ({ typ: m.typ, pruefungen: m.pruefungen }))
  );
  const praefixe = JSON.stringify(GUARD_MODE_PRAEFIXE);
  fs.appendFileSync(DEVICE, `
${MARKER}
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
      D[name] = function (type) { return type === m.typ || original(type); };
      uebernommen.push(name);
    }
    console.log("[eufy_max_patch] Typ " + m.typ + " gilt jetzt fuer: " + uebernommen.join(", "));
  }
  if (typeof D.isSoloCameraBySn === "function") {
    const originalSn = D.isSoloCameraBySn.bind(D);
    D.isSoloCameraBySn = function (sn) {
      if (typeof sn === "string") {
        for (const p of praefixe) { if (sn.startsWith(p)) return true; }
      }
      return originalSn(sn);
    };
    console.log("[eufy_max_patch] Guard Mode nutzt aktuelles Format fuer: " + praefixe.join(", "));
  }
})();
`);
  console.log("[eufy_max_patch] device.js gepatcht");
}

// Eufy antwortet auf den bisherigen Endpunkten inzwischen mit code 200
// statt code 0. Die Bibliothek prueft auf 0 und wertet alles andere als
// Fehler - Folge: leere Geraeteliste bei intakter Anmeldung.
if (pruefen(API)) {
  const alt = "result.code == types_1.ResponseErrorCode.CODE_OK";
  const neu = "(result.code == types_1.ResponseErrorCode.CODE_OK || result.code == 200)";
  let inhalt = fs.readFileSync(API, "utf8");
  const treffer = inhalt.split(alt).length - 1;
  if (treffer === 0) {
    console.log("[eufy_max_patch] api.js: Erfolgspruefung nicht gefunden");
  } else {
    inhalt = inhalt.split(alt).join(neu);
    inhalt += "\n" + MARKER + "\n";
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

# Feste IP-Adressen der Stationen. Verhindert, dass sich Kameras ueber
# Eufys Cloud-Relay verbinden statt lokal. Format je Eintrag: SERIENNUMMER:IP
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

# Discovery erst nach dem Start melden, damit die Integration nicht in
# einen noch nicht lauschenden Port rennt.
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
