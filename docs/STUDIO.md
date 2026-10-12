# Abrir, desarrollar y probar

## Archivo listo para Studio

1. Descarga `build/AimLab.rbxlx` y ábrelo en Roblox Studio con **Open from File**. Si necesitas reconstruirlo, ejecuta `python3 scripts/build_place.py` desde la raíz del proyecto.
2. Activa **View → Output** para ver errores y exportaciones de diagnóstico.
3. Ejecuta **Play**. El servidor crea suelo, spawn y tres esferas: `near`, `mid`, `far`, con desplazamiento lateral, reversas, salto y caída.
4. Minimiza el panel si tapa el escenario. Coloca el cursor cerca de una esfera dentro del círculo FOV. RMB orienta la cámara; F o **DISPARAR** envían tiros del perfil activo.
5. Activa **Debug Visualization** para ver el punto que usará el disparo. Para proyectiles con caída ese punto está por encima de la posición futura estimada del objetivo.

El archivo generado contiene el código completo; no requiere paquetes, HTTP habilitado, assets externos ni secretos. El servidor usa `Workspace:Raycast()` para hitscan y barridos de esfera relativa para blancos móviles + `Spherecast()`/raycast para obstáculos en proyectiles. El salto de los blancos es una trayectoria de laboratorio (aceleración vertical propia), independiente de `Workspace.Gravity` y de humanoides de otro juego.

## Editar desde archivos con Rojo (opcional)

Este proyecto también incluye `default.project.json`. Con Rojo instalado en tu equipo y su plugin en Studio:

```sh
rojo serve default.project.json
```

Conecta el plugin y sincroniza. Usa **Play**, no Run, para iniciar también el cliente. Rojo es opcional: `scripts/build_place.py` empaqueta exactamente las mismas fuentes y verifica que la serialización XML las preserve.

Estructura esperada en Explorer:

```text
ReplicatedStorage
  AimLab (Folder)
    Settings, Latency, MotionHistory, Predictor,
    Ballistics, Geometry, Weapons, Diagnostics (ModuleScript)
ServerScriptService
  AimLabServer (Folder)
    Main (Script)
StarterPlayer
  StarterPlayerScripts
    AimLabClient (Folder)
      Main (LocalScript)
      Interface (ModuleScript)
```

`AimLabRemotes` y `Workspace.AimLab` se crean durante la ejecución. No se necesita publicarlos por separado.

## Pruebas automatizadas fuera de Studio

Requieren Python 3 y las herramientas oficiales `luau` y `luau-compile`:

```sh
python3 scripts/check.py
```

El script compila todas las fuentes, ejecuta pruebas de comportamiento con Luau y genera el lugar. Falla si falta una herramienta o una prueba falla. Puedes indicar rutas con `LUAU` y `LUAU_COMPILE`. En el entorno preparado están en `/workspace/tools/luau-source`.

Instalación reproducible del compilador usado en este trabajo (Git + GNU make + g++):

```sh
git clone --depth 1 --branch 0.695 https://github.com/luau-lang/luau.git .tools/luau
make -C .tools/luau config=release luau luau-compile -j2
LUAU="$PWD/.tools/luau/luau" LUAU_COMPILE="$PWD/.tools/luau/luau-compile" python3 scripts/check.py
```

El tag usado resuelve a `1f6ff5d6f0072f2fab2adf35d1ffbaae7d848ad0`. Las pruebas usan un vector matemático de prueba: no emulan el motor de Roblox.

## Comprobación funcional requerida en Studio

Esta máquina Linux **no ejecuta Roblox Studio**. Las siguientes comprobaciones quedan pendientes y deben completarse allí:

| Prueba | Resultado esperado |
| --- | --- |
| Play | Aparecen los tres blancos y las seis pestañas; Output sin excepciones. |
| Sin blanco / blanco fuera de FOV | No se envían tiros y se informa falta de selección. |
| RevolverLab | Traza instantánea, cooldown aplicado, contador de tiros aceptados actualizado. |
| ProjectileLab | Proyectil visible y resultado al impactar, chocar o agotar vuelo. |
| Observation | Con blanco elegido aumenta el conteo de predicción a aproximadamente 5 Hz; RMSE independiente de tiros. |
| Auto ON/OFF | Manual usa segundos configurados; Auto responde gradualmente a RTT. |
| Delay simulado 0 → 0.15 → 0.25 → 0 | Cambia la edad de los snapshots, no el RTT del motor; no duplicar ese retraso en el offset. |
| Salto / caída / reversa | Cambia el estado; se reinicia historial y se atenúa aceleración acumulada. |
| Profiles / offsets | Cada arma conserva su offset durante la sesión, diagnóstico por perfil separado. |
| Reset | Restablece parámetros por defecto, sin crear GUI/conexiones extra. |
| Respawn / Stop → Play | Sin pérdidas crecientes de recursos; servidor y UI arrancan de nuevo. |
| Start Server con 2 Players | Datos y colas por jugador; cada cliente recibe su propio ping y telemetría. |
| Obstáculo propio entre tirador/blanco | La selección usa visibilidad; tiros ya en vuelo pueden chocar y reportar `obstacle`. |

La demora artificial solo retrasa snapshots. No emula pérdida de paquetes, jitter de remotes, colas de procesamiento ni toda la replicación del motor. Para validar latencia real, usa pruebas con clientes conectados y las opciones de emulación de red que ofrezca tu versión de Studio; verifica sus unidades y no sumes sus efectos dos veces.
