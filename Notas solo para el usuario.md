ctrl f6 exe
ctrlf7 memory map


AJUSTES:


Cinemática de la Iglesia: que cuando el borde se pone blanco al romperse la estatua del monster, Suene un sonido como de trueno. Que tras matar al último monster, tras un instante de alivio suene una musiquita triunfal antes de aparecer el cheque

Que cuando reciba daño el borde se ponga amarillo un instante. 

Cuando muera el borde se ponga rojo mientras cae Después vuelva a negro

Entre pantallas podría recordar si había un random pickup Health o estamina concreto que siga habiendo ese mismo.

BUGS
    
    Cuando estoy atacando con la espada y voy a pasar de a la pantalla izquierda OA la derecha a veces invade los background sprites inferiores del límite de la pantalla de la que voy a salir. 

    En alguna rara ocasión, los monsters aparecen en un gap norte y empiezan a moverse directamente hacia un lado ocupado por background sprites. 

    En ocasiones las agujas del reloj del HUD parpadean de manera muy molesta. 

    Las decoraciones izquierdas del hud del reloj, las que marcan la salud, a veces se pintan mal. Solo afecta a las que están decaídas. No afecta a las iniciales. Las iniciales sanas se pintan bien.
    
HACER MÚSICAS:

    Mission accomplished: green sleeves en tonalidad mayor y con ritmo de paso de caballo del oeste

    Game over????

MEJORAS: 


    Bgsrites
        
        Intentar hacer casas medievales

        Remolino de hojas para spawn nastis nocturnos. El actual es una mierda.  

    Diseño rooms:

 
        Aumentar variedad?

OTROS:
    

HISTORIA: 

    Sir Tharkys es un tipo con mala suerte. Durante mucho tiempo extendió cheques que su cuerpo no pudo pagar. Se ha quedado sin escudero. Se ha quedado hasta sin caballo. No le queda más remedio que ir allá donde se requiera una espada, esperando algunas migajas por sus servicios. Le llegaron noticias de un pueblo que vive atemorizado por unos monstruos de origen desconocido. A quien les librara de ellos, prometían enrtegar una jugosa recompensa que sacaría al caballero de sus problemas financieros. Tras hablar con el alcalde, éste le entrega una brújula rota que le indicará vagamente la ubicación de sus objetivos. Como despedida, le informa de que han cerrado la puerta de la ciudad para que no pueda ceder a la tentación de huir. Ganas le dan, tras conocer que muchos han caído antes en el intento... 

SISTEMA DE DIFICULTAD:

    Número de vidas al empezar
    Número de Nastis 3 o 4 
    Regeneración o no de salud y estamina. 
    Velocidad Inicial de nastis. 
    Velocidad inicial de Monsters. 
    los monsters aparezcan más rápido cuando cambio de pantalla
    Menor tiempo de aparición y de lanzamiento de la muerte. 
    Menor frecuencia de aparición de Pickups buenos. 
    brújula mágica. ¿nerfear su uso de alguna manera? 

        si coge cualquier otra cosa la anule
        O que dure menos. 
        O que no pueda disparar
        O que salga menos probabilidad.
        O que salga solo en la ruleta


PRESENTACIÓN

    Your challenge?

REMATES:

    Ir quitando los debuggers

    Organizar el HUD


- [x ] **Hit del jugador** — déjate tocar por un monstruo
      → hit corto descendente (agudo → grave, ~160 ms)

- [x] **Muerte del jugador** — déjate matar (HP a 0)
      → sweep largo agudo → muy grave (~1 s)

- [NO] **Pickup compass random** — recoge un magic compass normal
      → sweep ascendente corto (grave → agudo, ~640 ms)

- [x] **Pickup compass lasting** — recoge el compass permanente
      → sweep ascendente largo + PIN agudo final (~1.1 s)

- [x] **Victory fanfare** — atrapa los 3 monstruos en la iglesia (M7)
      → fanfarria larga ascendente + PIN agudo (~1.5 s)

- [x] **Countdown tick** (beats 1–3) — muere y espera al respawn
      → 3 pitidos cortos D5 (~569 Hz, ~160 ms cada uno)

- [x] **Countdown GO** (beat 4) — final del respawn countdown
      → 1 pitido más largo D6 (~1139 Hz, ~440 ms)

- [x] **Compass tick** — coge un compass y deja pasar el tiempo
      → pequeño tic D5 cada segundo aprox

- [MAL] **Música monstruos "po-po-popo-po"** — cuando hay monstruos activos
      → percusión grave C2 staccato en el patrón rítmico

- [x] **Bank cutscene "no-no"** — escena del banco (M9), cuando dice "no"
      → dos tonos alternos high/low (~318 Hz / ~252 Hz, 240 ms cada uno)

- [x] **Bank cutscene knocks** — los toques a la puerta del banco (M9)
      → golpes percusivos con ruido + HW envelope
      (grupos: 3 soft sin tone, luego 6 loud con tone grave)


Aumentar un poco la dificultad: demasiadas vidas? La salud y la estamina deberían ir bajando un poco?

Monstruos: que al perseguirme a otra sala aparezca un poco más rápido el primero y luego los demás detrás del primero con su cadencia actual

Monstruos : que cuando les expulse de una sala con el knockback tarden un poquito más en volver a entrar en ella. 

En el wrapper, 

    Hay que cambiar la letra de pausa P porque es una tecla de movimiento

    Que empiece maximizado o a pantalla completa 

Crear más variedad de sprites urbanos y por tanto de cementerio y de bosque y de ruinas 