# SEDWARE V3.2 — auditoría del movimiento antiguo

Se leyó completo el archivo adjunto `message (8).txt`, sin ejecutar su GUI, sus callbacks ni sus cargadores remotos. La referencia contiene 2761 líneas y 112649 bytes; SHA-256 exacto:

```text
7573674d0ef56f6c4a278dd5d23fa7e1080bddb8054a39c5530c7ea776642375
```

Las referencias `L…` de este documento corresponden a ese adjunto. El archivo original completo no se incorpora al repositorio; aquí se documentan solamente las implementaciones solicitadas y sus consecuencias. Esta revisión estática no verifica movimiento físico en Roblox Studio o Da Hood.

## Lo descrito y lo encontrado

| Solicitud | Evidencia en el adjunto | Conclusión verificable |
| --- | --- | --- |
| Fly con Core, Weld, BodyPosition, BodyGyro y X | `HUYZMI_fake_script`, L1858; callback Fly1, L1863–1970 | El cuerpo completo está incluido. Se pueden reutilizar el concepto de dirección relativa a la cámara y el toggle, adaptando las APIs y el ciclo de vida. |
| Speed V2 con WalkSpeed 140 y nombre `xxx` | `WPEBFPJ_fake_script`, L1758–1796 | El cuerpo está incluido. Aplica 140 inicialmente, pero el bucle no mantiene esa propiedad de forma continua después de renombrar el Humanoid. |
| Speed V1 anunciado con Q | Texto de botón, L428; callback `WS_V1.MouseButton1Click`, L2043–2045 | El callback sólo descarga y ejecuta un recurso Pastebin identificado como `kHFGTSkV`. El algoritmo, el registro de Q y su limpieza no están incluidos en el adjunto. No se descargó ni ejecutó ese recurso. |

Los nombres `*_fake_script` son funciones Lua que crean un `LocalScript` como referencia de jerarquía y registran callbacks mediante el código que ya está ejecutándose. No son módulos independientes ni un mecanismo de autorización del servidor. El contenedor se intenta insertar en `game.CoreGui` en L118; esa escritura no es una operación disponible para una GUI ordinaria de una experiencia propia. Sedware conserva su GUI en PlayerGui.

## Cómo desplaza el personaje Fly1

1. Cada clic destruye cualquier `workspace.Core` existente, sin comprobar su propietario (L1866–1868). Crea un Part de tamaño 0.05 por eje (L1870–1872).
2. Un `spawn` coloca ese Part en Workspace y crea un Weld con `Part0 = Core` y `Part1 = LocalPlayer.Character.LowerTorso` (L1874–1880). El Weld hace que las fuerzas y el giro sobre Core afecten a la misma assembly del personaje. Depende de LowerTorso y, por tanto, de un rig R15; no hay ruta para R6.
3. `WaitForChild("Core")` no tiene timeout y espera sólo la presencia de la pieza, sin confirmar que el Weld se haya completado (L1882). El cuerpo no configura masa, colisión ni una identidad privada de Core.
4. `start()` crea BodyPosition y BodyGyro dentro de Core (L1890–1897). BodyPosition intenta alcanzar una posición objetivo con fuerza máxima infinita por eje; BodyGyro intenta alcanzar una orientación con torque máximo `9e9`. Son objetivos de los controladores físicos, no confirmaciones de que el personaje los haya alcanzado.
5. Cada iteración de `repeat wait()` activa PlatformStand sobre el Humanoid actual y avanza el objetivo de posición según WASD (L1898–1924). BodyGyro recibe el CFrame de la cámara (L1925–1931), incluyendo su inclinación y roll. La cámara misma no se escribe.
6. `mouse.KeyDown` y `mouse.KeyUp` guardan WASD; X alterna `flying` y reinicia `start()` al reactivar (L1939–1968). Al terminar una iteración que observe `flying == false`, destruye BodyPosition/BodyGyro y fija PlatformStand en false (L1932–1937). Core y el Weld permanecen.

