extends Control
## Regole in breve (dal regolamento italiano) e riepilogo delle nazioni. Si apre dal menu o in partita.

const D = preload("res://scripts/data/ti_data.gd")

var main
var overlay := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.04, 0.9 if overlay else 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UI.iron_style(10, 0.98))
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 80
	box.offset_right = -80
	box.offset_top = 30
	box.offset_bottom = -30
	add_child(box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	box.add_child(vb)
	var hb := HBoxContainer.new()
	vb.add_child(hb)
	var t := UI.title("Le regole di Titans", 44)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(t)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	hb.add_child(tabs)
	var close := UI.button("Chiudi" if overlay else "Indietro", 180, 50, 22)
	close.pressed.connect(func():
		if overlay:
			queue_free()
		else:
			main.show_menu())
	hb.add_child(close)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 30)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(cols)
	var left := RichTextLabel.new()
	left.bbcode_enabled = true
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	var right := RichTextLabel.new()
	right.bbcode_enabled = true
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	var pages := [["Regole", _rules_a(), _rules_b()], ["Nazioni", _nations_a(), _nations_b()], ["5ª Nazione", _nation("sri"), _fifth()], ["Avanzata e varianti", _adv(), _digital()], ["Solitario", _solo_a(), _solo_b()], ["Espansioni", _xp_a(), _xp_b()]]
	for i in pages.size():
		var b := UI.button(pages[i][0], 170, 44, 18)
		var k := i
		b.pressed.connect(func():
			left.text = pages[k][1]
			right.text = pages[k][2]
			left.scroll_to_line(0)
			right.scroll_to_line(0))
		tabs.add_child(b)
	left.text = pages[0][1]
	right.text = pages[0][2]


func _h(t: String) -> String:
	return "[font_size=28][color=#c9a45a]%s[/color][/font_size]\n" % t


func _rules_a() -> String:
	var s := ""
	s += _h("Scopo")
	s += "Titans si gioca in 3 Round. Si guadagnano Punti Vittoria (PV) controllando Regioni alla fine di ogni Round (1 PV ciascuna), vincendo Battaglie e completando Obiettivi Segreti. Vince chi ha più PV (parità: più Regioni, poi più Unità, poi chi ha giocato per primo).\n\n"
	s += _h("Preparazione")
	s += "Lo scenario indica Capitali, Unità di partenza, Regioni inattive e la Regione Centrale. Ognuno pesca 3 Carte Supporto e guarda le prime 3 Carte del proprio Mazzo Nazione: può acquistarne 1 pagando il costo in Carte Supporto. Poi si scelgono 3 Obiettivi Segreti (4 a testa: se ne tiene 1 e si passano gli altri a destra).\n\n"
	s += _h("Le Carte Ordini")
	s += "Nell'Area degli Ordini ci sono 4 carte (5 in 3 giocatori); sopra, gli Ordini Successivi. Si sceglie a turno una carta; quando ne resta una sola si scarta e gli Ordini Successivi diventano disponibili. Finito il mazzo (12, 15 o 16 carte) il Round termina. In 2 giocatori vale la regola 3+1: l'ultima fila ha una carta coperta, rivelata dopo la prima scelta.\n\n"
	s += _h("Il turno")
	s += "[b]A. Ordini[/b]: scegli una Carta Ordini ed esegui le sue azioni nell'ordine che vuoi (puoi rinunciare a qualcuna).\n"
	s += "• [b]Muovi[/b] un'Unità del tipo indicato (o qualsiasi) in una Regione adiacente; [b]Muovi da 1 a 4 Unità[/b] da una Regione a una adiacente.\n"
	s += "• Quando l'ultima Unità lascia una Regione vi resta il tuo stendardo (Segnalino Controllo); la Capitale vale come segnalino.\n"
	s += "• Entrare in una Regione nemica senza Unità la conquista (la Capitale nemica viene distrutta: +3 PV; la Fortezza diventa tua). Entrare dove ci sono Unità nemiche innesca una Battaglia: le tue Unità restano sul confine.\n"
	s += "• [b]Schiera[/b] un'Unità dalla riserva in una tua Regione; [b]Costruisci una Fortezza[/b] in una tua Regione; [b]Acquista una Carta Nazione[/b] (prime 3 del tuo mazzo, costo in Carte Supporto; nel 3° Round costano 1 in meno).\n"
	s += "[b]B. Battaglie[/b]: risolvi le Battaglie che hai innescato, nell'ordine che vuoi.\n"
	s += "[b]C.[/b] Prendi 1 Carta Supporto (una delle 4 scoperte o dal mazzo).\n"
	s += "[b]D. Ripristino[/b]: scarta fino a 5 Carte Supporto. Il Titano sconfitto si rialza; se era già in piedi puoi schierarlo in una tua Regione.\n\n"
	s += _h("Ultima regione")
	s += "Chi controlla una sola Regione non può essere attaccato; con 2 Regioni se ne può attaccare una sola per turno.\n"
	return s


