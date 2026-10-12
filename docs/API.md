# APIs y límites observables

Referencia consultada: documentación oficial `Roblox/creator-docs` en GitHub, archivos `content/en-us/reference/engine/classes/Player.yaml`, `Workspace.yaml` y `BasePart.yaml` (11 de octubre de 2026).

| Dato | API o fuente | Qué permite afirmar |
| --- | --- | --- |
| Ping | [`Player:GetNetworkPing()`](https://create.roblox.com/docs/reference/engine/classes/Player#GetNetworkPing), servidor y LocalPlayer en cliente | La documentación actual lo define como **ida y vuelta**, en segundos, excluyendo procesamiento/deserialización. El lab divide por dos para estimar un trayecto; supone simetría. No mide edad de replicación ni latencia total del disparo. |
| Tiempo compartido | [`Workspace:GetServerTimeNow()`](https://create.roblox.com/docs/reference/engine/classes/Workspace#GetServerTimeNow) | Reloj del servidor aproximado y suavizado en cliente. No es un cronómetro exacto ni una fuente segura de autorización del cliente. |
| Posición observada | `BasePart.Position` | Estado disponible localmente, que puede diferir del servidor por replicación. En el lab se transmiten snapshots con su timestamp de servidor. |
| Velocidad | [`BasePart.AssemblyLinearVelocity`](https://create.roblox.com/docs/reference/engine/classes/BasePart#AssemblyLinearVelocity) | Studs/s en el centro de masa. Está marcada `NotReplicated`: no garantiza una medición autoritativa en cliente. El lab manda la derivada de su trayectoria propia desde el servidor. |
| Estado humanoide | `Humanoid:GetState()` / `StateChanged` en una experiencia propia | Permiten identificar estados disponibles; no revelan la trayectoria futura. Los blancos analíticos de este lab publican sus propios estados. |
| Impacto | `Workspace:Raycast()`, simulación del servidor | El servidor comprueba el disparo del lab, obstáculos y su geometría. No prueba el hit registration de otro juego. |
| GUI / entrada | `ScreenGui`, `GuiButton.Activated`, `UserInputService`, `Camera:WorldToViewportPoint()` | Controles y selección de blancos dentro de esta experiencia. |

No hay API pública que garantice conocer el algoritmo del Revolver de Da Hood, sus remotes, dispersión, velocidad de proyectil, rewind, cooldown o procesamiento interno. `RevolverLab` es un perfil **de laboratorio hitscan**, con dispersión inicial cero para aislar errores; no representa esas características desconocidas.

`13.371600151062012` no aparece en el código ni se convierte en segundos. Su escala y fórmula originales son desconocidas. Prediction manual aquí se expresa en **segundos adicionales desde ahora**, además de la edad real de la muestra. No se promete acertar siempre: las inversiones de dirección futuras no son observables.
