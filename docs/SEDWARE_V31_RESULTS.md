# Resultados SEDWARE V3.1

Las comparaciones ejecutadas muestran menos exceso vertical en saltos/aterrizajes y menos comprobaciones de ESP lejano. **El seguimiento en caída empeora y no hay mejora universal de precisión o CPU.** Fixed permanece por defecto; Adaptive y Critical conservan compromisos distintos.

Estado: **Luau CLI y dobles de API ejecutados; Roblox Studio, física/render/FPS nativos, impactos y Da Hood no ejecutados**. Un timestep programado a 144 Hz no significa que Roblox haya alcanzado 144 FPS. No se atribuyen disparos fallidos al error de cámara ni se anuncia integración con armas originales.

## Fuentes medidas

Ambas versiones cargan sus módulos desde el **bundle autónomo real**, no desde una fórmula duplicada.

- V3: commit [`7eeb3d1ce54a59b9fda2c56ab76a80cf79881c9a`](https://github.com/sedonkkk/sedon-/blob/7eeb3d1ce54a59b9fda2c56ab76a80cf79881c9a/SedwareCamLock.lua), SHA256 `44a7b9288a17e0ccc7daee89f6b865de3170ce3a21600340313c22e1e3831fe1`.
- V3.1: [`SedwareCamLock.lua`](../SedwareCamLock.lua), 230147 bytes, SHA256 `3a8e56d1220f34b961102f32b59e1a42f470ee58f739b7a3b7eea9c7b9ab602b`.
- Los cuatro resúmenes JSON contienen el mismo hash V3.1. Si el archivo cambia, estos resultados describen exclusivamente ese snapshot y deben regenerarse.

Herramientas: Luau CLI oficial y `CamV2Mock`. Los cuatro runners se ejecutaron secuencialmente; las mediciones de CPU se hicieron sin ejecutar las regresiones en paralelo.

## Regresiones y alcance

| Comprobación | Casos / filas | Verificaciones | Resultado |
| --- | --- | --- | --- |
| Cam/V3.1: matemática, cámara/roll, GUI, lifecycle, movimiento propio, servidor y loader | 146 casos | 129310 | 0 fallos |
| DH Prediction + Pink Dot Lock / multiarmas originales | 342 casos | 80528 | 0 fallos |
| Total de regresiones CLI/dobles | 488 casos | 209838 | 0 fallos |
| Calibration V3/V3.1 | 2304 filas / 1152 configuraciones pareadas | 614016 muestras; métricas finitas y roll | Completado |
| Persistencia de Session V3/V3.1 | 32 filas / 16 configuraciones pareadas | 4330 frames programados | Completado |
| CPU cercano + lejano | 48 configuraciones | 720 invariantes; 57600 frames programados | Completado |
| Compilación Cam | 47 archivos | Compilador Luau oficial | Aprobada |
| Runner nativo V3.1 | 23 casos preparados | Ninguno ejecutado en Roblox | Pendiente |

Las filas de calibración, persistencia y CPU se reportan aparte de las 488 regresiones: no son pruebas de impactos ni cuentas de usuarios reales. Los nombres históricos que contienen “native doubles” describen llamadas de API con dobles, no ejecución del motor.

Los fixtures históricos de matemática/controlador fijan `AngularSafety=false`, `VerticalControl=false` y/o `ReversalDamping=false` cuando comprueban calibración o comportamiento previo sin guardas. Los fixtures de pérdida histórica declaran `ReacquireOnLoss` y la gracia de parte requerida por su caso. **No se eliminaron casos.** Los 30 casos específicos nuevos de V3.1 comprueban por separado sus defaults y cambios; el paso de una regresión antigua no afirma que su comportamiento previo siga siendo idéntico bajo defaults nuevos.

## Calibración: qué mide cada error

Matriz: 12 trayectorias × 30/60/120/144 Hz programados × RTT nominal 60/100/150/300 ms × Fixed/Adaptive/Critical × Manual/Auto × V3/V3.1 = **2304 filas**. Usa Memory, tres segundos por fila, una orientación inicial de yaw −45°, muestras recibidas a 30 Hz, RTT muestreado a 5 Hz y ruido determinista X ±.04 / Y ±.025 studs.

Trayectorias: caminar, correr, saltos repetidos, aterrizaje, caída, inversión, movimiento cercano, lejano, círculo, parada, teleport y RTT variable. La comparación de oclusión/ausencia de parte pertenece al runner independiente de persistencia descrito después.

El simulador retrasa la posición capturada por RTT/2; solo el simulador conoce su captura. El estimador recibe el timestamp de **recepción** y RTT por separado. RTT/2 es una fixture reproducible, no una medida de la edad real de posiciones publicadas por Roblox.

- **Yaw/pitch y error angular actual:** orientación de cámara frente a la trayectoria real instantánea, en grados. Un adelanto intencional también puede aumentar este error.
- **Error frente al setpoint:** cámara frente a la posición predicha, separando respuesta del controlador de extrapolación.
- **Error de posición futuro:** posición predicha frente al futuro real en los horizontes X/Y solicitados originalmente; reducir horizontes por seguridad puede aumentar este error.
- **Error de posición instantáneo:** posición predicha frente a la trayectoria real en el momento actual; se reporta separado del futuro.
- **Adquisición angular:** tiempo en que se completan al menos 100 ms continuos dentro de 1° del setpoint. No mide búsqueda de jugador ni impacto. `-1` significa no adquirido; promedios omiten esos fallos y el número de fallos permanece visible.
- **Cambios de signo:** error que pasa entre valores mayores de +.05° y menores de −.05°. Una trayectoria cambiante puede causarlos; por sí solos no demuestran oscilación.

Los promedios siguientes dan el mismo peso a cada fila; no ponderan por número de frames. Máximos y tasas incluyen adquisición y transiciones.

| Modo | Yaw medio V3 → V3.1 (°) | Pitch medio (°) | Setpoint medio (°) | Adquisición media exitosa (s) | Fallos de adquisición |
| --- | --- | --- | --- | --- | --- |
| Fixed | 1.2919 → 1.3266 | 0.1976 → 0.2825 | 0.4861 → 0.6133 | 0.2195 → 0.2338 | 0/384 → 0/384 |
| Adaptive | 1.1343 → 1.1745 | 0.2104 → 0.3022 | 1.0276 → 1.1411 | 0.5406 → 0.5397 | 0/384 → 0/384 |
| Critical | 3.3541 → 3.3550 | 0.3679 → 0.4280 | 3.9533 → 3.9479 | 1.4924 → 1.5026 | 164/384 → 174/384 |

Adaptive reduce yaw frente a Fixed en esta matriz, pero aumenta el error de setpoint y su adquisición media es más lenta. Critical reduce algunos cambios de signo/sobrepasos a costa de seguimiento y muchos fallos de adquisición angular con las ganancias actuales. Las medias de adquisición de Critical usan grupos de filas exitosas diferentes; no son una comparación de todas las condiciones.

La posición predicha es independiente del modo de cámara: error instantáneo medio **1.4395 → 1.4131 studs** y error futuro solicitado **2.2847 → 2.2705 studs**. Estos cambios pequeños no implican mayor probabilidad de impacto.

### Saltos, aterrizajes y caída: beneficio y coste

| Fixture Fixed | Pitch medio V3 → V3.1 (°) | Velocidad pitch máxima (°/s) | Pitch por debajo del objetivo tras aterrizar (°) | Aceleración pitch máxima (°/s²) |
| --- | --- | --- | --- | --- |
| Saltos repetidos | 1.0455 → 0.8992 | 150.73 → 83.33 | 0.0000 → 0.0000 | 21811.68 → 5317.93 |
| Aterrizaje | 0.3668 → 0.3011 | 155.59 → 83.33 | 3.0141 → 1.4491 | 22518.10 → 5061.49 |
| Caída | 0.7334 → 1.9644 | 931.48 → 180.00 | 7.1388 → 2.3954 | 52203.17 → 22320.00 |

Las guardas reducen cambios bruscos y bajadas excesivas después de aterrizar, pero retrasan la adquisición y el seguimiento durante caída. El pitch global medio Fixed empeora **.1976 → .2825°**. No se sustituye este resultado por una afirmación de “precisión mejorada” universal.

`PitchMaxAcceleration=1200` limita el slew del comando durante guardas; llegada al setpoint, prevención de sobrepaso y activación/desactivación pueden interrumpirlo. Los máximos medidos exceden 1200: **no es un límite global de aceleración de la cámara**. El roll permaneció inferior a .000001° en todas las filas CLI, en aritmética de dobles; su validación CFrame nativa sigue pendiente.

### RTT nominal: referencia y límites

| RTT nominal (ms) | Yaw V3.1 medio (°) | Pitch medio (°) | Posición instantánea (studs) | Futuro solicitado (studs) |
| --- | --- | --- | --- | --- |
| 60 | 1.4711 | 0.1897 | 1.6576 | 1.2353 |
| 100 | 1.2921 | 0.2229 | 1.4686 | 1.7170 |
| 150 | 1.0376 | 0.2820 | 1.1754 | 2.2757 |
| 300 | 1.5057 | 0.4353 | 1.3509 | 3.8541 |

Incluye Manual/Auto y la fixture de RTT variable bajo cada nominal. No todo cambia monótonamente: el horizonte empírico puede adelantar o retrasar la verdad actual. Auto conserva la curva 55/62/70 ms y usa su extremo fuera de rango; no hay una calibración nueva demostrada para RTT 100–300 ms. El error futuro crece claramente con los retrasos ensayados.

## Persistencia: pérdida real frente a pausa

Se ejecuta el `Session` real de ambos bundles, con un candidato válido por fila, SmartSelection=true, Radius=180, MaxDistance=350, HitPart=HumanoidRootPart y TargetGraceSeconds=.2. Matriz: dos versiones × cuatro Hz programados × cuatro fallos temporales = **32 filas / 4330 frames**. Cada fila incluye .5 s de calentamiento y .8 s de recuperación. Oclusión es un resultado explícito del doble Raycast; ausencia de parte destruye y recrea RootPart en el mismo personaje cargado.

| Fallo | Duración (s) | Pérdidas V3 → V3.1 | Pausa media (s) | Mismo jugador al final | Readquisición automática |
| --- | --- | --- | --- | --- | --- |
| Oclusión breve | 0.1 | 0 → 0 | 0.1063 → 0.1063 | 4/4 → 4/4 | 0/4 → 0/4 |
| Oclusión prolongada | 0.4 | 4 → 4 | 0.2146 → 0.2146 | 4/4 → 0/4 | 4/4 → 0/4 |
| Parte ausente breve | 0.1 | 4 → 0 | 0.0000 → 0.1000 | 4/4 → 4/4 | 4/4 → 0/4 |
| Parte ausente prolongada | 0.3 | 4 → 4 | 0.0000 → 0.1448 | 4/4 → 0/4 | 4/4 → 0/4 |

V3.1 conserva al mismo jugador ante desaparición breve de parte sin liberar/reseleccionar. Oclusión breve ya se toleraba en V3. La diferencia tras fallos largos es intencional: V3 readquiere automáticamente; V3.1 conserva `ReacquireOnLoss=false` y requiere acción del usuario después de una pérdida real. Un resultado final sin objetivo no se oculta como éxito ni se presenta como peor extrapolación.

`lossCount` observa transiciones de `GetLockedTarget()` a nil, incluyendo callbacks síncronos de destrucción. `pausedSeconds` cuenta intervalos aún bloqueados con `pauseReason`. `recoveredSamePlayer=true` también incluye filas que nunca perdieron al jugador; `autoReacquired=true` exige una pérdida observada seguida de readquisición. V3 no expone GetTrackingDiagnostics: estado final y motivo se conservan como `Unavailable`.

Hay **un solo candidato** por fila. `otherPlayerSelections=0` comprueba integridad de esa fixture, no demuestra ausencia de cambios de objetivo en una partida multijugador. No se simulan impactos ni streaming del motor.

## CPU de cliente: cercano y lejano

Mismo host Luau CLI, 5/15/30 personajes estacionarios visibles, cámara ON/OFF y ESP ON/OFF. Cada condición ejecuta 1200 frames programados a 60 Hz después de .4 s de calentamiento; Fly/Speed OFF, Hitboxes/Names ON y VisibleOnly. **48 configuraciones / 57600 frames**, incluyendo ambos perfiles y versiones.

`meanHostFrameMs` incluye `Mock.advance`, plumbing de cámara y callbacks. `meanSessionMs`/`maxSessionMs` aíslan el coste instrumentado de Session._step y se incluyen en CSV. Es una corrida por condición; scheduling y garbage collection del host afectan valores. No son tiempos de render, FPS observados ni ratios de FPS Roblox.

### Perfil cercano: z=−60, configuración de rango por defecto

| Personajes | Cámara | V3 ESP OFF (ms/frame) | V3 ESP ON | V3.1 ESP OFF | V3.1 ESP ON |
| --- | --- | --- | --- | --- | --- |
| 5 | OFF | 0.004348 | 0.008564 | 0.005796 | 0.011694 |
| 5 | ON | 0.057706 | 0.064321 | 0.061006 | 0.066638 |
| 15 | OFF | 0.005188 | 0.017228 | 0.004797 | 0.021496 |
| 15 | ON | 0.059631 | 0.074948 | 0.058806 | 0.080100 |
| 30 | OFF | 0.004587 | 0.029076 | 0.004821 | 0.043886 |
| 30 | ON | 0.059514 | 0.094255 | 0.075964 | 0.101984 |

### Perfil lejano: z=−800, MaxDistance/ESPMaxDistance=1500 en ambas versiones

| Personajes | Cámara | V3 ESP OFF (ms/frame) | V3 ESP ON | V3.1 ESP OFF | V3.1 ESP ON |
| --- | --- | --- | --- | --- | --- |
| 5 | OFF | 0.004942 | 0.010096 | 0.004607 | 0.008717 |
| 5 | ON | 0.065280 | 0.068629 | 0.063129 | 0.068422 |
| 15 | OFF | 0.005149 | 0.019219 | 0.004847 | 0.016432 |
| 15 | ON | 0.067088 | 0.094791 | 0.071242 | 0.077720 |
| 30 | OFF | 0.004835 | 0.032898 | 0.004526 | 0.025368 |
| 30 | ON | 0.067626 | 0.091543 | 0.066632 | 0.105197 |

No hay reducción consistente del coste total. El perfil cercano conserva las mismas comprobaciones de visibilidad y algunas mediciones empeoran; incluso el perfil lejano puede empeorar con cámara activa en esta corrida. No se promete mejora global de FPS ni coste cero de ESP OFF.

La reducción reproducible está en operaciones lejanas: con 30 personajes y ESP ON, **5670 → 1560 raycasts y 5670 → 1560 proyecciones** (−72.49%). El bucle manager sigue realizando 189 actualizaciones; la caché de observación/sincronización lejana configurada a 3 Hz ejecuta 52 comprobaciones por personaje frente a 189 previas. La cuantización del bucle impide interpretar “3 Hz” como exactamente tres muestras cada segundo. El coste es visibilidad/proyección menos reciente; una nueva oclusión lejana puede tardar la ventana de caché más el siguiente tick en reflejarse.

Los 720 invariantes verifican: pool e instancias estables tras calentamiento, conexiones sin crecimiento, cero llamadas a Players:GetPlayers durante la ventana medida y cero conexiones, render bindings y tweens activos tras Unload. No demuestran ausencia de toda fuga posible del motor.

## Reproducción y archivos completos

Ejecuta desde la raíz con Luau/luau-compile oficiales disponibles. El commit baseline V3 debe existir en Git local. Para comparar CPU, termina las otras cargas y ejecuta estas herramientas secuencialmente:

```bash
python3 scripts/calibrate_cam_v31.py
python3 scripts/benchmark_cam_v31.py
python3 scripts/benchmark_cam_v31.py --far
python3 scripts/calibrate_persistence_v31.py
```

Las regresiones se reproducen por separado:

```bash
python3 scripts/check_cam.py
python3 scripts/check.py
python3 scripts/check_pink.py
```

Los runners generan nuevos archivos en build/. Estos CSV/JSON publicados son copias exactas de la ejecución documentada; una nueva ejecución de CPU puede arrojar tiempos diferentes.

| Datos | CSV | Resumen / hash y referencias |
| --- | --- | --- |
| Calibración | [2304 filas](results/SEDWARE_V31_CALIBRATION.csv) | [JSON](results/SEDWARE_V31_CALIBRATION_SUMMARY.json) |
| CPU cercano | [24 configuraciones](results/SEDWARE_V31_CPU_NEAR.csv) | [JSON](results/SEDWARE_V31_CPU_NEAR_SUMMARY.json) |
| CPU lejano | [24 configuraciones](results/SEDWARE_V31_CPU_FAR.csv) | [JSON](results/SEDWARE_V31_CPU_FAR_SUMMARY.json) |
| Persistencia | [32 filas](results/SEDWARE_V31_PERSISTENCE.csv) | [JSON](results/SEDWARE_V31_PERSISTENCE_SUMMARY.json) |

Consulta la [guía V3.1](SEDWARE_V31.md) para configuración, diagnóstico y ejecución de los **23 casos nativos preparados** en [SedwareCamV31Test.rbxlx](../studio/SedwareCamV31Test.rbxlx). Se requieren Play y comprobaciones físicas/manuales en una experiencia propia: movimiento Local/Server, desplazamiento observado, cámara, ESP, paredes, controles después de respawn y streaming real con clientes. El runner no se ejecutó en Linux y ninguno de esos resultados se marca como aprobado.
