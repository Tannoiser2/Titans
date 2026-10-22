class_name TIData
extends RefCounted
## Dati del gioco: nazioni, unità, dadi, carte Ordini, Supporto, Nazione e Obiettivo Segreto, mappa e
## scenari (dal regolamento italiano). Le carte sono descritte con codici che il motore interpreta.

# ---------------------------------------------------------------- unità e dadi

const UNITS := ["F", "K", "A", "T"]
const UNIT_NAME := {"F": "Fanteria", "K": "Cavalleria", "A": "Artiglieria", "T": "Titano"}
const UNIT_NAME_PL := {"F": "Fanterie", "K": "Cavallerie", "A": "Artiglierie", "T": "Titani"}
const FIRE_NAME := "Artiglieria di Fuoco"
## Unità di ogni nazione (13: 6 Fanteria, 4 Cavalleria, 2 Artiglieria, 1 Titano).
const UNIT_COUNT := {"F": 6, "K": 4, "A": 2, "T": 1}
## Facce dei dadi (simboli successo), dalla plancia.
const DICE := {
	"F": [0, 0, 1, 1, 1, 1],
	"K": [1, 1, 1, 2, 2, 2],
	"A": [1, 2, 2, 2, 3, 3],
	"T": [1, 1, 1, 2, 3, 4],
}
## Limite di dadi per giocatore in battaglia.
const DICE_LIMIT := {"F": 3, "K": 2, "A": 1, "T": 2}
const MAX_ENERGY := 10
const FORTRESSES := 3

# ---------------------------------------------------------------- nazioni

const NATIONS := {
	"pol": {
		"name": "Commonwealth Polacco-Lituano", "short": "Polonia", "code": "R",
		"color": Color("#b3262b"), "light": Color("#e8695e"), "dark": Color("#5c1214"),
		"spirit": "Il Grande Magnate", "titan": "Lech",
		"nation_ab": "Se nella tua Armata ci sono 2 Cavallerie: +1 Forza.",
		"titan_ab": "Scarta 1 Carta Supporto per portare 1 tuo Dado al valore massimo.",
		"adv": [
			{"cost": 4, "key": "reroll_any", "text": "Fase Battaglia: ritira qualsiasi Dado della tua Riserva (Titano in Battaglia)."},
			{"cost": 7, "key": "cav_in", "text": "Prima della Battaglia: muovi 1 Cavalleria da una Regione adiacente nella Battaglia (Titano in Battaglia)."},
		],
	},
	"rus": {
		"name": "Zarato Russo", "short": "Russia", "code": "Y",
		"color": Color("#e09a1e"), "light": Color("#f7c45c"), "dark": Color("#6e4508"),
		"spirit": "La Madre della Nazione", "titan": "il Bogatyr",
		"nation_ab": "Se nella tua Armata c'è esattamente 1 Fanteria: +1 Dado Fanteria.",
		"titan_ab": "Puoi ritirare 1 Dado qualsiasi della Battaglia.",
		"adv": [
			{"cost": 5, "key": "foe_rand_discard", "text": "Prima della Battaglia: l'avversario scarta 1 Carta Supporto a caso (Titano in Battaglia)."},
			{"cost": 7, "key": "titan_army", "text": "Fase A: l'azione «Muovi il Titano» vale come «Muovi da 1 a 4 Unità»."},
		],
	},
	"sve": {
		"name": "Regno di Svezia", "short": "Svezia", "code": "B",
		"color": Color("#2f63a8"), "light": Color("#79a7e0"), "dark": Color("#13294a"),
		"spirit": "Lo Spirito del Nord", "titan": "il Gigante dei ghiacci",
		"nation_ab": "Se nella tua Armata ci sono almeno 2 Fanterie: +1 Dado Cavalleria.",
		"titan_ab": "Puoi giocare 1 Carta Supporto senza soddisfarne i requisiti.",
		"adv": [
			{"cost": 4, "key": "titan_twice", "text": "Fase A: l'azione «Muovi il Titano» vale due movimenti (il primo non può innescare una Battaglia)."},
			{"cost": 7, "key": "draw2", "text": "Fase Battaglia: pesca 2 Carte Supporto dal mazzo (Titano in Battaglia)."},
		],
	},
	"ott": {
		"name": "Impero Ottomano", "short": "Ottomani", "code": "G",
		"color": Color("#2f7a45"), "light": Color("#6fc184"), "dark": Color("#123a1f"),
		"spirit": "Lo Spirito dei Turchi", "titan": "il Genio",
		"nation_ab": "Se nella tua Armata ci sono Fanteria e Artiglieria: +1 Forza.",
		"titan_ab": "Il tuo avversario svolge per primo la Fase Battaglia, poi tu.",
		"adv": [
			{"cost": 5, "key": "take_faceup", "text": "Fase Battaglia: prendi 1 delle 4 Carte Supporto scoperte (Titano in Battaglia)."},
			{"cost": 6, "key": "titan_in", "text": "Prima della Battaglia: muovi il Titano da una Regione adiacente nella Battaglia."},
		],
	},
	"sri": {
		"name": "Sacro Romano Impero", "short": "Impero", "code": "H",
		"color": Color("#4a4b52"), "light": Color("#e2bd4f"), "dark": Color("#17171b"),
		"spirit": "Lo Spirito Tedesco", "titan": "il Guerriero della foresta",
		"nation_ab": "Se nella tua Armata ci sono esattamente 2 o 3 Unità: +1 Dado Fanteria.",
		"titan_ab": "Scarta 1 Carta Supporto e prendi 1 delle 4 Carte Supporto scoperte.",
		"adv": [
			{"cost": 6, "key": "die_k", "text": "Fase Battaglia: aggiungi 1 Dado Cavalleria (Titano in Battaglia)."},
			{"cost": 7, "key": "titan_inf", "text": "Fase A: aggiungi 1 Fanteria nella Regione del Titano."},
		],
		"expansion": true,
	},
}
const NATION_ORDER := ["pol", "rus", "sve", "ott", "sri"]
const CODE_TO_NATION := {"R": "pol", "Y": "rus", "B": "sve", "G": "ott", "H": "sri"}