La expresión de L1901 conserva la rotación anterior del gyro y reemplaza su traslación por la posición objetivo. W/S suman o restan el LookVector de la cámara multiplicado por `speed`; A/D trasladan en el eje X local de esa rotación anterior. Con una cámara estable, esto equivale a sumar los ejes Forward/Right de la cámara; al rotarla, la componente lateral puede usar la orientación de la iteración previa.

`speed` es un incremento de posición por iteración, no studs por segundo. Empieza en 10 (L1886), baja a 5 al detectar una iteración sin WASD (L1902–1904), y todas las expresiones `speed = speed + 0` lo dejan igual. No existe aceleración real del parámetro. La comprobación `speed > 10` no se alcanza con esos valores. Después de la primera espera en reposo, suele seguir en 5 hasta finalizar `start()`. Sin dt, la velocidad objetivo depende de la frecuencia del scheduler; tampoco hay normalización diagonal. La velocidad física alcanzada depende además del solver, la masa, el controlador y las decisiones del servidor.

## Problemas de Fly1 que no deben heredarse

| Evidencia | Problema |
| --- | --- |
| `flying`, `localplayer`, `plr` y `mouse` sin `local`, L1861–1885 | Estado compartido con otros callbacks y con otras ejecuciones; varios controladores pueden alterar la misma bandera. |
| Destruir Core por nombre y volver a crear conexiones en cada clic, L1866–1868 y L1939–1968 | Puede destruir una instancia ajena y acumular bindings. El bucle anterior no comprueba continuamente si perdió su Core. |
| Acceso directo a Character/LowerTorso/Humanoid/CurrentCamera, L1878, L1900, L1906 | No maneja carga parcial, R6, muerte, respawn ni cámara temporalmente ausente. El renombrado de Speed V2 rompe el acceso `Character.Humanoid`. |
| Cleanup únicamente después del `repeat`, L1932–1937 | Un error dentro del bucle puede saltarse la restauración. No hay bloque protegido ni cancelación por Destroy/respawn. |
| PlatformStand siempre false al terminar, L1936 | No restaura el valor previo; tampoco conserva el Humanoid concreto que modificó. Puede modificar el personaje nuevo al salir de una sesión antigua. |
| Desconexión del mouse sólo en KeyDown si desapareció Core, L1940 | Apagar con X conserva los bindings; cerrar la GUI sólo la destruye (L1709–1719). Las señales externas del mouse y los bucles no se limpian por destruir el botón. |
| Fuerza infinita, torque extremo y ausencia de dt/clamp | No hay límites físicos finitos, velocidad configurable ni independencia de frecuencia. |

W/S permiten ascender o descender al orientar la cámara, pero no hay Space/LeftControl propios en este callback. Tampoco existe un campo de velocidad numérica para Fly1. Esas opciones de V3.2 son una adaptación explícita de Sedware, no capacidades encontradas en el archivo antiguo.

## Qué hace y qué falla en Speed V2

El callback ON espera a que Character tenga `Humanoid` o `xxx`, obtiene únicamente `Humanoid`, comprueba Health y alterna la visibilidad de CheckBox1/CheckBox2 (L1763–1768). En el primer ciclo cambia el nombre a `xxx` y WalkSpeed a 140 (L1769–1772).

El detalle crítico es la condición interior `Character:FindFirstChild('Humanoid')`: después del renombrado deja de cumplirse. El `while wait()` sigue despertando, pero no vuelve a aplicar 140 ni evalúa su `break` interior mientras sólo exista `xxx`. Por ello, la descripción de un bucle que “mantiene la velocidad” no coincide con el flujo efectivo del código. Si otro sistema cambia WalkSpeed de `xxx`, este bucle no lo corrige.

El callback OFF obtiene `xxx`, muestra CheckBox1 y asigna WalkSpeed 16/nombre Humanoid. Un segundo después vuelve a asignar 16/nombre Humanoid usando la variable global `hum` (L1782–1793). El bucle ON puede entonces entrar otra vez, asignar 140 y, al ver CheckBox1 visible, restaurar 16 y salir (L1770–1776). Este orden depende del scheduler; 16 se fija sin conservar el valor original.