func _rules_b() -> String:
	var s := ""
	s += _h("La Battaglia")
	s += "Ogni giocatore lancia i dadi delle sue Unità (al massimo 3 Fanteria, 2 Cavalleria, 1 Artiglieria e 1 Dado Titano per il Titano; la riserva è di 2 Dadi Titano). Dadi: Fanteria 0-0-1-1-1-1, Cavalleria 1-1-1-2-2-2, Artiglieria 1-2-2-2-3-3, Titano 1-1-1-2-3-4.\n"
	s += "Prima il Difensore, poi l'Attaccante svolgono la loro Fase Battaglia (con Fortezza o Capitale l'ordine si inverte e il Difensore pesca 1 Carta Supporto). Nella propria fase si può, quante volte si vuole:\n"
	s += "• giocare Carte Supporto rispettandone il requisito (icona nera = la tua Armata, rossa = quella avversaria): [b]Aggiungi un Dado[/b] (1 carta: Dado Fanteria, 2 carte: Dado Titano), [b]Aggiungi Forza[/b] (+1, +3 in coppia, +5 in tris), [b]Muovi 1 Unità in Battaglia[/b] da una Regione adiacente (1 per Battaglia);\n"
	s += "• scartare 1 Carta Supporto per ritirare quanti Dadi si vuole;\n"
	s += "• usare Carte Nazione, l'Abilità del Titano (una volta) e l'Abilità della Nazione.\n"
	s += "Vince chi ha più Forza; in parità vince il Difensore.\n\n"
	s += _h("Esito")
	s += "Differenza 0–2: nessuna perdita, il vincitore prende 1 PV, il perdente pesca 1 carta.\nDifferenza 3–4: il perdente elimina 1 Unità e pesca 2 carte; il vincitore prende 2 PV.\nDifferenza 5 o più: 2 Unità, 3 carte, 4 PV.\n"
	s += "+1 PV a chi elimina il Titano avversario; +1 PV all'Attaccante che distrugge una Fortezza; +3 PV per la Capitale nemica.\n"
	s += "L'Attaccante sconfitto torna nelle Regioni di partenza; il Difensore sconfitto si ritira in una sola Regione adiacente che controlla (o libera, se non ne ha), altrimenti le sue Unità sono distrutte. Il Titano eliminato torna sulla plancia: a terra se attaccava, in piedi se difendeva.\n\n"
	s += _h("Obiettivi Segreti")
	s += "Ognuno può completare al massimo 1 Obiettivo per turno (anche mentre difende): si rivela e si prendono i PV. Nella versione digitale gli Obiettivi si completano da soli appena possibile.\n\n"
	s += _h("Fine del Round")
	s += "1 PV per ogni Regione controllata. Poi si rinnovano le 4 Carte Supporto scoperte, si rimescola il Mazzo Ordini e le Carte Nazione usate tornano disponibili. Rinforzi, a partire dal Primo Giocatore:\n"
	s += "• 1° Rinforzo: prendi 2 Carte Supporto oppure pesca 2 Obiettivi Segreti e tienine 1;\n• 2° Rinforzo: acquista una Carta Nazione (con lo sconto del Round successivo) oppure scarta 1 Carta Supporto e schiera 1 Unità.\n"
	return s