# ---------------------------------------------------------------- carte Ordini
## Azioni: mF/mK/mA/mT muovi quell'unità, mX muovi un'unità qualsiasi, army muovi da 1 a 4 unità,
## dF/dK/dA schiera quell'unità, dX schiera un'unità qualsiasi (anche il Titano), fort costruisci Fortezza,
## buy acquista Carta Nazione, buy1 acquista con sconto di 1.
## min = numero minimo di giocatori per cui la carta è nel mazzo.
## energy (Modalità Avanzata): "act" = 1 o 4 Energia, "army" = 0/2/4/6.

const ORDERS := [
	{"a": ["mF", "mA", "dK"], "min": 2},
	{"a": ["mK", "mA", "dF"], "min": 2},
	{"a": ["mF", "mK", "mT"], "min": 2},
	{"a": ["mT", "fort", "dX"], "min": 2},
	{"a": ["mF", "mT", "dX"], "min": 2},
	{"a": ["mK", "mT", "dF"], "min": 2},
	{"a": ["army"], "min": 2},
	{"a": ["army"], "min": 2},
	{"a": ["army"], "min": 2},
	{"a": ["buy", "mX"], "min": 3},
	{"a": ["mF", "mA", "mT"], "min": 2},
	{"a": ["buy", "mX"], "min": 2},
	{"a": ["buy1", "mF"], "min": 2},
	{"a": ["army"], "min": 3},
	{"a": ["mF", "mT", "dK"], "min": 3},
	{"a": ["mK", "mA", "dF"], "min": 4},
	{"a": ["army"], "min": 5},
	{"a": ["mA", "mT", "dF"], "min": 5},
	{"a": ["buy1", "mF"], "min": 5},
	{"a": ["mF", "mK", "dX"], "min": 5},
]

const ADV_ORDERS := [
	{"a": ["mF", "mK", "mA"], "min": 4},
	{"a": ["mK", "mT", "dF"], "min": 2},
	{"a": ["mK", "mA", "dF"], "min": 2},
	{"a": ["mF", "mT", "dA"], "min": 2},
	{"a": ["mF", "mT", "fort"], "min": 2},
	{"a": ["buy", "mF", "dK"], "min": 2},
	{"a": ["mF", "mK", "mT"], "min": 2},
	{"a": ["mF", "mA", "dK"], "min": 2},
	{"a": ["army"], "min": 2},
	{"a": ["army"], "min": 2},
	{"a": ["mK", "mA", "mT"], "min": 2},
	{"a": ["buy", "mA", "mK"], "min": 2},
	{"a": ["army"], "min": 2},
	{"a": ["buy", "mT", "dF"], "min": 3},
	{"a": ["mF", "mT", "dK"], "min": 3},
	{"a": ["army"], "min": 4},
	{"a": ["mF", "mK", "dA"], "min": 5},
	{"a": ["army"], "min": 5},
	{"a": ["mA", "mT", "dF"], "min": 5},
	{"a": ["buy", "mF", "mK"], "min": 5},
]

const ACTION_NAME := {
	"mF": "Muovi 1 Fanteria", "mK": "Muovi 1 Cavalleria", "mA": "Muovi 1 Artiglieria", "mT": "Muovi il Titano",
	"mX": "Muovi 1 Unità", "army": "Muovi da 1 a 4 Unità", "dF": "Schiera 1 Fanteria", "dK": "Schiera 1 Cavalleria",
	"dA": "Schiera 1 Artiglieria", "dX": "Schiera 1 Unità", "fort": "Costruisci una Fortezza",
	"buy": "Acquista una Carta Nazione", "buy1": "Acquista una Carta Nazione (sconto 1)",
}

# ---------------------------------------------------------------- carte Supporto
## kind: "dado" (+1 Dado Fanteria; in coppia +1 Dado Titano), "forza" (+1 / +3 in coppia / +5 in tris),
## "muovi" (muovi 1 Unità da una Regione adiacente nella Battaglia, 1 per Battaglia).
## req: [lato, unità]: "own" = la tua Armata deve avere l'unità, "foe" = l'Armata avversaria.
## L'ordine segue le immagini (assets/carte/supNN.jpg).

