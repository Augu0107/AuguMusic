# AuguMusic

Lettore musicale offline per iPad (e iPhone) in SwiftUI, ispirato a Musicolet. Uso personale, si installa con AltStore.

## Cosa c'è nella v0.1

- **Libreria** da una o più cartelle: "Sull'iPad › AuguMusic", iCloud Drive, chiavetta USB-C, disco esterno o server SMB, scelte con il selettore dell'app File
- Viste **Cartelle, Album, Artisti, Artisti album, Generi, Compositori, Brani**, più una ricerca globale
- Tag letti da MP3, M4A/AAC/ALAC, FLAC (commenti Vorbis e copertina), WAV, AIFF e CAF. Le copertine vengono dai tag oppure da `cover.jpg` / `folder.jpg` nella cartella
- **Code multiple** (fino a 20, il limite si cambia): riprendi, rinomina, salva come playlist, rimuovi, riordina, cerca dentro la coda, "riproduci dopo", "aggiungi alla coda", "aggiungi a nuova coda"
- Ripetizione come Musicolet: ripeti la coda, ripeti il brano, passa alla coda successiva, ferma a fine coda, ferma dopo ogni brano. Modalità casuale per coda, con rimescolamento
- **Equalizzatore** a 10 bande con preset, preset personali, preamplificazione e bass boost
- **Velocità, tono e bilanciamento**, ripetizione **A-B**, **segnalibri con note**
- **Testi sincronizzati** (`.lrc` con lo stesso nome del brano, oppure testo nei tag): righe evidenziate, scorrimento automatico, tocco su una riga per saltarci
- **Timer di spegnimento**: dopo N minuti (con l'opzione di finire il brano), dopo questo brano, dopo N brani
- **Playlist e Preferiti**, esportazione M3U
- Dissolvenza su play/pausa, ReplayGain (brano/album), pausa quando si staccano le cuffie
- Riproduzione in background, controlli in schermata di blocco, Centro di Controllo e AirPods
- Su iPad in orizzontale, la schermata "In riproduzione" mostra coda, testo o segnalibri affiancati
- Temi Automatico, Chiaro, Scuro e Nero AMOLED, con 8 colori d'accento

## Prossime fasi

- Editor dei tag (modifica dei metadati, serve TagLib)
- Riproduzione gapless vera
- Editor dei testi `.lrc`
- Backup e ripristino di code, playlist e impostazioni

## Come ottenere l'.ipa (senza Mac)

1. Crea un repository su GitHub. Pubblico è più comodo: i minuti macOS di GitHub Actions sono gratis senza limiti, mentre su un repo privato ne hai circa 200 al mese.
2. Carica tutti i file di questa cartella, compresa `.github/workflows/build-ipa.yml`.
3. Ogni push avvia la compilazione da solo. In alternativa: scheda **Actions** → **Build IPA** → **Run workflow**.
4. Quando la compilazione finisce (circa 5 minuti), apri il run e scarica l'artifact **AuguMusic-ipa**. Dentro lo zip c'è `AuguMusic.ipa`.
5. Se fallisce, scarica l'artifact **xcodebuild-log** e mandamelo: lo sistemo.

## Installazione con AltStore

1. Copia `AuguMusic.ipa` sull'iPad, per esempio in iCloud Drive.
2. In AltStore vai su **My Apps** → **+** e scegli il file. Oppure, dall'app File, condividi l'.ipa con AltStore.
3. Con un Apple ID gratuito l'app dura 7 giorni. AltStore la rinnova da solo quando AltServer è acceso sul PC nella stessa rete Wi-Fi.

## Mettere la musica

- **Più semplice:** app File → Sull'iPad → AuguMusic → cartella `Musica`. Copia lì i file, poi in AuguMusic vai su Impostazioni → Aggiorna la libreria.
- **Cartelle esterne:** Impostazioni → Aggiungi cartella… (iCloud Drive, chiavetta, SMB). L'app si ricorda l'accesso.
- **Testi:** `Canzone.mp3` + `Canzone.lrc` nella stessa cartella.

## Struttura

```
project.yml                 progetto XcodeGen (iOS 17+)
.github/workflows/          compilazione dell'.ipa non firmato
Sources/App                 avvio dell'app
Sources/Models              brani, code, playlist, modalità
Sources/Stores              libreria, impostazioni, dati utente
Sources/Services            lettura tag, FLAC, copertine, testi LRC
Sources/Player              motore audio (AVAudioEngine + EQ + TimePitch) e logica code
Sources/Views               interfaccia SwiftUI
```
