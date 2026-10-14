# Resultados SEDWARE V3.2

V3.2 corrige el límite de aceleración **aplicada** de pitch en los escenarios continuos ensayados y corrige fallos verificables de movimiento, ciclo de vida y jerarquía del ESP. **El error medio de pitch Fixed empeora y el coste CPU no mejora de forma uniforme.** Los resultados no demuestran Fly/Speed/ESP dentro de Da Hood.

Estado: **Luau CLI y dobles de API ejecutados; Roblox Studio, física/render/FPS nativos e impactos no ejecutados**. Programar un timestep a 144 Hz no significa alcanzar 144 FPS en Roblox. No hay integración añadida con las armas originales.

## Fuentes y referencia antigua

Los dos runners comparativos cargan los módulos desde los **bundles autónomos reales**, sin reimplementar sus fórmulas.

- Baseline V3.1: commit [`da44a4c7af3857c1fed22b9fb757c012180650ac`](https://github.com/sedonkkk/sedon-/blob/da44a4c7af3857c1fed22b9fb757c012180650ac/SedwareCamLock.lua), 230147 bytes, SHA256 `3a8e56d1220f34b961102f32b59e1a42f470ee58f739b7a3b7eea9c7b9ab602b`.
- V3.2: [SedwareCamLock.lua](../SedwareCamLock.lua), 250722 bytes, SHA256 `11cf292c14716295436ec39d7f54115924a5351b823aa54ae503d6fac3d12d28`.
- Los tres resúmenes JSON publicados contienen ese mismo hash V3.2. Si el script cambia, estas mediciones describen exclusivamente el snapshot identificado.

Se leyó completo `message (8).txt`: 112649 bytes y 2761 líneas, SHA256 `7573674d0ef56f6c4a278dd5d23fa7e1080bddb8054a39c5530c7ea776642375`. La [auditoría con líneas exactas](SEDWARE_V32_LEGACY_AUDIT.md) separa descripción y flujo efectivo. Fly1 usa Core/Weld, BodyPosition/BodyGyro y desplazamientos por wait(); Speed V2 deja de ejecutar su cuerpo tras renombrar Humanoid a xxx. Speed V1 sólo contiene un cargador remoto y su algoritmo no está incluido. No se ejecutó el archivo antiguo ni sus recursos externos.

## Regresiones y categorías

| Comprobación | Casos / filas | Verificaciones | Resultado |
| --- | --- | --- | --- |
| Cam: matemática, cámara/roll, GUI, seguimiento, movimiento propio, servidor y loader | 197 casos | 193429 | 0 fallos |
| DH Prediction + Pink Dot Lock / multiarmas originales | 342 casos | 80528 | 0 fallos |
| Total de regresiones CLI/dobles | 539 casos | 273957 | 0 fallos |
| Calibración V3.1/V3.2 | 2304 filas / 1152 pares | 614016 muestras programadas | Completada |
| CPU cercano + lejano | 48 configuraciones | 720 invariantes; 57600 frames programados | Completada |
| Compilación Cam | 55 archivos | Compilador Luau oficial | Aprobada |
| Runner nativo V3.2 | 56 casos preparados | Ninguno ejecutado en Roblox | Pendiente |

Los 51 casos nuevos específicos de V3.2 comprueban seguimiento (11), movimiento/servidor propio (22), ESP (8) y Session/UI (10). Verifican comandos, propiedades, referencias, estados y cancelación mediante dobles. No verifican el desplazamiento físico del solver ni el render detrás de una pared nativa. Los dos casos finales de movimiento comprueban cuantización float32 de WalkSpeed, restauración y ausencia de escrituras repetidas; una corrección material sigue detectándose.

Los fixtures históricos conservan sus casos y explicitan opt-outs de guardas o políticas cuando miden el comportamiento anterior: AngularSafety, VerticalControl, ReversalDamping, readquisición/gracia y confirmación física/servidor según el caso. Las nuevas regresiones comprueban aparte los defaults actuales. **No se eliminaron casos para hacer pasar el cambio.** Los nombres históricos que contienen “native doubles” siguen describiendo dobles, no ejecución del motor.

## Calibración: referencias de las métricas

Matriz: 12 trayectorias × 30/60/120/144 Hz programados × RTT nominal 60/100/150/300 ms × Fixed/Adaptive/Critical × Manual/Auto × dos versiones = **2304 filas**. Cada fila dura tres segundos, usa Memory, yaw inicial −45°, observaciones recibidas a 30 Hz, RTT muestreado a 5 Hz y ruido determinista X ±.04/Y ±.025 studs.

Las trayectorias son caminar, correr, saltos repetidos, aterrizar, caer, invertir dirección, movimiento cercano, lejano, circular, detenerse, teleport y RTT variable. No hay impactos, simulación de daños ni selección multijugador en esta matriz matemática.

El simulador conoce la captura y retrasa la posición por RTT/2; el estimador recibe sólo tiempo local de recepción y RTT por separado. Esa fixture no determina la edad real de datos replicados en Roblox.

- **Yaw/pitch y ángulo actual:** orientación frente a la verdad instantánea; adelantar deliberadamente el movimiento también puede aumentar este error.
- **Error de setpoint:** cámara frente a la posición predicha, para separar respuesta del controlador y extrapolación.
- **Posición futura:** posición predicha frente a la trayectoria real en los horizontes X/Y originalmente solicitados, antes de cualquier reducción por seguridad.
- **Posición instantánea:** posición predicha frente a la verdad actual, separada del error futuro.
- **Adquisición angular:** final de al menos 100 ms continuos dentro de 1° del setpoint; `-1` es fallo y no entra en la media de éxitos. No mide seleccionar jugador ni acertar una bala.
- **Warmup:** métricas desde t≥.5 s, publicadas además de las métricas de todos los frames. No sustituyen la adquisición inicial.

Las medias dan igual peso a cada fila. Máximos y tasas incluyen adquisición y transiciones; los CSV conservan cada condición.

| Modo | Yaw medio V3.1 → V3.2 (°) | Pitch medio (°) | Setpoint medio (°) | Adquisición exitosa (s) | Fallos de adquisición |
| --- | --- | --- | --- | --- | --- |
| Fixed | 1.3266 → 1.3266 | 0.2825 → 0.3013 | 0.6133 → 0.6361 | 0.2338 → 0.2660 | 0/384 → 0/384 |
| Adaptive | 1.1745 → 1.1747 | 0.3022 → 0.3118 | 1.1411 → 1.1492 | 0.5397 → 0.5502 | 0/384 → 0/384 |
| Critical | 3.3550 → 3.3550 | 0.4280 → 0.4225 | 3.9479 → 3.9480 | 1.5026 → 1.5026 | 174/384 → 174/384 |

Fixed mantiene el yaw y aumenta el pitch medio **.2825 → .3013°** y la adquisición **.2338 → .2660 s**. Adaptive también aumenta su pitch; Critical lo reduce ligeramente, pero conserva **174/384 fallos de adquisición**. No hay mejora universal de precisión. Los errores de posición, independientes del modo de cámara, cambian poco: instantáneo **1.4131 → 1.4135 studs** y futuro solicitado **2.2705 → 2.2709 studs**.

### Aceleración aplicada y sobrepaso

Se mide la diferencia entre pitches consecutivos del CFrame aplicado dividida por dt; no se usa solamente el comando interno. El scope continuo exige AngularSafety y contexto de predicción, y excluye epochs iniciales/reinicios y restricciones duras explícitamente marcadas en V3.2. La baseline no expone esas marcas y se mide directamente.

| Modo | Aceleración pitch continua máxima V3.1 → V3.2 (°/s²) | Frames sobre 1200 dentro del scope | Recuperación de frenado V3.2 (frames) | Cruces del setpoint V3.2 (frames) |
| --- | --- | --- | --- | --- |
| Fixed | 22320.00 → 1200.00 | 1354 → 0 | 645 | 75 |
| Adaptive | 21120.00 → 1200.00 | 430 → 0 | 449 | 63 |
| Critical | 8630.04 → 1200.00 | 827 → 0 | 48 | 6 |

En esta matriz V3.2 también alcanza un máximo de todos los frames de **1200°/s²** y registra cero conflictos duros. Es un resultado de estas fixtures, **no una garantía global**: reinicios, sustitución de cámara, polos, escrituras externas y yaw tienen límites distintos. La ausencia de flags en V3.1 no permite interpretar sus contadores cero como ausencia comprobada de esos eventos.

La guarda conserva velocidad aplicada y puede tardar en frenarla tras cambiar el objetivo. Los cruces con setpoint móvil se registran aparte del sobrepaso de un objetivo estable. `stableGoalOvershootMaxDegrees=0` en estas filas no demuestra ausencia de toda oscilación; los cambios de signo de error también pueden resultar del movimiento del objetivo y del adelanto intencional. El roll calculado permaneció bajo .000001° en aritmética de dobles; el CFrame nativo sigue pendiente.

| Fixture Fixed | Pitch medio V3.1 → V3.2 (°) | Pitch máximo (°/s) | Aceleración continua máxima (°/s²) | Adquisición exitosa (s) |
| --- | --- | --- | --- | --- |
| Saltos repetidos | 0.8992 → 0.9254 | 83.33 → 68.61 | 5317.93 → 1200.00 | 0.2616 → 0.2681 |
| Aterrizaje | 0.3011 → 0.3137 | 83.33 → 69.17 | 5061.49 → 1200.00 | 0.1790 → 0.1790 |
| Caída | 1.9644 → 2.1516 | 180.00 → 180.00 | 22320.00 → 1200.00 | 0.3246 → 0.7042 |
| Inversión | 0.0191 → 0.0191 | 5.98 → 5.98 | 916.31 → 916.31 | 0.1861 → 0.1861 |

Los cambios bruscos de aceleración se reducen, a costa de inercia y mayor error/adquisición durante algunas caídas. El indicador medio de pitch por debajo de la verdad actual tras aterrizar también aumenta en la fixture Landing **.8790 → .9674°**. Esa métrica es una media por fila distinta del máximo global usado en informes anteriores; se conserva el detalle en CSV.

### RTT nominal

| RTT (ms) | Yaw V3.2 Fixed medio (°) | Pitch (°) | Posición instantánea (studs) | Futuro solicitado (studs) |
| --- | --- | --- | --- | --- |
| 60 | 1.4711 | 0.2095 | 1.6576 | 1.2353 |
| 100 | 1.2921 | 0.2438 | 1.4688 | 1.7174 |
| 150 | 1.0376 | 0.3019 | 1.1763 | 2.2765 |
| 300 | 1.5057 | 0.4499 | 1.3515 | 3.8544 |

Incluye Manual/Auto y la trayectoria de RTT variable bajo cada nominal. No representa latencia real medida ni una recalibración universal para 100–300 ms. Auto conserva su curva empírica existente; el error futuro sigue creciendo con el retraso ensayado.

## CPU: mismo host, sin render ni física nativos

Cada perfil usa 5/15/30 personajes visibles estacionarios, cámara ON/OFF y ESP ON/OFF. Cada configuración recorre 1200 frames programados a 60 Hz tras .4 s de calentamiento. Hitboxes/Names ON, VisibleOnly; Fly/Speed OFF. Se ejecutaron primero cercano y luego lejano, sin otras pruebas corriendo en paralelo.

`meanHostFrameMs` incluye Mock.advance y todos sus callbacks; `meanSessionMs` y `maxSessionMs` aíslan la instrumentación de Session._step en los CSV. Los tiempos incluyen overhead de los dobles, no render de Roblox. Es una corrida por condición, sensible a scheduling y garbage collection; los ratios CPU no son ratios FPS.

### Cercano: z=−60, rangos por defecto

| Personajes | Cámara | V3.1 ESP OFF (ms/frame) | V3.1 ESP ON | V3.2 ESP OFF | V3.2 ESP ON |
| --- | --- | --- | --- | --- | --- |
| 5 | OFF | 0.004829 | 0.011567 | 0.004403 | 0.012007 |
| 5 | ON | 0.062829 | 0.069334 | 0.064868 | 0.073414 |
| 15 | OFF | 0.005511 | 0.021835 | 0.004991 | 0.028394 |
| 15 | ON | 0.060317 | 0.079641 | 0.065723 | 0.092839 |
| 30 | OFF | 0.004507 | 0.038069 | 0.004766 | 0.052339 |
| 30 | ON | 0.062541 | 0.102532 | 0.063590 | 0.119982 |

### Lejano: z=−800, MaxDistance/ESPMaxDistance=1500 en ambas versiones

| Personajes | Cámara | V3.1 ESP OFF (ms/frame) | V3.1 ESP ON | V3.2 ESP OFF | V3.2 ESP ON |
| --- | --- | --- | --- | --- | --- |
| 5 | OFF | 0.005436 | 0.008399 | 0.004687 | 0.009165 |
| 5 | ON | 0.062144 | 0.070517 | 0.069061 | 0.072998 |
| 15 | OFF | 0.004563 | 0.014791 | 0.004544 | 0.017845 |
| 15 | ON | 0.059578 | 0.076520 | 0.063970 | 0.081930 |
| 30 | OFF | 0.005003 | 0.022016 | 0.004596 | 0.031254 |
| 30 | ON | 0.060437 | 0.085945 | 0.064475 | 0.095520 |

Con 30 personajes, cámara y ESP ON, el coste observado sube **0.102532 → 0.119982 ms** cercano (+17.02%) y **0.085945 → 0.095520 ms** lejano (+11.14%). Algunas condiciones mejoran, pero no hay reducción uniforme ni se promete mejora de FPS.

Ambas versiones mantienen las operaciones lejanas reducidas introducidas en V3.1: con 30 personajes y ESP ON, **5670 raycasts/proyecciones cercanos frente a 1560 lejanos** por versión. No es una reducción nueva de V3.2 frente a V3.1. ESP OFF registra cero raycasts/proyecciones en esta fixture.

Los 720 invariantes comprueban pool e instancias sin crecimiento después del warmup, conexiones estables, cero Players:GetPlayers en la ventana medida y cero conexiones/render bindings/tweens tras Unload. V3.2 conserva más objetos/conexiones de GUI y diagnóstico que V3.1, visibles en CSV; estabilidad durante esta ventana no prueba ausencia de toda fuga posible en el motor.

## Reproducción, datos y validación pendiente

Con Luau/luau-compile oficiales disponibles y el commit baseline V3.1 en Git local, ejecutar secuencialmente desde la raíz:

```bash
python3 scripts/calibrate_cam_v32.py
python3 scripts/benchmark_cam_v32.py
python3 scripts/benchmark_cam_v32.py --far
```

Las regresiones se ejecutan por separado:

```bash
python3 scripts/check_cam.py
python3 scripts/check.py
python3 scripts/check_pink.py
```

Los archivos publicados son copias exactas de build/. Repetir CPU puede producir otros tiempos; un cambio de script exige regenerar el hash y la comparación.

| Datos | CSV | Resumen / hash |
| --- | --- | --- |
| Calibración | [2304 filas](results/SEDWARE_V32_CALIBRATION.csv) | [JSON](results/SEDWARE_V32_CALIBRATION_SUMMARY.json) |
| CPU cercano | [24 configuraciones](results/SEDWARE_V32_CPU_NEAR.csv) | [JSON](results/SEDWARE_V32_CPU_NEAR_SUMMARY.json) |
| CPU lejano | [24 configuraciones](results/SEDWARE_V32_CPU_FAR.csv) | [JSON](results/SEDWARE_V32_CPU_FAR_SUMMARY.json) |

Consulta la [guía V3.2](SEDWARE_V32.md) y abre [SedwareCamV32Test.rbxlx](../studio/SedwareCamV32Test.rbxlx) para ejecutar los **56 casos nativos preparados**, todos pendientes. Requieren Play en una experiencia propia: desplazamiento y velocidad medidos, restauración, respawn/R6/R15, restricciones, override del servidor propio, paredes/Highlight/Billboard reales y cámara. Se requieren además C/V/G físicos, captura de texto, primera/tercera persona, drag/minimizar tras respawn, dos clientes, StreamingEnabled y MicroProfiler.

La actualización contiene una integración de movimiento para una experiencia propia o autorizada. No certifica permisos, replicación, Fly/Speed/ESP, selección ni impactos en Da Hood original.
