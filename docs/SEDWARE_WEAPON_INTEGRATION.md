# SEDWARE: predicción conectada a un arma propia

La causa de que el Revolver original siga la cámara es concreta: **PinkDotLock.lua no registra un controlador de disparo de Da Hood**. Seleccionar con C, calcular una posición y dibujar un DOT no altera el destino que el controlador original envía a su servidor.

## Auditoría del código existente

| Etapa | Código | Qué hace y quién consume el resultado |
| --- | --- | --- |
| Selección | [Session:LockTarget](../src/pink/Session.luau), Selection y ModeDetector | C selecciona un Player válido en primera o tercera persona. Conserva su identidad y parte. |
| DOT | [Session:_step](../src/pink/Session.luau) → Overlay:setDot | Proyecta **part.Position observada**. El DOT no representa la posición anticipada ni una dirección de bala. |
| Predicción | [Prediction:_predict](../src/pink/Prediction.luau) y predictComparisons | Usa Memory, velocidad, X/Y, Auto y los offsets configurados; devuelve registros active/manual/auto. Session:_step conserva esas comparaciones. |
| API | [Session:GetPredictedPosition](../src/pink/Session.luau) | Devuelve GetPrediction().position. No dispara, no mueve la cámara y no modifica ningún arma. DebugMode también consume el registro para diagnóstico. |
| Adaptador | [Session:CreateShotAdapter](../src/pink/Session.luau) y [ShotAdapter](../src/pink/ShotAdapter.luau) | capture obtiene una instantánea inmutable y record compara una referencia independiente. fire solamente llama al callback que suministre la integración; sin callback devuelve no-fire-callback. No busca armas ni intercepta comunicaciones. |
| Disparo anterior de prueba | Los scripts anteriores de src/pink_demo | Permitían enviar con F un raycast propio desde la cabeza, únicamente con bloqueo. No eran un Tool equipado, no tenían disparo normal sin bloqueo y no aplicaban daño. |
| Disparo de Da Hood | Ausente en el archivo autónomo | No existe ninguna suscripción al Revolver original, callback de su controlador ni conexión autorizada con su servidor. Por eso conserva la dirección de su mira. |

El archivo autónomo y los algoritmos compartidos se conservan. La integración añadida vive en los scripts y módulos del arma propia.

Durante la revisión del ciclo de vida también se corrigió el marcador de propietario de la sesión. Estaba directamente en PlayerGui, cuyos hijos Roblox reinicia al reaparecer; la GUI de Sedware ya usaba ResetOnSpawn=false. El marcador ahora está dentro de esa GUI persistente y la búsqueda incluye tanto esa ubicación como la ubicación anterior. Así, volver a ejecutar el script después de un respawn conserva la protección contra sesiones y conexiones duplicadas.

## Demostración completa para Studio

Abre [`studio/PinkDotLockTest.rbxlx`](../studio/PinkDotLockTest.rbxlx). Incluye el mismo PinkDotLock.lua y seis fuentes empaquetadas: el payload, tres módulos del arma y los scripts cliente/servidor. El servidor crea y entrega un **Tool SEDWARE Revolver**, de color rosado, con Handle y Attachment Muzzle. No requiere un loader HTTP ni otros archivos descargados por separado.

También puedes usar Rojo con [`sedware.project.json`](../sedware.project.json) en tu propio lugar. Los dos scripts de demostración comprueban RunService:IsStudio(); esta entrega está destinada a pruebas en Studio.

1. En Studio selecciona **Start Server con 2 Players**. Coloca ambos personajes a la vista y a menos de 350 studs. Abre Output en servidor y clientes.
2. Equipa **SEDWARE Revolver** desde la mochila y dispara con clic. Sin bloqueo, la dirección sale de la mira: centro en primera persona y cursor en tercera persona.
3. Apunta cerca del otro jugador y pulsa **C**. Comprueba el DOT y el aviso Locked. Mueve libremente la cámara y el cursor hacia otro sitio; dispara con clic manteniendo el bloqueo. El punto solicitado debe ser GetPredictedPosition(), aunque la mira apunte a otro sitio.
4. Comprueba en Output **PENDING** y después **CONFIRMED**. Una confirmación puede ser impacto en el objetivo, contacto con una pared o fallo. Solamente el raycast del servidor decide. El daño es la diferencia de Health tras Humanoid:TakeDamage; un ForceField puede producir impacto con daño cero.
5. Pulsa C para liberar el objetivo y repite el disparo normal. Prueba movimiento lateral, saltos, primera/tercera persona, obstáculos, muerte y respawn. El servidor entrega una sola arma por personaje y las conexiones se limpian al descargar o reemplazar la integración.

La demostración no garantiza acertar todos los tiros. X/Y conservan **0.1205 / 0.0800 segundos**; son valores iniciales de calibración. La física de esta arma propia es hitscan, rango 400 studs, cooldown 0.35 segundos y daño 25. No son propiedades conocidas del Revolver de Da Hood. Un horizonte que anticipe demasiado puede fallar; se informa ese fallo real y no se desplaza el personaje ni se fuerza un impacto para ocultarlo.

```mermaid
sequenceDiagram
    participant C as Cliente: Tool.Activated
    participant S as SEDWARE
    participant W as Servidor del arma propia
    C->>S: GetLockedTarget()
    alt Objetivo bloqueado
        C->>S: capture() y GetPredictedPosition()
        S-->>C: Instantánea y posición predicha
    else Sin bloqueo
        C->>C: Obtener punto de mira de la cámara
    end
    C->>W: Solicitud con identificador y aimpoint
    C->>C: PENDING; ningún impacto confirmado
    W->>W: Validar Tool, origen, edad, identidad y cooldown
    W->>W: Raycast desde Muzzle del servidor
    W->>W: Medir posición y daño reales
    W-->>C: Aceptado/rechazado; impacto y referencia independientes
    C->>S: record() si existe referencia válida
```

