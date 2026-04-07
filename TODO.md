# TODO

## Bugs
- [ ] En ocasiones, cuando estoy sobre un tejado rojo. Al ponerme yo rojo, se Invierten los atributos de las bg sprite cells superiores cellsdel tejado. 
- [ ]
- [ ]
- [ ]
- [ ]

-ENEMIGOS EN GENERAL
    Dejan rastros de atributos que contaminan a otros enemigos y al player
    Cuando están en modo scare a veces se quedan atrapados según la ubicación de los bg sprites. Que busquen una salida!
    Que si no han sido capaces de salir, que despawneen
    a veces solapan con el pozo o con bg sprites menores, como el bench

HUD

    A veces no se dibujan bien los adornos decaying del reloj. Otras veces se dibujan bien

- [ ] Monsters: 
    - [x] monsters deben empujarse mejor
    - [X] deben morir tras la pausa del knockback (o al darse con el límite de la pantalla) si llevan 5 golpes. Aparecerá otro en una posición random
    - [?] a veces no hace knockback, a pesar de haber direcciones disponibles
    - [x] cuando los echo a la derecha, siempre mueren, en lugar de irse a la room de la derecha   
    - [x] revisa la consistencia de los golpes. Estás seguro de que solo reciben uno por cada ciclo de animación de attack?
    - [x] que fleen igual que los nasties cuando llega el amanecer1
    
    - [ ] Un sprite de 2 * 1 con humo de daño en el lado del player desde donde va a ser proyectado el monster
    - [ ] WIP: al salir de la pantalla o al entrar podrían dibujarse hasta desaparecer o hasta aparecer del todo? (si funciona, probar con el player). Actualmente no funciona bien. No terminan de seguirme siempre, creo que puede deberse a que si aparecen el la fila contraria por el clipping entonces aparecen por el lado contrario y vienen a mi desde el frente
    - [ ] BUG:Pero te has cargado que si lo he empujado y entro enseguida, debería estar allí esperándome!!!
    También veo una reducción en la performance. No sé en cual de Las fases ha ocurrido. Haz una auditoría de las posibles optimizaciones, sobre las colisiones de los monsters (por ejemplo revisa lo que hicimos con los nasties y mira si puedes reaprovechar alguna rutina). 
    

- [ ] player: 
    - [x] Me gustaría que, Cuando inicio un ataque se termine siempre de reproducir la animacion aunque me deje moverme. 
    - [x] BUG: cuando me muevo atacando, la animación de ataque es más lenta
    - [ ??] que la salida y la entrada de las rooms sea igual de suave que los monsters
    - [ ] aumentar animaciones: un frame de daño para cada orientación, dos frames de idle para cada orientación, y trabajar la animación de muerte.Cuando tenga un nivel bajo de estamina. Jadeará y Mírala a los lados, cuando esté idle 
    - [ ] La muerte del soldado. ¿Será caer de rodillas? Con el torso de la cabeza hacia atrás al estilo platoon.

- [x] La bounding box del. Soldado cuando está atacando respecto a la colisiones de daño. Sólo afectará a los sprites, a los cells, donde se encuentre el cuerpo, no la espada. 

- [x] nasties: 
    - [x] aparecer tras un momento en la pantalla nueva
    - [x] no aparecer encima del player
    - [DEPRECATED. TOO EXPENSIVE] no solaparse entre ellos: si chocan, dirección contraria cada uno
    - [x] no solaparse con el player. Si lo tocan y no están atacando, hacen daño y mueren
    - [deprecated] correr más cuando "scared"
    - [x] separar por momento del día: 
        - [x] a1 y d y c1: águila, araña, cabra (cuando coincida con la fila  se lanza horizontal), serpiente (cuando coincida con la columna se lanza vertical)
        - [x] c2 y n1 y a1: rata, murciélago, escorpión (cuando coincida con la fila  se lanza horizontal), gato rabioso (cuando coincida con la columna se lanza )
        - [ ] 
        - [ ] 
- [ ] 
- [ ] 

otros: 

- [x] que las ventanas se apaguen solo un poco después de terminar de sonar la última campanada

## Próximo
- [ ] Añadir reloj. DONE  
- [ ] Añadir enemigo tipo 2-                
- [ ] Pantalla de título
- [x] Actualizar rata   

- [ ] 

