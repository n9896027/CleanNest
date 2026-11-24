# CleanNest

**Gestión local del Mac y limpieza segura para flujos de desarrollo con IA.**

CleanNest reúne espacios de trabajo de Agentes, modelos locales, servicios, estado del sistema y ocupación del disco en una app nativa. Primero muestra las pruebas, después explica sus consecuencias y finalmente te deja decidir. Los archivos van a la Papelera de forma predeterminada; la IA nunca puede autorizar su eliminación.

[简体中文](README.md) · [English](README.en.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · **Español** · [한국어](README.ko.md)

[Descargar la versión oficial](https://github.com/n9896027/CleanNest/releases/latest) · [Verificación de 0.12.3](docs/VERIFICATION-0.12.3.md) · [Privacidad](PRIVACY.md) · [Seguridad](SECURITY.md)

## En desarrollo: inventario local completo de Agentes en 0.12.4

**0.12.4 (Build 54), candidato local aún no publicado**, clasifica las 23 apps de este Mac según su función real. Doce clientes independientes de IA/Agentes superaron la identificación por firma con muestras locales y pueden abrir la vista previa de desinstalación existente: ChatGPT, Claude, Doubao, Gemini, Grok Bot, Kimi, MiniMax Design, Muse, NewMax, Tabbit, ZCode y Xiaoyunque. Hermes Studio, Pi Agent y WorkBuddy son clientes independientes, pero permanecen en solo lectura con el motivo concreto de integridad de firma o confianza de distribución Apple insuficiente.

Cada copia gestionable debe coincidir con el Bundle ID, Signing ID y Team ID permitidos y cumplir `anchor apple generic`. Un Team ID en un certificado autofirmado no basta para hacerse pasar por un cliente oficial. La vista previa conserva Application Support, HTTPStorages, WebKit, preferencias, estado de ventanas, proyectos y credenciales; solo admite cachés y registros regenerables expresamente registrados. Las reglas en línea no pueden añadir rutas de eliminación.

Ocho apps relacionadas siguen visibles en un grupo separado de solo lectura, sin presentarlas como Agentes: CC Switch (selector de configuración API/proveedor), KimiCU (componente de automatización incluido con Kimi), MiniMax Hub 2 (iniciador local), WorkDaddy (iniciador de automatización de WorkBuddy), Claude Code URL Handler, shell auxiliar Hermes, Ollama (ejecutor de modelos locales) y YuanHub (banco de operaciones de contenido con asistente de IA integrado). Consulta el [inventario local de Agentes de escritorio](docs/AGENT_DESKTOP_INVENTORY.md) para ver las 23 clasificaciones, identificadores, pruebas de firma y límites. Reconocer muestras y probar rutas aisladas no equivale a desinstalar aplicaciones reales; no se desinstaló ningún cliente en esta iteración.

### Base de 0.12.3 — Build 53

- **Inventario de Agentes de escritorio.** Reconoce cada copia mediante el Bundle ID exacto, una firma válida y un Team ID permitido. Muestra el icono real del Finder, la versión, el build y la ruta.
- **Grok Bot verificado.** La muestra oficial 1.2.3 (`com.anysphere.sand` / `DCNK4UB866`) superó la detección con validación de firma de producción. No se ha verificado una muestra oficial de Meta Muse para Mac; esta versión no afirma compatibilidad ni inventa identificadores o carpetas.
- **Desinstalación conectada.** «Desinstalar Agent…» utiliza la vista previa, las comprobaciones de identidad, las seis fases de ejecución, los reintentos por elemento y la recuperación desde la Papelera del desinstalador existente. Los datos de aplicación de Grok Bot permanecen de solo lectura; las cuentas en la nube, los bots, el historial del navegador y los contenedores compartidos quedan fuera del alcance.
- **Reglas sin nuevos permisos remotos.** Las reglas en línea deben estar firmadas por el mismo certificado que CleanNest. Pueden ampliar la detección y la evidencia de solo lectura, pero no pueden añadir rutas de eliminación.
- **Actualizaciones sin Xcode ni CLT.** El cliente usa `pkgutil` y `spctl`, incluidos en macOS, para comprobar el tamaño, SHA-256, la firma Developer ID Installer y la evaluación de Gatekeeper. La máquina de publicación verifica por separado la notarización y el ticket insertado por Apple.
- **Descargas reutilizables.** Un paquete verificado se conserva al cerrar la ventana, si falla una consulta temporal o si no puede abrirse el instalador. Los límites de GitHub muestran una hora acotada para volver a intentarlo.

La interfaz se mantiene más clara desde 0.12.1: los candidatos aparecen antes que el diagnóstico, los registros de aplicaciones explican su origen y consecuencias, y la selección por lotes requiere confirmación.

## Descargar e instalar

1. Abre la [última versión oficial](https://github.com/n9896027/CleanNest/releases/latest).
2. Descarga `CleanNest-0.12.3-53.pkg` y comprueba su SHA-256 con el archivo `SHA256SUMS` de esa misma versión.
3. Abre el PKG y confirma la instalación en macOS. Se instala en `/Applications`.
4. Como alternativa, usa `CleanNest-0.12.3-53.zip`. Las reglas de reconocimiento se distribuyen por separado como `CleanNestAgentRules.zip` y no son necesarias para las reglas integradas.

**Requisitos:** macOS 14 Sonoma o posterior. El paquete Universal 2 contiene `arm64` y `x86_64` para Apple Silicon e Intel. No se necesitan Homebrew, Mole, Xcode, Terminal, una cuenta ni un motor de limpieza adicional para el uso normal.

La actualización siempre requiere que confirmes la descarga, que abras el instalador y que confirmes por última vez en macOS. CleanNest no se instala ni se sustituye silenciosamente. Si la versión antigua se detiene durante la validación, utiliza el PKG oficial de la página de la versión.

## Funciones principales

- Limpieza revisable de cachés de desarrollo, registros, instaladores y otros candidatos.
- Protección de archivos activos, comprobación de identidad y Papelera antes de una eliminación definitiva.
- Libro de ejecución persistente, recuperación por elemento y comprobación del espacio APFS real.
- Espacios de trabajo de Codex, Claude, Pi Agent, Kimi, WorkBuddy, Hermes, OpenClaw, Trae, MiniMax Hub y Xiaoyunque, con directorios registrados solo cuando existe evidencia fiable.
- Inventario por niveles de 23 apps: 12 clientes independientes verificados, 3 clientes independientes de solo lectura y 8 componentes o herramientas relacionadas; la vista previa de desinstalación conserva los datos privados descritos en el inventario.
- Procesos, puertos, modelos, clientes y servicios launchd de oMLX, Ollama, LM Studio y otros servicios locales.
- Métricas de CPU, memoria, disco, red, GPU, temperatura, ventiladores y batería.
- Navegador de almacenamiento, desinstalador de aplicaciones, mantenimiento y MCP local de solo lectura.
- Motor nativo integrado: las funciones deterministas no dependen de una IA ni de un servicio en la nube.

## Privacidad y seguridad

No hay cuentas, anuncios, telemetría ni nube propia en la versión actual de código abierto. La IA opcional solo acepta un servicio explícito en `127.0.0.1` y recibe metadatos limitados, no el contenido de los archivos. La comprobación de versiones consulta GitHub; puede desactivarse en los ajustes.

Las reglas de reconocimiento no pueden cambiar los permisos de ejecución. Las carpetas compartidas, los datos de usuario, los elementos gestionados por el sistema y los archivos de propiedad no demostrada se mantienen de solo lectura. Consulta la [política de privacidad](PRIVACY.md), el [modelo de amenazas](docs/THREAT_MODEL.md) y la [guía de permisos](docs/PERMISSIONS.md).

## Verificación y límites

Las pruebas automatizadas, la auditoría estricta de los tres idiomas de la app, la compilación Universal 2, las firmas Developer ID, la notarización y Gatekeeper se registran en el [documento de verificación de 0.12.3](docs/VERIFICATION-0.12.3.md).

Una compilación para Intel no equivale a probar un Mac Intel físico. Tampoco se han sustituido por pruebas unitarias la instalación limpia en macOS 14, la migración desde una copia autofirmada, la desinstalación real de Grok Bot ni todas las combinaciones de macOS y hardware. El documento distingue entre pruebas completadas, pruebas condicionadas y escenarios no ejecutados.

Este README español explica el producto y su versión; no implica que la interfaz de la app esté traducida al español. La app ofrece inglés, chino simplificado y chino tradicional.

## Desarrollo

```bash
git clone https://github.com/n9896027/CleanNest.git
cd CleanNest
swift test
swift run CleanNestSelfTest
./build.sh
open build/CleanNest.app
```

Las herramientas de desarrollo solo son necesarias para compilar el código fuente, no para instalar o actualizar el PKG oficial. El código se distribuye bajo la [licencia MIT](LICENSE).
