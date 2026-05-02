Cuando el player comienza a caminar pixel a pixel hacia abajo, su color pasa a dim. Me gustaría que estuviese bright todo el sprite del player hasta que abandone la pantalla.  

Cambiar el sprite de "The End" la palabra "the" un carácter más a la izquierda. 

Haz que cada contacto con Nasty o Monster quite un poquito más de salud y que el jugador parpadee ON/OFF durante un segundo de gracia en el que no recibe más daño. 

Probar a poner el brazo y el dedo un carácter más altos. 

He añadido un tercer frame a la animación de la muerte del jugador y, además, he creado las tres versiones reflejadas para que pueda morir en las dos direcciones: izquierda o derecha. El nuevo archivo es el siguiente: 

que los nasties no vuelvan a aparecer hasta que el player tenga el control. Desde ese momento, que pase la misma pausa hasta que empiecen a aparecer los nasties, que cuando entran en una pantalla nueva. Me explico?

Tres pitidos durante la fase 1, tras el respawn, coinciden con los parpadeos. El último pitido es más largo. 

El enemigo muerte inicia su contador de aparición cuando el player tiene el control. 

Tengo que reducir las animaciones de Puff y Spawn a 3 por 3. Ver como son en Sabrewulf?. 

Las animaciones de Spawn y Puff ocupan con demasiada frecuencia caracteres de los Background Sprites. Habría que implementar alguna manera de que aparezcan de manera que no pase esto. ¿Qué opciones tenemos? 

Todavía me falta implementar las pociones de vida, estamina, etc. 


En vez de "Game Over", "La Muerte" haciendo el moonwalk. 

Gestionar la muerte del jugador Hablemos. Queda el resto de una tumba. Los nastis mueren. Una pausa. Vuelven a aparecer en cuanto respawnea el jugador. Los monstruos Se retiran del cadáver y se quedan quietos. Una pausa hasta que respaune el jugador y acabe su período de gracia, momento en el que volverán a su comportamiento normal. El jugador vuelve a aparecer en la Misma pantalla en la que murió, por el mismo sitio por el que entró. Estará parpadeando ON/OFF durante 3 segundos de gracia, en los que no recibirá daño. 


Mira en el level editor. En el panel derecho superior, "template info", pone "templates 48 designed" (48 total). Eso es un bug? Yo creo que tenemos muchas más ¿no?

El tiempo debería pasar un poco más rápido para que haya más variedad.

Las decoraciones izquierdas del hud del reloj, las que marcan la salud, a veces se pintan mal. Solo afecta a las que están decaídas. No afecta a las iniciales. Las iniciales sanas se pintan bien.

Aunque las campanadas siempre suenan a su volumen más alto cuando estoy en la plaza del reloj y van disminuyendo con la distancia, debe haber un mínimo audible aunque esté en el otro extremo del mapa.

La música de tensión que suena cuando acaban las campanadas solo suena por un canal. 

Música de amanecer (Salvo después de matar a los monstruos en la iglesia). Tirolari tirari rolari 

Crear animación de Spawn y Puff. Preguntar cuántos frames tiene cada una.