func _nations_a() -> String:
	var s := ""
	for nt in ["pol", "rus"]:
		s += _nation(nt)
	return s


func _nations_b() -> String:
	var s := ""
	for nt in ["sve", "ott"]:
		s += _nation(nt)
	return s


func _nation(nt: String) -> String:
	var n: Dictionary = D.NATIONS[nt]
	var s := _h(n["name"])
	s += "[b]Abilità della Nazione[/b]: %s\n[b]Abilità del Titano[/b]: %s\n" % [n["nation_ab"], n["titan_ab"]]
	s += "[b]Abilità avanzate[/b]: %d Energia — %s; %d Energia — %s\n" % [n["adv"][0]["cost"], n["adv"][0]["text"], n["adv"][1]["cost"], n["adv"][1]["text"]]
	s += "[b]Carte Nazione[/b]:\n"
	for i in 10:
		s += "• (costo %d) %s\n" % [D.NATION_CARDS[nt][i]["cost"], D.nation_card_text(nt, i)]
	return s + "\n"


func _fifth() -> String:
	var s := _h("Espansione 5ª Nazione")
	s += "Aggiunge il Sacro Romano Impero, con 10 scenari sul lato B del tabellone: 4 per 2 giocatori, 2 per 3, 2 per 4 e 2 per 5 giocatori.\n\n"
	s += _h("Partita a 5 giocatori")
	s += "Si aggiungono 4 Carte Ordini (e 4 Carte Ordini Avanzati in Modalità Avanzata): il mazzo è di 20 carte. Nell'Area degli Ordini e negli Ordini Successivi ci sono 4 carte, come in 4 giocatori; ognuno gioca 3 turni per Round. Gli Obiettivi Segreti si risolvono come in 4 giocatori.\n"
	return s


func _solo_a() -> String:
	var s := _h("Modalità Solitario")
	s += "Giochi contro l'Automa, un avversario guidato da 12 carte con le sue azioni. Si gioca su uno dei 6 scenari dedicati (S1–S6, lato A); scegli quale delle due Nazioni guidi. Si usano tutte le 16 Carte Ordini del gioco base; la Modalità Avanzata e le varianti non si usano.\n\n"
	s += _h("Preparazione")
	s += "• L'Automa è il Primo Giocatore. Alcune Carte Nazione di ciascuna Nazione vengono tolte dal suo mazzo.\n"
	s += "• Tu e l'Automa pescate 3 Carte Supporto: tu acquisti le Carte Nazione come di consueto, l'Automa rivela la prima del suo mazzo e la paga con le carte dal fondo della sua pila (se non può, la mette in fondo al mazzo e pesca 1 Carta Supporto).\n"
	s += "• Peschi 2 Obiettivi Segreti tre volte e ne tieni 1 ogni volta.\n\n"
	s += _h("Il turno")
	s += "Il turno è come nel gioco base, ma alla fine di ogni turno del giocatore le 2 Carte Ordini rimaste nell'Area si scartano, gli Ordini Successivi scorrono e se ne pescano 4. Senza più carte nel Mazzo Ordini il turno successivo è l'ultimo del Round.\n\n"
	s += _h("Il turno dell'Automa")
	s += "1. Pesca una carta Automa.\n2. Risolve le azioni dall'alto verso il basso (a livello Base ignora quelle con la stella); un'azione impossibile si salta.\n3. Risolve le Battaglie nell'ordine in cui le ha iniziate.\n4. Pesca 1 Carta Supporto coperta.\n5. Ripristino: scarta dal fondo le carte oltre il limite; se il suo Titano è stato sconfitto torna nell'Armata più grande.\n6. Scarta la Carta Ordini nella posizione indicata (I–IV), lasciandoti 3 carte fra cui scegliere.\n\n"
	s += _h("Fine della partita")
	s += "Al termine del 3° Round vinci se hai più Punti Vittoria dell'Automa: in parità vince l'Automa. Perdi subito se l'Automa conquista la tua Capitale. L'Automa prende 2 PV per ogni Regione che controlla a fine Round.\n"
	return s