Otros fallos verificables:

- Si ON encuentra sólo `xxx`, la espera termina pero `hum` es nil; `hum.Health` falla. Si OFF encuentra sólo `Humanoid`, `hum2` es nil y también falla.
- La espera no valida primero que Character exista. El bucle no tiene salida expresa por muerte, respawn o cierre de la GUI.
- `hum` y `plr` son globales. Otros callbacks del archivo escriben esas mismas variables; el OFF retrasado puede restaurar una referencia diferente.
- Renombrar Humanoid rompe búsquedas por nombre usadas por Fly1 y por scripts de personaje. No aumenta de forma legítima la autoridad del cliente.
- No hay una prueba de desplazamiento o velocidad física. WalkSpeed 140 indica una propiedad local escrita, no un resultado aceptado por el servidor.

## Adaptación moderna dentro de una experiencia propia o autorizada

| Idea del archivo antiguo | Adaptación mantenible |
| --- | --- |
| WASD relativo a la cámara | Calcular una dirección con CFrame.LookVector/RightVector actuales, sumar Space/LeftControl según configuración y limitar su magnitud. Usar una velocidad en studs/segundo. |
| Core + Weld a LowerTorso | Un único Attachment propio en HumanoidRootPart, común en rigs R6/R15 válidos. No crear Core ni Weld; validar Character, Humanoid y root antes de activar. |
| BodyPosition que mueve un objetivo cada wait | LinearVelocity en coordenadas World con VectorVelocity configurable. Al soltar, reducir suavemente a cero; definir límites finitos suficientes para sostener la assembly autorizada, sin introducir valores infinitos. |
| BodyGyro que sigue toda la cámara | AlignOrientation puede orientar la assembly propia si se necesita. Usar una orientación horizontal sin roll/pitch artificiales; no escribir el CFrame de cámara. La decisión de orientar el personaje debe ser explícita. |
| PlatformStand true/false | Capturar propiedades del Humanoid concreto, conservar referencias y restaurar los valores previos durante OFF, error, respawn y Unload. Las restricciones pertenecen a una única sesión y se destruyen en todos esos caminos. |
| WalkSpeed 140 + renombrado | Speed configurable sobre el Humanoid sin cambiar su nombre; guardar el WalkSpeed original, detectar cambios externos y no disputar el servidor con un bucle de escrituras. |
| KeyDown/KeyUp y bucles por clic | InputBegan/InputEnded centralizados, una actualización de movimiento cancelable, keybinds validados y limpieza de señales. El cambio de foco limpia las teclas retenidas. |
| Indicador de checkbox | Separar estado solicitado, controlador instalado y movimiento medido. Usar AssemblyLinearVelocity como observación física y registrar rechazo/override; no anunciar ON por crear una instancia. |

LinearVelocity, AlignOrientation, Attachment, HumanoidRootPart y AssemblyLinearVelocity son APIs oficiales. BodyPosition y BodyGyro son controladores heredados/deprecados; no hay motivo para copiar sus límites extremos ni su pieza auxiliar. AssemblyLinearVelocity sirve para observar la velocidad de la assembly; escribirla repetidamente no reemplaza la autorización ni un controlador físico estable.

El código de Fly1 y Speed V2 no contiene una integración propia de servidor ni confirma propiedad de red. Un cliente puede observar una propiedad aplicada y aun así no conseguir el desplazamiento deseado. La ruta Server de Sedware necesita su controlador propio instalado y autorización concedida por la experiencia. Esta auditoría no demuestra compatibilidad de movimiento con Da Hood original.

Las otras funciones del archivo, los cargadores remotos, los cambios de seguridad y las comunicaciones del juego quedan fuera de esta adaptación. La GUI de Sedware, el Cam Lock y su selección no se reemplazan con la GUI antigua.