const SUPPORT := [
	{"kind": "dado", "req": ["own", "T"]}, {"kind": "dado", "req": ["own", "A"]}, {"kind": "dado", "req": ["own", "K"]},
	{"kind": "dado", "req": ["own", "F"]}, {"kind": "dado", "req": ["foe", "T"]}, {"kind": "dado", "req": ["foe", "A"]},
	{"kind": "dado", "req": ["foe", "K"]}, {"kind": "dado", "req": ["foe", "F"]}, {"kind": "muovi", "req": ["foe", "T"]},
	{"kind": "muovi", "req": ["foe", "A"]}, {"kind": "muovi", "req": ["foe", "K"]}, {"kind": "muovi", "req": ["foe", "F"]},
	{"kind": "forza", "req": ["foe", "T"]}, {"kind": "forza", "req": ["foe", "A"]}, {"kind": "forza", "req": ["foe", "F"]},
	{"kind": "forza", "req": ["foe", "K"]}, {"kind": "forza", "req": ["own", "T"]}, {"kind": "forza", "req": ["own", "F"]},
	{"kind": "forza", "req": ["own", "K"]}, {"kind": "forza", "req": ["own", "A"]}, {"kind": "forza", "req": ["own", "A"]},
	{"kind": "forza", "req": ["own", "F"]}, {"kind": "forza", "req": ["own", "K"]}, {"kind": "forza", "req": ["own", "T"]},
	{"kind": "forza", "req": ["foe", "K"]}, {"kind": "forza", "req": ["foe", "F"]}, {"kind": "forza", "req": ["foe", "A"]},
	{"kind": "forza", "req": ["foe", "T"]}, {"kind": "muovi", "req": ["foe", "F"]}, {"kind": "muovi", "req": ["foe", "K"]},
	{"kind": "muovi", "req": ["foe", "A"]}, {"kind": "muovi", "req": ["foe", "T"]}, {"kind": "dado", "req": ["own", "F"]},
	{"kind": "dado", "req": ["own", "K"]}, {"kind": "dado", "req": ["own", "A"]}, {"kind": "dado", "req": ["own", "T"]},
]

const SUPPORT_NAME := {"dado": "Aggiungi un Dado", "forza": "Aggiungi Forza", "muovi": "Muovi 1 Unità in Battaglia"}

# ---------------------------------------------------------------- carte Nazione
## when: "battaglia" (nella tua Fase Battaglia), "prima" (prima della Battaglia), "vinta" (dopo aver vinto,
## prima di eliminare le Unità e assegnare i PV), "dopo" (dopo la Battaglia), "turno_a" (prima della Fase A
## del tuo turno), "dopo_d" (dopo la Fase D del tuo turno).
## req: elenco di condizioni: own_F/K/A/T, foe_F/K/A/T, own_1F (esattamente 1 Fanteria), own_2K (almeno 2
## Cavallerie), only_A (solo Artiglierie), att (sei l'Attaccante), def (sei il Difensore), fewer (la tua
## Armata ha meno Unità di quella avversaria), foe_2 (l'avversario ha almeno 2 Unità).
## eff: die_F/K/A/T, str_N, max_die, draw, draw_discard, vp, dice2_str3, sup2_titan, foe_discard,
## look_discard, take_discard, move_in, foe_move_out, deploy_F, move_F, win_str.
## freq: "round" (si ruota fino a fine Round), "battaglia" (una volta per Battaglia), "turno".
## Ordine = immagini assets/carte/<naz>NN.jpg.

