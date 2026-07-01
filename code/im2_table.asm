; ==============================================================================
; IM2_TABLE - Tabla de vectores IM 2 (fix ULA snow en hardware real)
; ==============================================================================
; DEBE vivir en bank 2 ($8000-$BFFF): la unica RAM no-contended Y siempre
; visible del mapa 128K. Antes vivia en $7A00 (slot 1 = bank 5 CONTENDED) y
; el registro I apuntaba a memoria contended -> los refresh cycles M1 del Z80
; (I:R en el bus de direcciones) colisionan con los fetches de video de la
; ULA -> "snow" por toda la pantalla en hardware real (48K/128K/+2 gris; en
; algunos 128K puede incluso colgar la maquina). Los emuladores del pipeline
; (Spectaculator, chips) NO emulan el snow, por eso nunca se vio en dev.
; Ver docs/ula_snow_investigation.md.
;
; Diseno:
; - ALIGN 256: page-aligned donde caiga en el flujo (sin ORG fijo -> sin
;   "zona prohibida" nueva). Inicio carga el registro I con `high Im2Table`,
;   asi que el valor se autoadapta si el layout de bank 2 cambia.
; - 257 bytes (no 256): si el data bus entrega $FF en el IRQ ack, la CPU lee
;   el word en Im2Table+$FF e Im2Table+$100.
; - Todos $7B -> cualquier byte del bus da vector = $7B7B = Im2Vector
;   (JP MusicIrqHandler, music_irq.asm, slot 1). Que el HANDLER sea contended
;   solo cuesta algun T-state; el snow lo causa exclusivamente la pagina de I.
; - NUNCA recolocar esta tabla en $4000-$7FFF ni permitir I en $40-$7F.
; ==============================================================================
    ALIGN 256
Im2Table:
    DEFS 257, $7B
    ; Guardas: la tabla entera debe caer en bank 2 (siempre visible +
    ; no-contended). Si bank 2 se llena y ALIGN empuja la tabla sobre $C000,
    ; el build revienta aqui en vez de nevar en hardware.
    ASSERT Im2Table >= $8000
    ASSERT (Im2Table + 257) <= $C000
