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
- **Tutti i 24 scenari del regolamento** (pagine 19–24) e i 10 della 5ª Nazione, sui due lati del tabellone, con Regioni inattive e
  Regione Centrale.
- Le cinque nazioni con le loro Carte Nazione: Commonwealth Polacco-Lituano, Zarato Russo, Regno di Svezia,
  Impero Ottomano e, con l'espansione 5ª Nazione, il Sacro Romano Impero (partite fino a 5 giocatori, mazzo di 20 Ordini).
- **Modalità di gioco**: Modalità Avanzata (Ordini Avanzati, Energia, scambio degli Ordini, abilità avanzate del
  Titano), Presa della Capitale, Partita estesa a 4 Round.
- **Modalità Solitario contro l'Automa** (Compendio delle Nazioni): i 6 scenari S1–S6, le 12 carte Automa
  scansionate dalla copia fisica, livello Base o Avanzato (azioni con la stella); l'Automa segue le sue regole di
  scelta (Fronte di Battaglia, Limite d'Armata, priorità di movimento e di ritirata) e il suo copione in Battaglia.
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
Le probabilità delle Battaglie sono calcolate con le distribuzioni esatte dei dadi (limite di dadi compreso) più le
risorse attese di ciascuno; gli Obiettivi Segreti in mano entrano nella valutazione delle mosse. «Normale» e
«Difficile» valutano anche la risposta migliore del giocatore successivo con le Carte Ordini che gli restano.
Le Carte Supporto si scelgono in base ai requisiti che si potranno soddisfare e ai set già in mano.
In battaglia calcola quanta Forza serve per vincere (tenendo conto delle carte che l'avversario può ancora
giocare) e spende prima le risorse gratuite (Carte Nazione «una volta per Battaglia», abilità), poi le Carte
Supporto più convenienti; se la battaglia è persa comunque risparmia le carte, salvo per ridurre le perdite;
se vince giocando per ultimo valuta se salire alla fascia di differenza successiva (più PV, più perdite all'avversario).
I pesi sono stati tarati con centinaia di partite simulate: contro la versione precedente la nuova vince fra il 37%
e il 42% delle partite a 3 giocatori (contro il 33% atteso).
Sceglie gli Obiettivi Segreti più facili da completare, le Carte Nazione più utili per il resto della partita e
dove ritirarsi e schierare.

## Interpretazioni della versione digitale
- Le Carte Nazione seguono le immagini delle carte (costo, requisiti, uso una volta per Round o per Battaglia)
  e i testi del Compendio delle Nazioni.
- Gli Obiettivi Segreti si completano da soli appena possibile (al massimo uno per turno, il più ricco).
- Il Bogatyr russo può far ritirare un dado qualsiasi della Battaglia, anche dell'avversario.
- Lo spazio fisico delle regioni non è limitato.
- Solitario: quando le regole dell'Automa lasciano una scelta libera («scegline una») decide il caso; le Carte
  Supporto dell'Automa sono una pila coperta e paga sempre dal fondo.
- Non sono ancora incluse le altre espansioni (Monumenti, Campi di Sangue, Echi del Passato, Pioggia di Fuoco,
  Emissari del Re).

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
data/scenari.json             i 24 scenari del regolamento, i 10 della 5ª Nazione e i 6 del Solitario
scripts/data/ti_data.gd       nazioni, dadi, Carte Ordini, Supporto, Nazione e Obiettivi
scripts/core/engine.gd        regole e svolgimento della partita
scripts/core/ai.gd            giocatori artificiali
scripts/core/automa.gd        scelte dell'Automa in Battaglia (le sue azioni sono nel motore)
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
TI_SOLO=1 godot --headless --path . -s tests/sim.gd -- 10 2 1 # IA contro l'Automa Base (TI_SOLO=2 Avanzato)
python3 tests/firebase_mock.py 8765 & …tests/online_play.gd  # due dispositivi online sul finto Firebase
xvfb-run godot --path . -s res://tests/shot.gd -- game       # screenshot
```