const NATION_CARDS := {
	"rus": [
		{"cost": 2, "when": "battaglia", "req": ["own_F"], "eff": "die_T", "freq": "round"},
		{"cost": 1, "when": "prima", "req": ["fewer"], "eff": "move_in", "freq": "round"},
		{"cost": 0, "when": "vinta", "req": ["own_F", "foe_F"], "eff": "vp", "freq": "battaglia"},
		{"cost": 2, "when": "battaglia", "req": ["own_A", "foe_F"], "eff": "str_2", "freq": "round"},
		{"cost": 3, "when": "battaglia", "req": ["att", "own_A"], "eff": "die_T", "freq": "round"},
		{"cost": 1, "when": "battaglia", "req": ["own_F", "foe_A"], "eff": "draw", "freq": "battaglia"},
		{"cost": 2, "when": "battaglia", "req": ["own_K"], "eff": "die_K", "freq": "round"},
		{"cost": 1, "when": "battaglia", "req": ["own_K", "foe_K"], "eff": "die_F", "freq": "battaglia"},
		{"cost": 2, "when": "battaglia", "req": [], "eff": "max_die", "freq": "round"},
		{"cost": 2, "when": "prima", "req": ["def"], "eff": "look_discard", "freq": "round"},
	],
	"ott": [
		{"cost": 1, "when": "dopo_d", "req": [], "eff": "deploy_F", "freq": "round"},
		{"cost": 2, "when": "battaglia", "req": [], "eff": "sup2_titan", "freq": "round"},
		{"cost": 0, "when": "battaglia", "req": ["own_K", "foe_A"], "eff": "die_F", "freq": "battaglia"},
		{"cost": 1, "when": "prima", "req": ["fewer"], "eff": "foe_discard", "freq": "battaglia"},
		{"cost": 2, "when": "battaglia", "req": ["own_F", "foe_F"], "eff": "die_F", "freq": "battaglia"},
		{"cost": 2, "when": "battaglia", "req": ["own_A", "foe_K"], "eff": "str_2", "freq": "battaglia"},
		{"cost": 3, "when": "battaglia", "req": ["own_2K"], "eff": "die_T", "freq": "round"},
		{"cost": 1, "when": "vinta", "req": ["own_F"], "eff": "vp", "freq": "battaglia"},
		{"cost": 1, "when": "vinta", "req": [], "eff": "draw", "freq": "battaglia"},
		{"cost": 1, "when": "battaglia", "req": ["only_A"], "eff": "die_K", "freq": "battaglia"},
	],
	"sve": [
		{"cost": 0, "when": "dopo", "req": [], "eff": "take_discard", "freq": "round"},
		{"cost": 2, "when": "prima", "req": ["own_K"], "eff": "draw", "freq": "battaglia"},
		{"cost": 1, "when": "turno_a", "req": [], "eff": "move_F", "freq": "turno"},
		{"cost": 1, "when": "battaglia", "req": ["def", "own_A"], "eff": "die_T", "freq": "round"},
		{"cost": 1, "when": "battaglia", "req": ["own_A", "foe_F"], "eff": "str_1", "freq": "battaglia"},
		{"cost": 3, "when": "battaglia", "req": ["own_1F", "foe_K"], "eff": "die_T", "freq": "round"},
		{"cost": 1, "when": "battaglia", "req": ["own_K", "foe_A"], "eff": "die_A", "freq": "round"},
		{"cost": 2, "when": "battaglia", "req": ["own_F"], "eff": "die_K", "freq": "battaglia"},
		{"cost": 1, "when": "vinta", "req": ["fewer"], "eff": "vp", "freq": "battaglia"},
		{"cost": 2, "when": "vinta", "req": [], "eff": "win_str", "freq": "battaglia"},
	],
	"pol": [
		{"cost": 2, "when": "battaglia", "req": [], "eff": "dice2_str3", "freq": "round"},
		{"cost": 0, "when": "prima", "req": ["own_A"], "eff": "draw_discard", "freq": "battaglia"},
		{"cost": 2, "when": "battaglia", "req": ["def", "fewer"], "eff": "die_T", "freq": "round"},
		{"cost": 2, "when": "battaglia", "req": ["own_K", "foe_F"], "eff": "die_F", "freq": "battaglia"},
		{"cost": 2, "when": "battaglia", "req": ["own_F", "foe_K"], "eff": "die_A", "freq": "round"},
		{"cost": 3, "when": "battaglia", "req": ["own_K", "foe_A"], "eff": "die_T", "freq": "round"},
		{"cost": 2, "when": "battaglia", "req": ["att", "own_A"], "eff": "str_2", "freq": "round"},
		{"cost": 1, "when": "dopo", "req": ["own_F"], "eff": "draw", "freq": "battaglia"},
		{"cost": 1, "when": "vinta", "req": ["own_K"], "eff": "vp", "freq": "battaglia"},
		{"cost": 1, "when": "prima", "req": ["att", "foe_2"], "eff": "foe_move_out", "freq": "round"},
	],
	"sri": [
		{"cost": 1, "when": "battaglia", "req": ["own_F", "foe_A"], "eff": "die_F", "freq": "battaglia"},
		{"cost": 0, "when": "battaglia", "req": ["own_F", "foe_K"], "eff": "die_K", "freq": "round"},
		{"cost": 2, "when": "battaglia", "req": ["own_K", "foe_F"], "eff": "str_2", "freq": "round"},
		{"cost": 1, "when": "vinta", "req": ["own_A"], "eff": "vp", "freq": "battaglia"},
		{"cost": 3, "when": "battaglia", "req": ["fewer"], "eff": "die_T", "freq": "round"},
		{"cost": 0, "when": "battaglia", "req": [], "eff": "reroll2", "freq": "battaglia"},
		{"cost": 2, "when": "battaglia", "req": ["own_F", "foe_F"], "eff": "die_A", "freq": "round"},
		{"cost": 2, "when": "battaglia", "req": ["own_A", "foe_A"], "eff": "die_T", "freq": "round"},
		{"cost": 3, "when": "battaglia", "req": ["own_K"], "eff": "str_1", "freq": "battaglia"},
		{"cost": 1, "when": "battaglia", "req": ["more"], "eff": "die_F", "freq": "battaglia"},
	],
}

