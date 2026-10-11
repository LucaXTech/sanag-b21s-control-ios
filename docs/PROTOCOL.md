# Sanag B21S · protocollo BLE verificato

Progetto indipendente di interoperabilità, a cura di Luca Serioli.

- Advertising service: `A0FA`
- GATT service: `FAA0`
- Write characteristic: `FAA1`
- Notify characteristic: `FAA2`
- Lettura EQ: `AA 76 01 00 21`
- Imposta indice EQ N in `[0,5]`: `AA 39 01 NN CC`, con `CC = (0xAA + 0x39 + 0x01 + N) & 0xFF`.
- Risposta: `A5 39 01 NN CC`; stato: `A5 76 01 NN CC`.

| N | Nome UI | Nome visualizzato dall'app ufficiale |
|---:|---|---|
| 0 | Stereo+ | SSQVP |
| 1 | Pop | Pop ultrasonico |
| 2 | Rock | Rock festoso |
| 3 | Classica | Classica ricerca suoni |
| 4 | Voci | Lirica iniziale |
| 5 | Soft | Purezza morbida |

Osservazioni riferite a un modello B21S; altri firmware o modelli non verificati. Nessuna scrittura firmware o comandi di configurazione sconosciuti.


## Batteria B21S — scoperta dalla v0.4.3

- Nell'APK ufficiale Sanag, `BluetoothDeviceViewModel.sendGetBatteryCMD` invia il frame `aa330100` prima del checksum.
- Frame completo con checksum additivo: `AA 33 01 00 DE` sulla caratteristica `FAA1`.
- Notifica ricevuta in precedenza dalle cuffie su `FAA2`: `A5 33 01 4E 27` (0x4E = 78; checksum 0x27 valido).
- Ipotesi ad alta confidenza: `A5 33 01 XX checksum`, con `XX` livello batteria 0...100%.
- **Da validare su hardware** confrontando la lettura BLE con la percentuale visualizzata nel widget Batterie di iOS. Non è letta da un'API privata di iOS.
- La richiesta viene inviata dopo il completamento della connessione GATT; notifiche spontanee successive possono aggiornarne il valore.
