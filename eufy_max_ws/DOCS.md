# Eufy Max WS

WebSocket-Server für Eufy-Kameras. Gehört zur Integration **Eufy Max** und
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
| `p2p_connection_setup` | Wie sich der Server mit den Kameras verbindet: `0` nur lokal, `1` nur Cloud-Relay, `2` bevorzugt lokal (Empfehlung). Bei `0` funktionieren nur Kameras im selben Netz. |
| `station_ip_addresses` | Feste IP je Station, Format `SERIENNUMMER:IP`. Verhindert, dass sich Kameras über Eufys langsames Cloud-Relay verbinden. Beispiel: `T8170T10250310E0:192.168.3.188` |
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
