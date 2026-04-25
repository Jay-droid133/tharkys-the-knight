# Sprite Generator — qué es

Nuevo editor en `tools/sprite_generator.html`. Es una webapp standalone (HTML+JS vanilla, sin dependencias, un único archivo) para preparar pixel art con la paleta y restricciones del ZX Spectrum, en tiempo real, antes de meterlo en el juego.

## Qué hace

Toma una imagen cualquiera (drag & drop, file picker o pegado con `Ctrl+V` desde el portapapeles) y la convierte a pixel art Spectrum aplicando un pipeline encadenado, con todos los parámetros expuestos como sliders/checkboxes que se actualizan a 60 fps mientras el usuario los mueve.

Pasos del pipeline, en orden:

1. **Center-crop** al aspect ratio del sprite final (no estira, recorta).
2. **Reescalado** a `cells_x × 8` por `cells_y × 8` píxeles con interpolación de calidad alta.
3. **Ajuste de imagen**: brillo, contraste, saturación y gamma.
4. **Cuantización por celda 8×8** con la paleta del Spectrum:
   - Modo color con 15 colores (8 normales + 7 brillantes; el negro se considera compartido).
   - Aplica attribute clash: 2 colores como mucho por celda 8×8, ambos del mismo grupo (`auto` por brillo medio de la celda, o forzados a `normal` / `bright`).
   - Opción de saltarse el clash (`enforce_clash` off) y permitir los 15 colores libres por celda.
   - Modo monocromo: ink + paper a elegir entre los 8 colores, con toggle de brightness, sin clash. Pensado para sprites del jugador / enemigos.
5. **Dithering Bayer 4×4** opcional, con intensidad de 0 a 100, aplicado a la decisión ink/paper de cada píxel.

Tres canvases visibles en pantalla:

- Original (recortado al aspect del sprite, para ver lo que entra).
- Pixel art ampliado (zoom configurable, nearest-neighbor, para ver cómo queda en grande).
- 1:1 con los píxeles reales.

## Export actual

Solo PNG: el ampliado y el 1:1. Es lo que falta extender para que sirva al pipeline ASM del juego.

## Cómo se vincula con el resto del flujo

Es la pieza final del flujo `ComfyUI → PNG generado → Spectrum`. Antes había un nodo equivalente en ComfyUI (`SpectrumColorClash`), pero hacía falta volver a ejecutar el grafo cada vez que se tocaba un slider de post-procesado. Este editor evita ese ciclo: una vez tienes una buena imagen base de Flux/SD, la pegas aquí y afinas el resto en tiempo real.

## Contexto: ComfyUI como generador

ComfyUI corre en `C:\ComfyUI_windows_portable\` con PyTorch 2.11 + CUDA 12.8 sobre RTX 5090 (Blackwell). El frontend está en versión 1.43.x.

Modelos disponibles en `ComfyUI/models/`:

- `diffusion_models/flux1-schnell-fp8.safetensors` (Flux.1 schnell quantizado FP8 desde el mirror de Comfy-Org).
- `checkpoints/sd3.5_large.safetensors` (Stable Diffusion 3.5 Large, vía symlink junction desde otra unidad).
- `clip/clip_g.safetensors`, `clip_l.safetensors`, `t5xxl_fp16.safetensors` (text encoders).
- `vae/ae.safetensors` (VAE de Flux, descargado del repo oficial de BFL).
- `style_models/flux1-redux-dev.safetensors` (Flux Redux para referencia de estilo por imagen).
- `clip_vision/sigclip_vision_patch14_384.safetensors` (vision encoder que usa Redux).
- `loras/Retro-Pixel.safetensors` (LoRA `prithivMLmods/Retro-Pixel-Flux-LoRA`, trigger `Retro Pixel, retro pixel art style`).

Custom nodes propios en `ComfyUI/custom_nodes/comfyui_spectrum/__init__.py` (Python, NumPy + PyTorch, todo en un único archivo):

- `SpectrumColorClash` — color clash + dithering Bayer + modo monocromo. Misma lógica que el editor HTML.
- `SpectrumSpriteDims` — calcula `px_width`, `px_height`, `gen_width`, `gen_height` a partir de `cells_x`, `cells_y`, `scale_factor`. Sus salidas se cablean a varios `ImageScale` para no tener que mantener tres pares de dimensiones a mano.
- `SpectrumPromptCombine` — junta dos textareas (`subject` + `style`) en un único string que se conecta como widget→input al `CLIPTextEncode`.
- `SpectrumImageAdjust` — brillo, contraste, saturación, gamma sobre un tensor `IMAGE` antes de pixelizar.

Workflows guardados en `C:\Users\JJ\Downloads\`, todos sobre la misma base con el mismo bloque post-proceso (`SpectrumImageAdjust → ImageScale pixelizar → SpectrumColorClash → ImageScale ampliar → Preview/Save`):

- `flux_spectrum_workflow.json` — text-to-image puro con Flux schnell + LoRA.
- `flux_redux_spectrum_workflow.json` — añade `LoadImage` + `CLIPVisionEncode` + `StyleModelApply` para usar una imagen como referencia de estilo.
- `flux_img2img_spectrum_workflow.json` — añade `LoadImage` + `ImageScale` + `VAEEncode` y mete el latente al KSampler con `denoise` < 1.
- `flux_img2img_redux_spectrum_workflow.json` — combina img2img + Redux: dos `LoadImage` distintos, uno para punto de partida y otro para referencia de estilo.
- `sd35_spectrum_workflow.json` — variante con SD 3.5 Large (28 pasos, CFG 4.5, `TripleCLIPLoader`, `ModelSamplingSD3` shift 3.0).

Parámetros típicos:

- Flux schnell: `cfg=1.0`, `steps=4` (img2img sube a 8), `sampler=euler`, `scheduler=simple`. No usa negative prompt real.
- SD 3.5 Large: `cfg=4.5`, `steps=28`, `sampler=euler`, `scheduler=sgm_uniform`, `EmptySD3LatentImage`.
- Generación a 1024×768 (8×6 celdas con `scale_factor=16`) para luego pixelizar a 64×48.

## Referencia útil

`C:\Users\JJ\Downloads\spectrum-asset-ai.zip` (proyecto de terceros descargado para inspirarse) contiene:

- `utils/spectrumConverter.ts` — conversor TS a paleta Spectrum, similar al del editor pero con código adicional para producir el bytemap nativo (interleaved para SCREEN, lineal para sprites/tiles) y el byte de atributo. Útil como referencia si en algún momento se quiere portar algo de su lógica de exportación.
- `utils/tapeGenerator.ts` — generador de cinta `.tap` con loader BASIC + bloque CODE/SCREEN.

No está integrado en el repo; vive solo en el zip.
