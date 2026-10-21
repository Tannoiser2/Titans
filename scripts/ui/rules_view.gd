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
	var pages := [["Regole", _rules_a(), _rules_b()], ["Nazioni", _nations_a(), _nations_b()], ["Avanzata e varianti", _adv(), _digital()]]
	for i in pages.size():
		var b := UI.button(pages[i][0], 220, 44, 19)
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
	s += "• Non sono incluse (per ora) la Modalità Solitario con l'Automa e le espansioni.\n"
	return s