func _solo_b() -> String:
	var s := _h("Le azioni dell'Automa")
	s += "• [b]Recluta[/b] 1 Fanteria, o l'Unità più forte disponibile (Artiglieria, poi Cavalleria, poi Fanteria), nella Regione indicata.\n"
	s += "• [b]Movimento verso la Capitale[/b]: l'Armata indicata avanza di 1 Regione lungo il percorso più breve verso la tua Capitale.\n"
	s += "• [b]Movimento d'Espansione[/b]: l'Armata indicata entra in una Regione adiacente, nell'ordine: Regione libera controllata da te, Regione libera non controllata, Regione con la tua Armata più piccola, Regione con l'Armata più piccola dell'Automa.\n"
	s += "• [b]Acquista una Carta Nazione[/b] dalla cima del suo mazzo.\n"
	s += "Le Armate indicate sono la più grande, la più piccola, quella con l'Artiglieria o quella con il Titano.\n\n"
	s += _h("Regole di scelta")
	s += "• [b]Fronte di Battaglia[/b]: fra più Regioni o Armate valide sceglie quella adiacente al maggior numero di tue Regioni, poi quella vicina a più Regioni libere.\n"
	s += "• [b]Limite d'Armata[/b]: non crea Armate che superano il limite dei dadi (3 Fanterie, 2 Cavallerie, 1 Artiglieria): sceglie l'opzione successiva.\n"
	s += "• Con tutti i Segnalini Controllo piazzati non lascia Regioni che controlla.\n\n"
	s += _h("In Battaglia")
	s += "L'Automa usa l'abilità della Nazione e le Carte Nazione possibili, poi le Carte Supporto (Muovi > Forza > Dado, il set più grande), e ritira i dadi con il risultato più basso. Se gioca per secondo e ha già il vantaggio massimo (5, o 3 contro una sola Unità) si ferma. Paga i costi con le carte dal fondo della sua pila, perde prima le Unità più deboli e si ritira verso la propria Capitale.\n"
	return s


func _xp_a() -> String:
	var s := _h("Monumenti")
	s += "Ogni Nazione ha 3 Monumenti. Nel tuo turno (nel menu delle azioni della Fase A o dopo la Fase D) puoi costruirne 1, pagando il costo in Carte Supporto (sconto del 3° Round come le Carte Nazione), in una Regione che controlli senza Capitale, Fortezza o altri Monumenti. Dove c'è un Monumento non si costruisce una Fortezza. Se perdi il controllo della Regione il Monumento è distrutto per sempre.\n"
	for nt in D.NATION_ORDER:
		s += "\n[b]%s[/b]\n" % D.NATIONS[nt]["name"]
		for i in 3:
			var md: Dictionary = D.MONUMENTS[nt][i]
			s += "• [b]%s[/b] (%s): %s\n" % [md["name"], ["I", "II", "III"][i], md["text"]]
	return s


