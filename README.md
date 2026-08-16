# Eufy Max WS

WebSocket-Server für Eufy-Kameras. Gehört zur Integration [**Eufy Max**](https://github.com/Max6025/eufy_max) und
meldet sich bei ihr automatisch an — im Einrichtungsdialog muss nichts von
Hand eingetragen werden.

## Konfiguration

| Option | Bedeutung |
|---|---|
| `username` | E-Mail des Eufy-Kontos. **Owner-Konto verwenden**, Gastkonten dürfen viele Einstellungen nicht ändern. |
| `password` | Passwort dieses Kontos |
| `country` | Ländercode des Kontos, z. B. `DE` |
| `language` | Sprache, z. B. `de` |
| `trusted_device_name` | Name, unter dem sich der Server bei Eufy anmeldet |
| `event_duration_seconds` | Wie lange ein Bewegungsereignis als aktiv gilt |
| `accept_invitations` | Freigabe-Einladungen automatisch annehmen |
| `polling_interval_minutes` | Abstand der Cloud-Abfragen |
| `debug` | Ausführliches Protokoll bei Problemen |

Der Port ist fest auf **3000** gesetzt und muss nicht angepasst werden.

## Wichtig

Das Konto darf sich **nicht gleichzeitig** in der Eufy-App auf dem Handy
anmelden — Eufy wirft dann die Sitzung des Servers raus. Für das Handy ein
zweites, freigegebenes Konto verwenden.

Bei der ersten Anmeldung verlangt Eufy meist ein Captcha oder einen
2FA-Code. Home Assistant zeigt dann eine Benachrichtigung; die Antwort wird
über `eufy_max.set_captcha` bzw. `eufy_max.set_verify_code` geschickt.

## Protokoll

Bei Problemen `debug` einschalten und den Tab **Protokoll** öffnen.