const WHEN_TEXT := {
	"battaglia": "In Battaglia", "prima": "Prima della Battaglia", "vinta": "Dopo aver vinto la Battaglia",
	"dopo": "Dopo la Battaglia", "turno_a": "Prima della Fase A del tuo turno", "dopo_d": "Dopo la Fase D del tuo turno",
}
const REQ_TEXT := {
	"own_F": "hai almeno 1 Fanteria", "own_K": "hai almeno 1 Cavalleria", "own_A": "hai almeno 1 Artiglieria",
	"own_T": "hai il Titano", "foe_F": "l'avversario ha Fanteria", "foe_K": "l'avversario ha Cavalleria",
	"foe_A": "l'avversario ha Artiglieria", "foe_T": "l'avversario ha il Titano", "own_1F": "hai esattamente 1 Fanteria",
	"own_2K": "hai almeno 2 Cavallerie", "only_A": "la tua Armata è di sole Artiglierie", "att": "sei l'Attaccante",
	"def": "sei il Difensore", "fewer": "la tua Armata ha meno Unità di quella avversaria",
	"foe_2": "l'avversario ha almeno 2 Unità",
	"more": "la tua Armata ha più Unità di quella avversaria",
}
const EFF_TEXT := {
	"die_F": "Lancia 1 Dado Fanteria", "die_K": "Lancia 1 Dado Cavalleria", "die_A": "Lancia 1 Dado Artiglieria",
	"die_T": "Lancia 1 Dado Titano", "str_1": "+1 Forza", "str_2": "+2 Forza", "max_die": "Porta 1 Dado al valore massimo",
	"draw": "Pesca 1 Carta Supporto", "draw_discard": "Pesca 1 Carta Supporto, poi scartane 1", "vp": "+1 Punto Vittoria",
	"dice2_str3": "Scarta 2 Dadi della tua Riserva e aggiungi 3 Forza", "sup2_titan": "Scarta 2 Carte Supporto: lancia 1 Dado Titano",
	"foe_discard": "L'avversario scarta 1 Carta Supporto", "look_discard": "Guarda le Carte Supporto dell'avversario e scartane 1",
	"take_discard": "Prendi 1 carta dalla pila degli scarti Supporto", "move_in": "Scarta 1 Carta Supporto e muovi 1 Unità da una Regione adiacente nella Battaglia",
	"foe_move_out": "L'avversario sposta 1 sua Unità fuori dalla Battaglia, in una Regione che controlla",
	"deploy_F": "Schiera 1 Fanteria in una Regione controllata", "move_F": "Muovi 1 Fanteria in una Regione adiacente che controlli",
	"win_str": "Se hai vinto, la tua Forza aumenta di 1",
	"reroll2": "Scarta 1 Carta Supporto per ritirare i Dadi della tua Riserva, due volte",
}
const FREQ_TEXT := {"round": "Una volta per Round", "battaglia": "Una volta per Battaglia", "turno": "Una volta per turno"}


static func nation_card(nat: String, i: int) -> Dictionary:
	return NATION_CARDS[nat][i]


static func nation_card_text(nat: String, i: int) -> String:
	var c: Dictionary = NATION_CARDS[nat][i]
	var t: String = WHEN_TEXT[c["when"]]
	var req: Array = c["req"]
	if not req.is_empty():
		var parts := []
		for r in req:
			parts.append(REQ_TEXT[r])
		t += ", se " + " e ".join(parts)
	t += ": " + EFF_TEXT[c["eff"]] + ". " + FREQ_TEXT[c["freq"]] + "."
	return t


static func support_text(i: int) -> String:
	var c: Dictionary = SUPPORT[i]
	var req: Array = c["req"]
	var who := "la tua Armata ha" if req[0] == "own" else "l'Armata avversaria ha"
	var t := "Requisito: %s %s. " % [who, ("il Titano" if req[1] == "T" else "almeno 1 " + UNIT_NAME[req[1]])]
	match c["kind"]:
		"dado": t += "Effetto: +1 Dado Fanteria; in coppia (2 carte «Aggiungi un Dado») +1 Dado Titano."
		"forza": t += "Effetto: +1 Forza; in coppia +3, in tris +5."
		"muovi": t += "Effetto: muovi 1 tua Unità da una Regione adiacente nella Battaglia e lancia il suo Dado (1 per Battaglia)."
	return t


# ---------------------------------------------------------------- Modalità Solitario: l'Automa
## Azioni: [tipo, obiettivo]. Tipi: rec_F (recluta 1 Fanteria), rec_X (recluta l'Unità più forte disponibile:
## Artiglieria, poi Cavalleria, poi Fanteria), cap (Movimento verso la Capitale del giocatore), exp (Movimento
## d'Espansione), buy (acquista una Carta Nazione). Obiettivi: big (Armata più grande), small (Armata più
## piccola), arty (Armata con Artiglieria), titan (Armata con il Titano), capA (Regione con la Capitale
## dell'Automa), free (Regione libera controllata dall'Automa). "adv" = azioni della difficoltà Avanzata (stella).
## d = Carta Ordini da scartare (posizione I–IV nell'Area degli Ordini). Ordine = assets/carte/automaNN.jpg.

