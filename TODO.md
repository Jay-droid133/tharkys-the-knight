# TODO

## Bugs
- [ ] En ocasiones, cuando estoy sobre un tejado rojo. Al ponerme yo rojo, se Invierten los atributos de las bg sprite cells superiores cellsdel tejado. 
- [ ]
- [ ]
- [ ]
- [ ]

- [ ] Monsters: 
    - [x] monsters deben empujarse mejor
    - [X] deben morir tras la pausa del knockback (o al darse con el límite de la pantalla) si llevan 5 golpes. Aparecerá otro en una posición random
    - [ ] a veces no hace knockback, a pesar de haber direcciones disponibles
    - [x] cuando los echo a la derecha, siempre mueren, en lugar de irse a la room de la derecha   
    - [x] revisa la consistencia de los golpes. Estás seguro de que solo reciben uno por cada ciclo de animación de attack?
    - [ ] Un sprite de 2 * 1 con humo de daño en el lado del player desde donde va a ser proyectado el monster
    - [ ] WIP: al salir de la pantalla o al entrar podrían dibujarse hasta desaparecer o hasta aparecer del todo? (si funciona, probar con el player). Actualmente no funciona bien. No terminan de seguirme siempre, creo que puede deberse a que si aparecen el la fila contraria por el clipping entonces aparecen por el lado contrario y vienen a mi desde el frente
    - [ ] BUG:Pero te has cargado que si lo he empujado y entro enseguida, debería estar allí esperándome!!!
    También veo una reducción en la performance. No sé en cual de Las fases ha ocurrido. Haz una auditoría de las posibles optimizaciones, sobre las colisiones de los monsters (por ejemplo revisa lo que hicimos con los nasties y mira si puedes reaprovechar alguna rutina). 
    

- [ ] player: 
    - [x] Me gustaría que, Cuando inicio un ataque se termine siempre de reproducir la animacion aunque me deje moverme. 
    - [ ] BUG: cuando me muevo atacando, la animación de ataque es más lenta
    - [ ??] que la salida y la entrada de las rooms sea igual de suave que los monsters
    - [ ] aumentar animaciones: un frame de daño para cada orientación, dos frames de idle para cada orientación, y trabajar la animación de muerte.

- [ ] nasties: 
    - [x] aparecer tras un momento en la pantalla nueva
    - [x] no aparecer encima del player
    - [DEPRECATED. TOO EXPENSIVE] no solaparse entre ellos: si chocan, dirección contraria cada uno
    - [x] no solaparse con el player. Si lo tocan y no están atacando, hacen daño y mueren
    - [ ] correr más cuando "scared"
    - [ ] separar por momento del día: 
        - [ ] a1 y d y c1: águila, araña, cabra (se mueve verticalmente, busca la fila y se lanza horizontal), serpiente ((se mueve horizontalmente, busca la columna y se lanza))
        - [ ] c2 y n1 y a1: rata, murciélago, escorpión (se mueve verticalmente, busca la fila y se lanza horizontal), gato rabioso (se mueve horizontalmente, busca la columna y se lanza)
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

- [ ] Tener las tres opciones de ataque y poder elegir entre ellas en debug (una tecla por ejemplo, y una letra en el HUD)
- [ ] Que el indicador de salud sea la parte izquierda del adorno del reloj. Y el de la stamina, la parte derecha. Se va borrando línea a línea, y va cambiando de color (verde, azul, amarillo, rojo, magenta, azul)
- [ ] La STAMINA tendrá tres niveles: Máximo (principio, poción): permitirá el usar la espada continuamente. Medio: permitirá el modo Fijo. Bajo: el cooldown corto. VACÍA: el cooldown largo. Debe acercarse a un pozo, recoger pociones, o matar un monster concreto. Mejor que un monstruo concreto suelte poción o cualquiera de vez en cuando
La vida se recuperará igual: POZO, pociones, un monstruo concreto. Mejor que un monstruo concreto suelte poción o cualquiera de vez en cuando.
- [ ] Efectos de sonido al recoger objetos

## Hecho
- [x] Day/night cycle
- [x] Colisiones con fondo (BG)
- [x] Subir repo a GitHub
