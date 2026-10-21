# Titans — versione digitale

Adattamento digitale non ufficiale, per uso personale, di **Titans** di Łukasz Woźniak (Go On Board),
illustrazioni di Piotr Krężelewski. Fatto in Godot 4.7, tutto in italiano, dal regolamento italiano della
copia fisica e dal modulo Tabletop Simulator.

**Gioca:** https://tannoiser2.github.io/Titans/

## Cosa c'è
- **Regole complete del gioco base per 2–4 giocatori**: Carte Ordini con Area degli Ordini e Ordini Successivi
  (regola 3+1 in due), movimento, schieramento, Fortezze, Capitali, Carte Nazione (acquisto dalle prime 3 del
  mazzo, sconti di Round), Battaglie con i dadi veri del gioco e il limite di dadi, Carte Supporto singole, in
  coppia e in tris, ritiro dei dadi, abilità di Nazione e di Titano, esito della Battaglia con perdite, ritirate,
  carte al perdente e PV al vincitore, regola dell'ultima regione, 24 Obiettivi Segreti, fine del Round e Rinforzi.
- **Tutti i 24 scenari del regolamento** (pagine 19–24), sui due lati del tabellone, con Regioni inattive e
  Regione Centrale.
- Le quattro nazioni con le loro 40 Carte Nazione: Commonwealth Polacco-Lituano, Zarato Russo, Regno di Svezia,
  Impero Ottomano.
- **Modalità di gioco**: Modalità Avanzata (Ordini Avanzati, Energia, scambio degli Ordini, abilità avanzate del
  Titano), Presa della Capitale, Partita estesa a 4 Round.
- **IA** a tre livelli in qualunque combinazione con i giocatori umani; più umani sullo stesso dispositivo con la
  schermata «passa il dispositivo».
- **Gioco online** su Firebase: ognuno dal suo dispositivo con un codice di 4 lettere.
- **Tabellone in 3D** ruotabile e zoomabile, con le miniature 3D (Meshy) ricolorate per nazione: fanteria,
  cavalleria, artiglieria, Capitale e un Titano diverso per ogni nazione; Fortezze, stendardi di controllo,
  segnalini delle Regioni inattive e della Regione Centrale.
- Carte originali dal modulo TTS; titoli in Cinzel Decorative, intestazioni in Cinzel e testi in Crimson Pro
  (caratteri OFL), palette ferro, cuoio e oro.

## L'IA
Nella Fase A simula, per ogni Carta Ordini disponibile, le azioni su una copia leggera del tabellone e valuta la
posizione: regioni controllate (pesate dai Round che restano), Capitali e Fortezze, minacce degli eserciti nemici
adiacenti e battaglie innescate con la loro probabilità di vittoria. «Facile» e «Normale» scelgono un'azione alla
volta con un po' di casualità; «Difficile» esplora anche l'ordine delle azioni, senza casualità.
In battaglia calcola quanta Forza serve per vincere (tenendo conto delle carte che l'avversario può ancora
giocare) e spende prima le risorse gratuite (Carte Nazione «una volta per Battaglia», abilità), poi le Carte
Supporto più convenienti; se la battaglia è persa comunque risparmia le carte, salvo per ridurre le perdite.
Sceglie gli Obiettivi Segreti più facili da completare, le Carte Nazione più utili per il resto della partita e
dove ritirarsi e schierare.

## Interpretazioni della versione digitale
- Le Carte Nazione seguono le immagini delle carte (costo, requisiti, uso una volta per Round o per Battaglia)
  e i testi del Compendio delle Nazioni.
- Gli Obiettivi Segreti si completano da soli appena possibile (al massimo uno per turno, il più ricco).
- Il Bogatyr russo può far ritirare un dado qualsiasi della Battaglia, anche dell'avversario.
- Lo spazio fisico delle regioni non è limitato.
- Non sono ancora incluse la Modalità Solitario con l'Automa e le espansioni (5ª Nazione, Monumenti, Campi di
  Sangue, Echi del Passato, Pioggia di Fuoco, Emissari del Re): il materiale italiano c'è, si possono aggiungere.

## Comandi
Trascina con il tasto sinistro per ruotare la vista, con il destro per spostarla, rotella per lo zoom; «Vista»
passa alla vista dall'alto. Le regioni che si possono scegliere sono evidenziate in oro: clic sulla mappa.
Passando il mouse su regioni e carte se ne leggono i dettagli. Nella Battaglia i dadi si scelgono cliccandoli.
F11 schermo intero.

## Gioco online
Dal menu, **Gioca online**. Usa lo stesso progetto Firebase degli altri giochi della ludoteca, con le stanze sotto
`titans/rooms`: la sezione generica `$game` di `firebase/database.rules.json` lo copre già.
Chi crea la stanza sceglie nel menu scenario e opzioni; le nazioni su «Umano» sono i posti per gli amici, che
entrano con il codice. Ogni decisione è una mossa numerata (`acts/0`, `acts/1`, …) e tutti i dispositivi giocano
la stessa partita con lo stesso seme. Chi cade rientra con lo stesso codice; chi tace per un minuto viene
sostituito dall'IA.

## Struttura
```
data/mappa.json               regioni (nomi, centri) e confini dei due lati del tabellone
data/scenari.json             i 24 scenari del regolamento
scripts/data/ti_data.gd       nazioni, dadi, Carte Ordini, Supporto, Nazione e Obiettivi
scripts/core/engine.gd        regole e svolgimento della partita
scripts/core/ai.gd            giocatori artificiali
scripts/ui/                   menu, tabellone 3D, vista di gioco, regole
scripts/net/                  Firebase (REST) e partita online in lockstep
assets/map/                   mappe dei due lati, maschere e mappe delle regioni (per il clic)
assets/modelli/               miniature 3D alleggerite per il web
tests/                        simulazioni, screenshot, prova online con finto Firebase
```

## Prove
```
godot --headless --path . -s tests/sim.gd -- 10 3 1          # 10 partite fra IA, 3 giocatori, livello Normale
godot --headless --path . -s tests/sim.gd -- 10 2 1 1        # …in Modalità Avanzata
python3 tests/firebase_mock.py 8765 & …tests/online_play.gd  # due dispositivi online sul finto Firebase
xvfb-run godot --path . -s res://tests/shot.gd -- game       # screenshot
```