const AUTOMA_CARDS := [
	{"a": [["rec_X", "small"], ["cap", "arty"]], "adv": [["rec_F", "free"]], "d": 1},
	{"a": [["exp", "arty"], ["rec_F", "free"]], "adv": [["buy", ""]], "d": 2},
	{"a": [["cap", "big"], ["exp", "small"], ["rec_F", "free"]], "adv": [], "d": 3},
	{"a": [["exp", "big"], ["cap", "small"], ["buy", ""]], "adv": [], "d": 2},
	{"a": [["exp", "big"], ["cap", "small"], ["rec_F", "free"]], "adv": [], "d": 1},
	{"a": [["cap", "titan"], ["rec_F", "free"]], "adv": [["exp", "arty"]], "d": 1},
	{"a": [["rec_X", "small"], ["exp", "titan"]], "adv": [["cap", "small"]], "d": 4},
	{"a": [["rec_X", "small"], ["cap", "titan"]], "adv": [["exp", "arty"]], "d": 3},
	{"a": [["cap", "big"], ["exp", "small"], ["buy", ""]], "adv": [], "d": 4},
	{"a": [["rec_F", "capA"], ["cap", "big"], ["exp", "small"]], "adv": [], "d": 3},
	{"a": [["rec_X", "capA"], ["cap", "big"], ["exp", "small"]], "adv": [], "d": 4},
	{"a": [["cap", "titan"], ["buy", ""]], "adv": [["rec_X", "small"]], "d": 2},
]
const AUTOMA_TARGET := {"big": "l'Armata più grande", "small": "l'Armata più piccola", "arty": "l'Armata con l'Artiglieria",
	"titan": "l'Armata con il Titano", "capA": "la Regione della Capitale dell'Automa", "free": "una Regione libera controllata dall'Automa"}
## Carte Nazione che l'Automa rimette nella scatola (simbolo del Solitario).
const SOLO_REMOVE := {"pol": [0, 1, 8], "rus": [1, 2, 9], "sve": [0, 2, 8], "ott": [0, 1, 7], "sri": [3, 5, 6]}


static func automa_action_text(act: Array) -> String:
	match act[0]:
		"rec_F": return "Recluta 1 Fanteria in " + AUTOMA_TARGET[act[1]]
		"rec_X": return "Recluta l'Unità più forte disponibile in " + AUTOMA_TARGET[act[1]]
		"cap": return "Muovi " + AUTOMA_TARGET[act[1]] + " verso la tua Capitale"
		"exp": return "Movimento d'Espansione con " + AUTOMA_TARGET[act[1]]
		"buy": return "Acquista una Carta Nazione"
	return "?"


# ---------------------------------------------------------------- Obiettivi Segreti
## kind e parametri usati dal motore; vp = Punti Vittoria.

const OBJECTIVES := [
	{"vp": 2, "kind": "nation_cards_battle", "n": 4, "text": "Usa almeno 4 Carte Nazione in una sola Battaglia."},
	{"vp": 2, "kind": "win_no_support", "text": "Vinci una Battaglia senza giocare Carte Supporto (né per le abilità né per ritirare i Dadi)."},
	{"vp": 1, "kind": "units_on_board", "n": 12, "text": "Abbi 12 Unità schierate sul tabellone."},
	{"vp": 1, "kind": "two_battles", "text": "Inizia 2 Battaglie nello stesso turno."},
	{"vp": 1, "kind": "def_smaller_win", "text": "Difenditi con un'Armata più piccola di quella avversaria e vinci la Battaglia."},
	{"vp": 1, "kind": "att_smaller_win", "text": "Attacca con un'Armata più piccola di quella avversaria e vinci la Battaglia."},
	{"vp": 2, "kind": "regions", "n": [10, 9, 8], "text": "Controlla 10 Regioni (9 in 3 giocatori, 8 in 4 giocatori)."},
	{"vp": 1, "kind": "central_and_neigh", "n": [3, 2, 2], "text": "Controlla la Regione Centrale e 3 Regioni adiacenti a essa (2 in 3 o 4 giocatori)."},
	{"vp": 1, "kind": "att_smaller_win", "text": "Attacca con un'Armata più piccola di quella avversaria e vinci la Battaglia."},
	{"vp": 1, "kind": "token_regions", "n": 5, "text": "Controlla 5 Regioni solo con i tuoi Segnalini Controllo."},
	{"vp": 1, "kind": "two_big_armies", "text": "Mantieni 2 Armate di almeno 4 Unità dalla fine del tuo turno alla fine del tuo turno successivo."},
	{"vp": 2, "kind": "central_one_unit", "text": "Controlla la Regione Centrale con 1 sola Unità dalla fine del tuo turno alla fine del tuo turno successivo."},
	{"vp": 2, "kind": "support_cards_battle", "n": 6, "text": "Usa 6 Carte Supporto per le loro abilità in una sola Battaglia."},
	{"vp": 1, "kind": "only_type_regions", "u": "K", "n": 2, "text": "Controlla 2 Regioni solo con Unità di Cavalleria."},
	{"vp": 1, "kind": "only_type_regions", "u": "F", "n": 4, "text": "Controlla 4 Regioni solo con Unità di Fanteria."},
	{"vp": 2, "kind": "enemy_start", "n": 2, "text": "Controlla 2 Regioni che erano Regioni di partenza di altri giocatori."},
	{"vp": 2, "kind": "enemy_start_neigh", "n": 3, "text": "Controlla 3 Regioni adiacenti alle Regioni di partenza di altri giocatori."},
	{"vp": 2, "kind": "win_no_support", "text": "Vinci una Battaglia senza giocare Carte Supporto (né per le abilità né per ritirare i Dadi)."},
	{"vp": 2, "kind": "win_vs_titan_central", "text": "Vinci una Battaglia nella Regione Centrale contro un'Armata con il Titano."},
	{"vp": 1, "kind": "win_central", "text": "Vinci una Battaglia nella Regione Centrale."},
	{"vp": 2, "kind": "win_foe_2nc", "text": "Vinci una Battaglia in cui l'avversario ha usato almeno 2 Carte Nazione."},
	{"vp": 1, "kind": "win_diff", "n": 7, "text": "Vinci una Battaglia con una differenza di Forza di almeno 7."},
	{"vp": 2, "kind": "win_only_titan", "text": "Vinci una Battaglia con il solo Titano."},
	{"vp": 2, "kind": "win_no_titan_vs_titan", "text": "Vinci una Battaglia con un'Armata senza Titano contro un'Armata con il Titano."},
]

