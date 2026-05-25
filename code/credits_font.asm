; ==============================================================================
; credits_font.asm - Font 8x8 para creditos cutscene town gate Y splash post-load
; ==============================================================================
; Reward de ZX Origins (Damien Guard) — bold con sombra. Reemplazó al font
; custom mayúsculas-only original cuando se necesitaron minúsculas (ej. nombre
; con mixed case en los créditos). Tambien sustituyo el font del splash para
; consistencia visual entre menu y cutscene final.
;
; Vive en bank 4 (cold, holgado). El thunk LoadCreditsFontToBuffer copia los
; 768 B a BgSpriteBuffer (slot 2 always-visible) una vez al entrar fase
; CREDITS. DrawCharFontAt lee desde ese buffer.
;
; Layout: 96 chars consecutivos (0x20-0x7F), 8 B por char.
; Offset = (char - 0x20) * 8.
;
; Los bytes se inlinean como DEFB statements (formato source que el propio
; Damien distribuye junto al .ch8). Esto evita re-hospedar el font como
; archivo de font en el repositorio. Licencia: code/fonts/REWARD_LICENSE.md.
; ==============================================================================
CREDITS_FONT_SIZE EQU 768          ; 96 chars * 8 B

CreditsFontData:
    INCLUDE "reward_font_data.inc"
CreditsFontEnd:
    ASSERT (CreditsFontEnd - CreditsFontData) == CREDITS_FONT_SIZE