func _xp_b() -> String:
	var s := _h("Emissari del Re")
	s += "Prima degli Obiettivi Segreti ognuno riceve i 3 Obiettivi Nazione della sua Nazione; si preparano tanti Emissari quanti sono i giocatori (3 in due). Si completa sempre al massimo 1 Obiettivo per turno, Segreto o Nazione.\n"
	s += "• Il 1° Obiettivo Nazione dà un Emissario, che scegli fra quelli disponibili e affidi all'Armata che ha completato l'Obiettivo; il 2° vale 3 PV, il 3° 5 PV.\n"
	s += "• L'Emissario segue l'Armata quando muove (o resta, a tua scelta) e la aiuta in Battaglia: +2 Dadi Fanteria, +1 Dado Cavalleria, 1 Carta Supporto, 1 Dado al massimo oppure +1 PV se vinci.\n"
	s += "• Dopo una vittoria si gira e nella Battaglia successiva non aiuta, ma torna attivo. Se l'Armata perde si ritira con lei; se l'Armata è eliminata l'Emissario torna disponibile.\n\n"
	s += _h("Pioggia di Fuoco")
	s += "Ogni Nazione ha un'Artiglieria di Fuoco nella riserva. Quando uno schieramento di Artiglieria o Fanteria crea in una Regione la coppia Artiglieria + Fanteria, puoi rimettere le due Unità nella riserva e schierare al loro posto l'Artiglieria di Fuoco.\n"
	s += "• Per movimento, carte e abilità è 1 Unità di Artiglieria; in Battaglia tira 1 Dado Artiglieria e anche 1 Dado Fanteria.\n"
	s += "• Se eliminata torna nella riserva e si può ricreare.\n\n"
	s += _h("Echi del Passato")
	s += "Ognuno sceglie una carta Unità Caduta (dall'ultimo giocatore, in senso antiorario) e mette 1 Unità Caduta in una sua Regione con Unità. Le Unità Cadute (12 in tutto) non si muovono né si schierano con gli Ordini: seguono gratis le Unità che muovi; se restano sole disertano.\n"
	s += "• In Battaglia tirano 1 Dado Unità Caduta ciascuna (Forza 0, 1 o 2; alcune facce hanno il teschio). Dopo aver stabilito il vincitore si elimina 1 Unità Caduta per ogni teschio. Non si scelgono come perdite.\n"
	s += "• Chi perde una Battaglia ottiene 1 Unità Caduta se soddisfa la condizione della sua carta; la carta ha anche un'abilità negativa che vale nelle Battaglie con le sue Unità Cadute.\n\n"
	s += _h("Campi di Sangue")
	s += "Il mazzo Supporto è sostituito da quello di Campi di Sangue (36 carte con lo stesso effetto e in più il Simbolo dei Cosacchi). Ognuno parte con 1 Cosacco in una sua Regione; i Cosacchi (15 in tutto) sono un tipo di Unità diverso, con il loro Dado (0, 0, 1, 1, 2, 2).\n"
	s += "• Nella Fase A, una volta per turno, Azione speciale: muovi 1 Cosacco di 1 Regione, oppure metti una carta dalla mano sotto la Plancia come Potenziamento (mai due uguali), oppure, se non hai Cosacchi sulla mappa, scarta una carta con lo Schieramento e prendi 1 Cosacco.\n"
	s += "• Con l'azione «Schiera 1 Unità» si può schierare un Cosacco; con i movimenti di «1 Unità» o «da 1 a 4 Unità» si muovono anche i Cosacchi. Un Cosacco che entra in una Regione non tua si ferma per quel turno.\n"
	s += "• Dopo la Battaglia ognuno può usare il Simbolo dei Cosacchi delle carte giocate (non quelle scartate per ritirare): con 1–4 carte lo Schieramento (solo se non avevi Cosacchi in Battaglia) oppure 1 Potenziamento; con 5 o più lo Schieramento e 1 o 2 Potenziamenti.\n\n"
	s += _h("Spirito di Guerra")
	s += "Il mazzo Supporto è sostituito da quello di Spirito di Guerra (con Campi di Sangue i due mazzi si mescolano, le carte scoperte sono 6 e i set si fanno solo con carte dello stesso mazzo). I 6 Dadi Spirito di Guerra (simbolo, simbolo, simbolo, 2, 3, 4) sono in comune: se finiscono non si possono prendere.\n"
	s += "• «Aggiungi Forza»: 1 carta +1 Forza; 2 o 3 carte 1 Dado Spirito di Guerra, e il simbolo vale +3 (2 carte) o +6 (3 carte).\n"
	s += "• «Aggiungi un Dado»: 1 carta 1 Dado Fanteria; 2 carte 1 Dado Spirito di Guerra, e il simbolo attiva l'effetto di una delle due carte (muovere un'Unità di 1 o 2 Regioni nella Battaglia, aggiungere una Fanteria dalla riserva, ripristinare una Carta Nazione, portare al massimo gli altri dadi, +1 Forza per ogni dado dell'avversario o per ogni tuo dado).\n"
	s += "• Un Dado Spirito di Guerra con il simbolo resta sulla carta e non si ritira più.\n\n"
	s += _h("Potere dei Titani")
	s += "Ognuno ha 5 Carte Potere del Titano della sua Nazione: in preparazione ne pesca 2 e ne tiene 1 (l'altra in fondo). Ogni volta che attacca con il Titano, a fine Battaglia ne pesca altre 2 e ne tiene 1.\n"
	s += "• Se il Titano è in Battaglia si può attivare una carta (una sola per Battaglia) mettendoci sopra i Dadi richiesti: 2 o 3 Dadi diversi oppure uguali per tipo. I Dadi contano per la Forza ma non si ritirano più. L'effetto si risolve subito.\n\n"
	s += _h("Interpretazioni della versione digitale")
	s += "• Potere dei Titani: le carte restano e si possono riusare nelle Battaglie successive; i Dadi da mettere sulla carta sono scelti in automatico fra i più bassi.\n"
	s += "• Campi di Sangue: il Dado Cosacco ha due facce vuote, due da 1 e due da 2 (dalle scansioni si vedono le facce con le sciabole).\n"
	s += "• Unità Cadute: non contano per la dimensione dell'Armata né per il controllo delle Regioni.\n"
	s += "• Il costo dei Monumenti è il numero romano della carta (I, II, III).\n"
	s += "• Si costruisce al massimo 1 Monumento per turno. Castello Reale, San Basilio e Giannizzeri si attivano da soli, dopo le Battaglie o dopo la Fase D.\n"
	s += "• Santa Sofia si perde se perdi la Regione su cui l'hai costruita.\n"
	s += "• Quando muovi un'Artiglieria da una Regione con l'Artiglieria di Fuoco si muove quella di Fuoco; nelle perdite si elimina per ultima.\n"
	return s


