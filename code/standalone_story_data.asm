; ==============================================================================
; standalone_story_data.asm - 6 paginas EN + 6 paginas ES (F4)
; ==============================================================================
; Auto-generado por tools/build_standalone_story.py. NO editar a mano: cambios
; perderan en el siguiente build. Para modificar el texto, editar las listas
; STORY_ES / STORY_EN en el script Python y volver a ejecutarlo.
;
; Formato consumido por StandaloneStoryShow:
;   Cada pagina: secuencia de {row(1B), char*, 0}, terminada por $FE
;   Historia completa terminada por $FF
;
; Codepoints 0x80-0x8B = a-acute, e-acute, i-acute, o-acute, u-acute,
;                       A-acute, E-acute, I-acute, O-acute, U-acute, n-tilde, N-tilde
; ==============================================================================

StoryPagesEN:
    ; --- Page 1 (9 lines, rows 3..19 step 2) ---
    DEFB 3, "Sir Tharkys is a man", 0
    DEFB 5, "with bad luck.", 0
    DEFB 7, 0
    DEFB 9, "For a long time he wrote", 0
    DEFB 11, "checks his body could not", 0
    DEFB 13, "cash. His squire has", 0
    DEFB 15, "abandoned him.", 0
    DEFB 17, "Even his horse has", 0
    DEFB 19, "abandoned him...", 0
    DEFB $FE                ; end of page 1
    ; --- Page 2 (5 lines, rows 7..15 step 2) ---
    DEFB 7, "He has no choice but", 0
    DEFB 9, "to go wherever a sword", 0
    DEFB 11, "is needed, hoping for", 0
    DEFB 13, "a few scraps in return", 0
    DEFB 15, "for his services.", 0
    DEFB $FE                ; end of page 2
    ; --- Page 3 (10 lines, rows 2..20 step 2) ---
    DEFB 2, "Word reached him of a", 0
    DEFB 4, "village living in terror", 0
    DEFB 6, "of monsters of unknown", 0
    DEFB 8, "origin. ", 0
    DEFB 10, 0
    DEFB 12, "To whoever freed them,", 0
    DEFB 14, " they promised a", 0
    DEFB 16, "handsome reward that", 0
    DEFB 18, "would lift the knight out", 0
    DEFB 20, "of his financial troubles.", 0
    DEFB $FE                ; end of page 3
    ; --- Page 4 (9 lines, rows 3..19 step 2) ---
    DEFB 3, "After speaking with the", 0
    DEFB 5, "mayor, the latter hands", 0
    DEFB 7, "him a broken compass", 0
    DEFB 9, "that will vaguely show", 0
    DEFB 11, "the location of his", 0
    DEFB 13, "targets. He also mentions", 0
    DEFB 15, "a map on a napkin (!?!),", 0
    DEFB 17, "but the wind blew it", 0
    DEFB 19, "away (!!??!!).", 0
    DEFB $FE                ; end of page 4
    ; --- Page 5 (6 lines, rows 6..16 step 2) ---
    DEFB 6, "He wishes him good luck", 0
    DEFB 8, "and, as a parting note,", 0
    DEFB 10, "informs him they have", 0
    DEFB 12, "locked the town gate so", 0
    DEFB 14, "he cannot give in to the", 0
    DEFB 16, "temptation of fleeing.", 0
    DEFB $FE                ; end of page 5
    ; --- Page 6 (7 lines, rows 5..17 step 2) ---
    DEFB 5, "He feels like doing just", 0
    DEFB 7, "that, after seeing the", 0
    DEFB 9, "place crawling with", 0
    DEFB 11, "creatures and, above all,", 0
    DEFB 13, "after learning that many", 0
    DEFB 15, "knights have already", 0
    DEFB 17, "fallen trying...", 0
    DEFB $FE                ; end of page 6
    DEFB $FF                ; end of StoryPagesEN

StoryPagesES:
    ; --- Page 1 (9 lines, rows 3..19 step 2) ---
    DEFB 3, "Sir Tharkys es un tipo", 0
    DEFB 5, "con mala suerte.", 0
    DEFB 7, 0
    DEFB 9, "Durante mucho tiempo", 0
    DEFB 11, "extendi", $83, " cheques que su", 0
    DEFB 13, "cuerpo no pod", $82, "a pagar.", 0
    DEFB 15, "Su escudero le ha abandonado.", 0
    DEFB 17, " Le ha abandonado", 0
    DEFB 19, "hasta su caballo...", 0
    DEFB $FE                ; end of page 1
    ; --- Page 2 (5 lines, rows 7..15 step 2) ---
    DEFB 7, "No le queda m", $80, "s remedio", 0
    DEFB 9, "que ir all", $80, " donde", 0
    DEFB 11, "se requiera una espada,", 0
    DEFB 13, "esperando algunas migajas", 0
    DEFB 15, "a cambio de sus servicios.", 0
    DEFB $FE                ; end of page 2
    ; --- Page 3 (10 lines, rows 2..20 step 2) ---
    DEFB 2, "Le llegaron noticias de un ", 0
    DEFB 4, "pueblo que vive atemorizado", 0
    DEFB 6, " por unos monstruos ", 0
    DEFB 8, "de origen desconocido.", 0
    DEFB 10, 0
    DEFB 12, "A quien les liberara de ", 0
    DEFB 14, "ellos, promet", $82, "an entregar ", 0
    DEFB 16, "una jugosa recompensa ", 0
    DEFB 18, "que sacar", $82, "a a Tharkys ", 0
    DEFB 20, "de sus apuros econ", $83, "micos.", 0
    DEFB $FE                ; end of page 3
    ; --- Page 4 (9 lines, rows 3..19 step 2) ---
    DEFB 3, "Tras hablar con el", 0
    DEFB 5, "alcalde, ", $81, "ste le entrega", 0
    DEFB 7, "una br", $84, "jula rota que", 0
    DEFB 9, "le indicar", $80, " vagamente", 0
    DEFB 11, "la ubicaci", $83, "n de sus", 0
    DEFB 13, "objetivos. Tambi", $81, "n dice", 0
    DEFB 15, "que ten", $82, "a un mapa en", 0
    DEFB 17, "una servilleta (!?!),", 0
    DEFB 19, "pero se lo llev", $83, " el aire (!??!).", 0
    DEFB $FE                ; end of page 4
    ; --- Page 5 (5 lines, rows 7..15 step 2) ---
    DEFB 7, "Le desea buena suerte", 0
    DEFB 9, "y, como despedida, le informa", 0
    DEFB 11, "de que han cerrado la puerta", 0
    DEFB 13, "de la ciudad para que no pueda", 0
    DEFB 15, "ceder a la tentaci", $83, "n de huir.", 0
    DEFB $FE                ; end of page 5
    ; --- Page 6 (6 lines, rows 6..16 step 2) ---
    DEFB 6, "Ganas le dan, tras ver", 0
    DEFB 8, "c", $83, "mo est", $80, " todo lleno", 0
    DEFB 10, "de bichos y, sobre todo,", 0
    DEFB 12, "tras conocer que muchos otros", 0
    DEFB 14, " caballeros han ca", $82, "do antes", 0
    DEFB 16, " en el intento...", 0
    DEFB $FE                ; end of page 6
    DEFB $FF                ; end of StoryPagesES