# ---------------------------------------------------------------- espansioni Kickstarter
## Monumenti: 3 per Nazione. Il costo è il numero romano della carta (I, II, III) in Carte Supporto.
## when: "turno" = una volta per turno a scelta; "auto" = si applica da sé; "dopo_a", "dopo_c", "dopo_d" =
## dopo quella fase; "battaglia" = una volta per Battaglia; "sempre" = effetto continuo.
const MONUMENTS := {
	"pol": [
		{"key": "town_pol", "name": "Municipio", "cost": 1, "when": "turno", "text": "Una volta per turno: scarta 1 Carta Supporto e schiera 1 Fanteria nella Regione del Monumento, oppure scambia lì 1 Fanteria con 1 Cavalleria."},
		{"key": "cath_pol", "name": "Cattedrale", "cost": 2, "when": "sempre", "after_d": true, "text": "+1 PV subito dopo aver preso il controllo di ogni Regione adiacente al Monumento. Si costruisce solo dopo la Fase D."},
		{"key": "castle_pol", "name": "Castello Reale", "cost": 3, "when": "auto", "text": "Una volta per turno: pesca 1 Carta Supporto se controlli al massimo 2 Regioni adiacenti al Monumento."},
	],
	"rus": [
		{"key": "sofia", "name": "Cattedrale di Santa Sofia", "cost": 1, "when": "sempre", "border": true, "text": "Si piazza sul confine fra 2 Regioni, una delle quali tua: nessuna Unità può attraversare quel confine. A fine Round, finché è sulla mappa, +1 PV."},
		{"key": "basil", "name": "Cattedrale di San Basilio", "cost": 2, "when": "auto", "text": "Una volta per turno: se controlli 4 o più Regioni confinanti con quella del Monumento, pesca 1 Carta Supporto."},
		{"key": "spass", "name": "Torre di Spasskaja", "cost": 3, "when": "sempre", "text": "Le Unità che muovi dalla Regione del Monumento possono spostarsi di 1 Regione in più; in tal caso il primo passo non può entrare in una Regione controllata da un avversario."},
	],
	"sve": [
		{"key": "town_sve", "name": "Municipio", "cost": 1, "when": "turno", "text": "Una volta per turno: scarta 1 Carta Supporto e schiera 1 Fanteria nella Regione del Monumento."},
		{"key": "cath_sve", "name": "Cattedrale", "cost": 2, "when": "sempre", "text": "Ogni volta che prendi il controllo di una Regione adiacente al Monumento, pesca 2 Carte Supporto."},
		{"key": "kronor", "name": "Castello di Tre Kronor", "cost": 3, "when": "dopo_d", "text": "Dopo la Fase D puoi muovere 1 Unità dalla Regione del Monumento o da una adiacente, ma non in una Regione con Unità nemiche."},
	],
	"ott": [
		{"key": "topkapi", "name": "Palazzo di Topkapi", "cost": 1, "when": "dopo_a", "text": "Dopo la Fase A puoi muovere 1 Cavalleria dalla Regione del Monumento o da una adiacente; il movimento può iniziare una nuova Battaglia."},
		{"key": "jan", "name": "Tenda dei Giannizzeri", "cost": 2, "when": "auto", "text": "Una volta per turno: +1 PV se controlli 5 o più Regioni adiacenti alla Regione del Monumento."},
		{"key": "mosque", "name": "Moschea Blu", "cost": 3, "when": "dopo_c", "no_start": true, "text": "Dopo la Fase C: metti sotto il Monumento la prima Carta Supporto del mazzo, oppure prendi tutte quelle che ci sono sotto. Non si costruisce nelle Regioni di partenza."},
	],
	"sri": [
		{"key": "stefan", "name": "Cattedrale di Santo Stefano", "cost": 1, "when": "sempre", "text": "Pesca 2 Carte Supporto dopo che una Battaglia nella Regione del Monumento o in una adiacente ha eliminato una o più Unità."},
		{"key": "schon", "name": "Castello di Schönbrunn", "cost": 2, "when": "dopo_c", "text": "Dopo la Fase C: +1 PV se almeno 2 Regioni adiacenti al Monumento sono controllate da avversari."},
		{"key": "town_sri", "name": "Municipio", "cost": 3, "when": "battaglia", "text": "In una Battaglia nella Regione del Monumento o in una adiacente puoi giocare gratis 1 delle prime 3 Carte Nazione del tuo mazzo, solo per quella Battaglia; poi va in fondo al mazzo."},
	],
}

