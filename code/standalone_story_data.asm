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
    ; --- Page 1 (8 lines, rows 8..15) ---
    DEFB 8, "Sir Tharkys is a man", 0
    DEFB 9, "with bad luck.", 0
    DEFB 10, "For a long time he wrote", 0
    DEFB 11, "checks his body could not", 0
    DEFB 12, "cash. His squire has", 0
    DEFB 13, "abandoned him.", 0
    DEFB 14, "Even his horse has", 0
    DEFB 15, "abandoned him.", 0
    DEFB $FE                ; end of page 1
    ; --- Page 2 (5 lines, rows 9..13) ---
    DEFB 9, "He has no choice but", 0
    DEFB 10, "to go wherever a sword", 0
    DEFB 11, "is needed, hoping for", 0
    DEFB 12, "a few scraps in return", 0
    DEFB 13, "for his services.", 0
    DEFB $FE                ; end of page 2
    ; --- Page 3 (8 lines, rows 8..15) ---
    DEFB 8, "Word reached him of a", 0
    DEFB 9, "village living in terror", 0
    DEFB 10, "of monsters of unknown", 0
    DEFB 11, "origin. To whoever freed", 0
    DEFB 12, "them, they promised a", 0
    DEFB 13, "handsome reward that", 0
    DEFB 14, "would lift the knight out", 0
    DEFB 15, "of his financial troubles.", 0
    DEFB $FE                ; end of page 3
    ; --- Page 4 (9 lines, rows 7..15) ---
    DEFB 7, "After speaking with the", 0
    DEFB 8, "mayor, the latter hands", 0
    DEFB 9, "him a broken compass", 0
    DEFB 10, "that will vaguely show", 0
    DEFB 11, "the location of his", 0
    DEFB 12, "targets. He also mentions", 0
    DEFB 13, "a map on a napkin (!?!),", 0
    DEFB 14, "but the wind blew it", 0
    DEFB 15, "away (!!??!!).", 0
    DEFB $FE                ; end of page 4
    ; --- Page 5 (6 lines, rows 9..14) ---
    DEFB 9, "He wishes him good luck", 0
    DEFB 10, "and, as a parting note,", 0
    DEFB 11, "informs him they have", 0
    DEFB 12, "locked the town gate so", 0
    DEFB 13, "he cannot give in to the", 0
    DEFB 14, "temptation of fleeing.", 0
    DEFB $FE                ; end of page 5
    ; --- Page 6 (7 lines, rows 8..14) ---
    DEFB 8, "He feels like doing just", 0
    DEFB 9, "that, after seeing the", 0
    DEFB 10, "place crawling with", 0
    DEFB 11, "creatures and, above all,", 0
    DEFB 12, "after learning that many", 0
    DEFB 13, "knights have already", 0
    DEFB 14, "fallen trying...", 0
    DEFB $FE                ; end of page 6
    DEFB $FF                ; end of StoryPagesEN

StoryPagesES:
    ; --- Page 1 (9 lines, rows 7..15) ---
    DEFB 7, "Sir Tharkys es un tipo", 0
    DEFB 8, "con mala suerte.", 0
    DEFB 9, "Durante mucho tiempo", 0
    DEFB 10, "extendi", $83, " cheques que su", 0
    DEFB 11, "cuerpo no pod", $82, "a pagar.", 0
    DEFB 12, "Su escudero le ha", 0
    DEFB 13, "abandonado. Le ha", 0
    DEFB 14, "abandonado hasta", 0
    DEFB 15, "su caballo.", 0
    DEFB $FE                ; end of page 1
    ; --- Page 2 (5 lines, rows 9..13) ---
    DEFB 9, "No le queda m", $80, "s remedio", 0
    DEFB 10, "que ir all", $80, " donde se", 0
    DEFB 11, "requiera una espada,", 0
    DEFB 12, "esperando algunas migajas", 0
    DEFB 13, "a cambio de sus servicios.", 0
    DEFB $FE                ; end of page 2
    ; --- Page 3 (9 lines, rows 7..15) ---
    DEFB 7, "Le llegaron noticias", 0
    DEFB 8, "de un pueblo que vive", 0
    DEFB 9, "atemorizado por unos", 0
    DEFB 10, "monstruos de origen", 0
    DEFB 11, "desconocido.", 0
    DEFB 12, "A quien les liberara,", 0
    DEFB 13, "promet", $82, "an entregar una", 0
    DEFB 14, "jugosa recompensa que le", 0
    DEFB 15, "sacar", $82, "a de sus apuros.", 0
    DEFB $FE                ; end of page 3
    ; --- Page 4 (10 lines, rows 7..16) ---
    DEFB 7, "Tras hablar con el", 0
    DEFB 8, "alcalde, ", $81, "ste le entrega", 0
    DEFB 9, "una br", $84, "jula rota que", 0
    DEFB 10, "le indicar", $80, " vagamente", 0
    DEFB 11, "la ubicaci", $83, "n de sus", 0
    DEFB 12, "objetivos. Tambi", $81, "n dice", 0
    DEFB 13, "que ten", $82, "a un mapa en", 0
    DEFB 14, "una servilleta (!?!),", 0
    DEFB 15, "pero se lo llev", $83, 0
    DEFB 16, "el aire (!!??!!).", 0
    DEFB $FE                ; end of page 4
    ; --- Page 5 (6 lines, rows 9..14) ---
    DEFB 9, "Le desea buena suerte", 0
    DEFB 10, "y, como despedida, avisa", 0
    DEFB 11, "que han cerrado la puerta", 0
    DEFB 12, "de la ciudad para que no", 0
    DEFB 13, "ceda a la tentaci", $83, "n", 0
    DEFB 14, "de huir.", 0
    DEFB $FE                ; end of page 5
    ; --- Page 6 (7 lines, rows 8..14) ---
    DEFB 8, "Ganas le dan, tras ver", 0
    DEFB 9, "c", $83, "mo est", $80, " todo lleno", 0
    DEFB 10, "de bichos y, sobre todo,", 0
    DEFB 11, "tras conocer que muchos", 0
    DEFB 12, "otros caballeros", 0
    DEFB 13, "han ca", $82, "do antes", 0
    DEFB 14, "en el intento...", 0
    DEFB $FE                ; end of page 6
    DEFB $FF                ; end of StoryPagesES