func _adv() -> String:
	var s := _h("Modalità Avanzata")
	s += "Si usa il Mazzo Ordini Avanzati e il lato della plancia con il tracciato Energia (si parte con 1, massimo 10).\n"
	s += "• Prima della Fase A puoi pagare tanta Energia quante sono le carte nell'Area degli Ordini per scambiare una carta con una degli Ordini Successivi.\n"
	s += "• Dopo la Fase A guadagni Energia: con le carte a più azioni 1 Energia, oppure 4 se non hai usato almeno un'azione; con «Muovi da 1 a 4 Unità» 0/2/4/6 Energia muovendo 4/3/2/1 Unità.\n"
	s += "• L'Energia paga le Abilità Avanzate del Titano (una volta per turno ciascuna).\n"
	s += "• Finito il Mazzo Ordini, gli scarti formano un'ultima fila di Ordini Successivi, utile solo per gli scambi.\n\n"
	s += _h("Presa della Capitale")
	s += "Le Capitali non vengono distrutte ma conquistate: chi vince la Battaglia nella Capitale prende 1 PV e ne ottiene il controllo e le difese; se esce con tutte le Unità, la Capitale torna al proprietario. A fine partita 2 PV per ogni Capitale controllata (anche la propria).\n\n"
	s += _h("Partita estesa")
	s += "4 Round invece di 3: le Carte Nazione costano 1 in meno nel 3° Round e 2 in meno nel 4°.\n"
	return s


func _digital() -> String:
	var s := _h("Comandi")
	s += "• Trascina con il tasto sinistro per ruotare la vista, con il destro per spostarla, rotella per lo zoom. «Vista» passa dalla prospettiva alla vista dall'alto.\n"
	s += "• Le regioni evidenziate in oro sono quelle che puoi scegliere: clicca sulla mappa.\n"
	s += "• Passa il mouse su carte e regioni per leggerne i dettagli; clic su una carta Nazione o Ordini per ingrandirla.\n"
	s += "• Nella Battaglia i dadi si scelgono cliccandoli nel pannello in alto.\n"
	s += "• F11: schermo intero.\n\n"
	s += _h("Interpretazioni della versione digitale")
	s += "• Le Carte Nazione seguono le immagini delle carte (costo, requisiti, simbolo di uso una volta per Round) e i testi del Compendio delle Nazioni.\n"
	s += "• Le carte Supporto giocate in coppia o in tris sono scelte automaticamente fra quelle con il requisito soddisfatto.\n"
	s += "• Il Bogatyr russo può far ritirare un dado qualsiasi della Battaglia, anche dell'avversario.\n"
	s += "• Lo spazio fisico delle regioni non è limitato.\n"

	return s