## Archivos y autoridad

| Archivo | Responsabilidad |
| --- | --- |
| [ClientController.luau](../src/pink_weapon/ClientController.luau) | Usa las APIs públicas existentes, diferencia Locked/Normal y mantiene disparos pendientes hasta la respuesta. Correlaciona sesión e ID; rechaza respuestas ajenas, duplicadas o caducadas. Si falta predicción con un bloqueo activo, informa el fallo. |
| [ServerController.luau](../src/pink_weapon/ServerController.luau) | Valida solicitudes y calcula dirección desde el origen autoritativo del arma. El resultado depende del raycast, nunca de la distancia entre predicción y blanco. |
| [WeaponSettings.luau](../src/pink_weapon/WeaponSettings.luau) | Parámetros y validación del arma de laboratorio, separados de la configuración de Sedware. |
| [Probe.client.luau](../src/pink_demo/Probe.client.luau) | Conecta Tool.Activated, la mira y los únicos eventos propios SEDWAREWeaponRemotes/Fire y Result. Lee la cámara sin modificarla. Muestra estados pendientes, rechazos y confirmaciones. |
| [Probe.server.luau](../src/pink_demo/Probe.server.luau) | Crea y registra el Tool propio, obtiene Muzzle.WorldPosition, hace Workspace:Raycast y Humanoid:TakeDamage. Gestiona jugadores, respawn y limpieza. |
| [build_pink.py](../scripts/build_pink.py) | Empaqueta exactamente las fuentes y verifica que el lugar generado coincide con ellas. |

El servidor exige el Tool propio realmente equipado y registrado para ese jugador, un personaje vivo, vectores finitos, origen cercano a su Muzzle, cooldown y timestamps dentro de límites. En Locked comprueba además Player, Character, parte permitida, vida y distancia. Un objeto con un nombre o atributo copiado no sustituye al Tool registrado por el servidor.

`accepted` significa que el servidor procesó un disparo válido. `hit` significa contacto físico con alguna superficie. `selectedTargetHit` significa que ese contacto corresponde al personaje bloqueado. `damageApplied` mide el cambio efectivo de vida. Son resultados distintos. Las referencias de posición/reloj del servidor se miden después del raycast y no se fabrican usando PredictionX/Y. La comparación de posición active/manual/auto tampoco demuestra un impacto.

## Da Hood original

El cliente público permite observar personajes, dibujar una GUI y leer la cámara. No proporciona una API universal para reemplazar el destino del Revolver de otra experiencia. Tool.Activated, por sí solo, tampoco reemplaza el controlador original ni la validación que su servidor realiza.

Para integrar esta ruta con ese Revolver hace falta que el propietario de Da Hood proporcione un controlador o interfaz de arma autorizada y añada la validación correspondiente en **su servidor**. No tenemos ese código ni una interfaz pública documentada. Esta entrega no inventa nombres de eventos, no modifica comunicaciones protegidas y no usa hooks, inyección o evasión de anticheat. **El loader de PinkDotLock.lua sigue cargando selección, DOT y predicción; no transforma el Revolver de Da Hood en el arma de Studio.**

## Verificación y diagnóstico

```sh
python3 scripts/build_pink.py
python3 scripts/check_pink.py
python3 scripts/check.py
```

Las pruebas automatizadas ejecutan los controladores y el payload existentes con transportes, APIs y raycasts sustituidos explícitamente por dobles. Cubren el puente Locked/Normal, espera de confirmación, impactos/fallos/obstáculos, daño, identidad, rechazos, timeout y limpieza. **No certifican la física, red, Tool ni render nativos de Roblox.** Esta máquina Linux no ejecutó Roblox Studio ni Da Hood. El lugar y la guía anterior permiten realizar esa verificación nativa pendiente.

Resultados con Luau oficial 0.695:

| Grupo | Pruebas | Comprobaciones | Fallos |
| --- | ---: | ---: | ---: |
| Controladores del arma propia, Prediction y ShotAdapter | 40 | 485 | 0 |
| Bundle real de Sedware conectado a ambos controladores | 12 | 264 | 0 |
| Selección, predicción, adaptador, GUI, arranque, LockKey y loader | 158 | 2.407 | 0 |
| DH PREDICTION LAB anterior | 96 | 75.895 | 0 |
| Total | **306** | **79.051** | **0** |

La compilación pasó para las 26 fuentes del conjunto Pink/SEDWARE. Se verificó que PinkDotLock.lua coincide con sus 13 módulos, que ambos lugares contienen exactamente sus fuentes y que los parámetros iniciales X/Y se mantienen. La regresión de respawn reproduce que la versión anterior dejaba dos listeners InputBegan y dos RenderStepped; la versión corregida conserva uno de cada uno.

En Output filtra por `[SEDWARE]` para la inicialización, C y Memory; por `[SEDWARE][Weapon]` para el cliente del arma, y por `[SEDWARE Weapon]` para el servidor. Ante Shot rejected consulta reason. Un timeout indica ausencia de respuesta del servidor y no confirma ningún impacto. Si aparece el DOT pero no Weapon READY, el cliente de arma propia no llegó a conectar sus módulos/eventos; no es una integración activa.

Si reinicias solamente el script del servidor durante Play, se destruyen sus eventos y armas anteriores. Para probar nuevamente toda la integración, detén Play y vuelve a iniciar servidor y clientes; el cliente informa la pérdida de sus eventos y limpia las solicitudes pendientes.