## Emissari del Re: segnalini che accompagnano un'Armata e la aiutano in Battaglia.
const EMISSARIES := {
	"F2": "Aggiungi 2 Dadi Fanteria",
	"K1": "Aggiungi 1 Dado Cavalleria",
	"draw": "Pesca 1 Carta Supporto",
	"max": "Porta 1 Dado al valore massimo",
	"vp": "Se vinci la Battaglia: +1 PV",
}
const EMISSARY_KEYS := ["F2", "K1", "draw", "max", "vp"]

## Obiettivi Nazione (Emissari del Re), 3 per Nazione.
const NATION_OBJECTIVES := {
	"pol": [
		{"kind": "win_only_K", "text": "Vincere una Battaglia solo con Unità di Cavalleria."},
		{"kind": "start_neigh_all", "text": "Controllare tutte le Regioni adiacenti alle proprie Regioni di partenza."},
		{"kind": "win_no_cards", "text": "Vincere una Battaglia senza usare Carte Supporto né Carte Nazione."},
	],
	"rus": [
		{"kind": "win_central", "text": "Vincere una Battaglia nella Regione Centrale."},
		{"kind": "win_empty_hand", "text": "Vincere una Battaglia senza Carte Supporto in mano."},
		{"kind": "all_F", "text": "Avere tutte le Unità di Fanteria schierate sul Tabellone."},
	],
	"sve": [
		{"kind": "win_only_F", "text": "Vincere una Battaglia solo con Unità di Fanteria."},
		{"kind": "wipe", "text": "Eliminare tutte le Unità avversarie in una Battaglia."},
		{"kind": "tokens_plus2", "text": "Controllare con Segnalini Controllo 2 Regioni in più rispetto a quelle controllate dalle proprie Unità."},
	],
	"ott": [
		{"kind": "win_only_A", "text": "Vincere una Battaglia solo con Unità di Artiglieria."},
		{"kind": "win_capital", "text": "Vincere una Battaglia in una Regione con una Capitale."},
		{"kind": "near_titan3", "text": "Controllare 3 o più Regioni adiacenti a una o più Regioni con un Titano nemico."},
	],
	"sri": [
		{"kind": "dice8", "text": "Utilizzare tutti e 8 i Dadi Battaglia in una Battaglia."},
		{"kind": "nc5", "text": "Utilizzare almeno 5 Carte Nazione in una Battaglia."},
		{"kind": "all_K", "text": "Avere tutte le Unità di Cavalleria schierate sul Tabellone."},
	],
}
## Ricompense degli Obiettivi Nazione: il 1° dà un Emissario, il 2° 3 PV, il 3° 5 PV.
const NOBJ_VP := [0, 3, 5]


static func monument(nat: String, i: int) -> Dictionary:
	return MONUMENTS[nat][i]


# ---------------------------------------------------------------- mappa e scenari

static var _map := {}
static var _scen: Array = []


static func map_data(side: String) -> Dictionary:
	if _map.is_empty():
		var f := FileAccess.open("res://data/mappa.json", FileAccess.READ)
		_map = JSON.parse_string(f.get_as_text())
	return _map[side]


static func scenarios() -> Array:
	if _scen.is_empty():
		var f := FileAccess.open("res://data/scenari.json", FileAccess.READ)
		_scen = JSON.parse_string(f.get_as_text())
	return _scen


static func scenarios_for(n: int, with_exp := true) -> Array:
	var out := []
	for s in scenarios():
		if not with_exp and s.has("expansion"):
			continue
		if s.get("solo", false):
			continue
		if (s["nations"] as Array).size() == n:
			out.append(s)
	return out


static func solo_scenarios() -> Array:
	var out := []
	for s in scenarios():
		if s.get("solo", false):
			out.append(s)
	return out


static func scenario(id: String) -> Dictionary:
	for s in scenarios():
		if s["id"] == id:
			return s
	return {}


static func scenario_label(s: Dictionary) -> String:
	var names := []
	for c in s["nations"]:
		names.append(NATIONS[CODE_TO_NATION[c]]["short"])
	return "Scenario %s — %s (lato %s)" % [s["id"], ", ".join(names), s["side"]]