## Ideas / backlog
- [ ] Una idea muy loca: el objetivo de juego es conducir a los 3 monstruos, a la fuerza. en la iglesia. Allí mueren y el juego acaba. La cuestión es que parece demasiado fácil porque los monstruos se van todo el rato siguiendo. Conforme se acercan a la Iglesia deben querer huir de ella ya no tanto atacar al personaje. Este tendrá que perseguirlos y jugar al billar con ellos hasta que entren Y me voy a Acostar 
- [ ] Reloj en HUD [#1](https://github.com/Jay-droid133/nuevo-juego/issues/1)

- [ ] Contador de tiempo global: Day 1, Day 2...
- [ ] Valorar opción stamina


- [ ] Efectos de sonido al recoger objetos

## Hecho
- [x] Day/night cycle
- [x] Colisiones con fondo (BG)
- [x] Subir repo a GitHub


A ver más cositas sobre la idea general. La ciudad es más pequeña que sabre wulf. Bastante más pequeña. En la parte este hay un cementerio cerrado. Con una iglesia. La parte oeste hay una parte boscosa. La ciudad está rodeada de murallas y abajo en el centro está la gran puerta. El jugador la ve en su camino, pero se encuentra cerrada. La verja del cementerio tiene un cerrojo. Harán falta los 3 trozos de una llave. Cada día habrá un trozo de una llave. Escondido en la ciudad. También necesitará encontrar un crucifijo con el crucifijo. Les robirá 1 de los monstruos. El objetivo final será. Empujar a los monsters. Dentro de la Iglesia el problema es que cuando tenga el crucifijo los monsters le van a evitar y tiene a que conducirlos como ganado a hostias. Hasta el cementerio. Y hasta la puerta de la Iglesia. Cada vez que entre 1 se ilumina la puerta y las ventanas para aumentar la dificultad, la puerta de la Iglesia la tendrá que abrir él con la espada. Está abierta solo un rato luego se cerrará. Mientras esta abierta, intentará ir metiendo si puede de golpe y si no 1 a 1 a los 3 monsters. cada vez que meta 1, La puerta se cerrará la puerta flaserá en blanco y se cerrará también flasheeran en blanco las ventanas. Cuando meta el tercero flashela en blanco, la puerta se cerrará y flashearan en blanco y rojo. Indicando que ya se ha acabado el juego. Se supone que el jugador se imaginará que tiene que volver por la gran puerta de la muralla, en el sur. Y una vez que entré por ella, el. Juego, tomar control, se da la vuelta pensativo. Y por encima de su cabeza asoma una mano con el dedo. Cagándose en el pueblo. Pantalla negra y créditos. 
SISTEMA DE SALUD:

- [ ] Que el indicador de salud sea la parte izquierda del adorno del reloj. Y el de la stamina, la parte derecha. Se va borrando línea a línea, y va cambiando de color (verde, azul, amarillo, rojo, magenta, azul)
- [ ] La STAMINA tendrá tres niveles: Máximo (principio, poción): permitirá el usar la espada continuamente. Medio: permitirá el modo Fijo. Bajo: el cooldown corto. VACÍA: el cooldown largo. Debe acercarse a un pozo, recoger pociones, o matar un monster concreto. Mejor que un monstruo concreto suelte poción o cualquiera de vez en cuando
La vida se recuperará igual: POZO, pociones, un monstruo concreto. Mejor que un monstruo concreto suelte poción o, bien cualquiera de vez en cuando.

También me gustaría un indicador : DAY 1, 2, 3, 4

El juego empezará a las 7:00 H de la mañana, cuando ya es de día. Pasará ese día. Esa noche. El segundo día la segunda noche. El tercer día y la tercera noche tengo que pensar la manera de obtener Los 3 trozos de la llave y el crucifijo. 1 cada dia.Tendré que pensar la forma en que cada día un nasti al azar caer una llave al morir. ¿O cuando salga corriendo? Al dar las campanadas. Casi mejor eso. El crucifijo lo soltará Un nasti también En la tercera noche cuando dé las campanadas y se vaya corriendo Un momento: a lo mejor este enfoque desincentiva la exploración. A ver como lo hago. qué me sugieres? Ponte creativo, anda! cómo podría obligar al jugador a explorar?

El crucifijo será un arma de doble filo. Hará que los monstruos se alejen del player, con lo que habrá que conducirlos como ganado a hostias por todo el pueblo hasta el cementerio y la iglesia. Una vez en el cementerio, se moverán todavía más rápido, con lo que será muy dificil dirirlos a su muerte.


Respecto a los nastis. Habrá dos clases los que atacan desde arriba, los que atacan desde abajo y los que atacan desde los lados cada. Cada 1 se moverá a su bola, pero cuando le tengan. A tiro se echarán encima de él la. Serpiente atacará desde abajo, el águila atacará desde arriba el gato atacará desde arriba. El escorpión atacará desde abajo. La rata atacar desde abajo. La arañata cara desde arriba puedes de abajo los pozos estarán distribuidos por la ciudad, habrá pocos y reinicien harán completamente la salud y las lactamina. La estamina. En total serán. El juego empezará a las 7:00 H de la mañana, cuando ya es de día. Pasará ese día. Esa noche. El segundo día la segunda noche. El tercer día y la tercera noche tengo que pensar la manera de obtener Los 3 trozos de la llave y el crucifijo. 1 cada dia.Tendré que pensar la forma en que cada día un nasti al azar caer una llave al morir. ¿O cuando salga corriendo? Al dar las campanadas. Casi mejor eso. El crucifijo lo soltará Un nasti también En la tercera noche cuando dé las campanadas y se vaya corriendo Un momento: a lo mejor este enfoque desincentiva la exploración. A ver como lo hago.  


HUD: 
los atributos están al revés
que vaya recuperando algo de salud y de stamina más rápido. 