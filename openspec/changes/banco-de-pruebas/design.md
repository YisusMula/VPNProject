## Context

Ver `proposal.md` — Why. El dato que hace viable este cambio: durante el cambio
anterior se comprobó que `wireguard-go` compilado desde fuente permite levantar
un `wg-easy` con `wg0` real aunque el kernel no traiga WireGuard
(`CONFIG_WIREGUARD is not set`). El montaje existió y funcionó; lo que falta es
hacerlo repetible.

## Goals / Non-Goals

**Goals:**

- Que un comando responda a "¿sigue funcionando esto?" sin montar nada a mano.
- Comprobar **resultados observables**, no que los comandos no den error.
- Que el banco sea honesto sobre lo que no puede probar en cada entorno.

**Non-Goals:**

- Integración continua. El banco se ejecuta a mano; enlazarlo con un servicio
  externo es otro asunto.
- Cobertura exhaustiva. Se cubren los caminos que romperían el uso real.
- Probar la conectividad hacia internet real desde el túnel: depende del entorno
  y daría falsos negativos.

## Decisions

### D1 — WireGuard del kernel primero, espacio de usuario como respaldo

El banco comprueba si el kernel soporta WireGuard y, si es así, lo usa tal cual.
Sólo si no, intenta compilar la implementación en espacio de usuario.

*Motivo*: en el equipo del usuario —una Raspberry Pi o un mini-PC con kernel
moderno— el módulo está y no hay nada que compilar: el banco se ejecuta sin
dependencias añadidas. La compilación es la excepción, para entornos como el de
desarrollo de este proyecto.

*Consecuencia*: la imagen de prueba sólo se construye cuando hace falta, y se
etiqueta aparte de la imagen del producto para no confundirlas.

### D2 — Proyecto de Compose separado, nunca el del usuario

El banco levanta su stack con un nombre de proyecto propio y un volumen propio.

*Motivo*: es la única forma de garantizar el aislamiento que exige la
especificación. Reutilizar el proyecto del usuario significaría que una
ejecución del banco puede borrarle las claves de todos sus dispositivos, que es
exactamente el desastre que la copia de seguridad existe para evitar.

Por el mismo motivo el banco genera su propio fichero de configuración en un
directorio temporal y **nunca lee ni escribe el `.env` de la raíz**.

### D3 — Limpieza mediante `trap`, no al final del guion

Los recursos se eliminan desde una función registrada con `trap ... EXIT`.

*Motivo*: si la limpieza estuviera al final, una comprobación fallida bajo
`set -e` la saltaría, dejando contenedores y volúmenes huérfanos que además
harían fallar la siguiente ejecución por conflicto de puertos.

### D4 — Las comprobaciones verifican efectos, no códigos de salida

Cada comprobación mira el estado observable: que el dispositivo aparezca en el
listado, que el fichero contenga la ruta esperada, que el peer desaparezca del
servidor, que el cliente revocado deje de recibir respuesta.

*Motivo*: un script puede terminar con éxito sin haber hecho su trabajo. El caso
real de este proyecto: `deploy.sh` informaba de "servidor en marcha" con el
túnel caído, porque comprobaba que respondiera el panel.

### D5 — Los escenarios de red se cubren con entradas fijas

CGNAT, doble NAT y ausencia de herramientas no se pueden reproducir en el equipo
donde corre el banco. Se comprueban pasando salidas fijas conocidas a las
funciones de clasificación.

*Motivo*: es la única manera de verificar esa lógica, y son justo los caminos
que más importan al usuario —el diagnóstico de CGNAT decide si el proyecto le
sirve o no— y los que nunca se ejercitan en el día a día.

*Alternativa descartada — simular la red con espacios de nombres*: mucha más
maquinaria para verificar unas funciones que sólo clasifican texto.

### D6 — Omitir se anuncia; nunca se cuenta como superado

Cuando el entorno no permite una prueba, el banco la marca como omitida, dice
por qué, y lo refleja en el resumen final aparte de las superadas.

*Motivo*: un banco que dice "todo correcto" habiéndose saltado la mitad es peor
que no tener banco, porque da una confianza que no corresponde.

## Risks / Trade-offs

- **[Compilar la implementación en espacio de usuario tarda]** → Sólo ocurre
  donde no hay módulo de kernel, y la imagen resultante se reutiliza entre
  ejecuciones.
- **[El banco depende de la API de una versión concreta de la imagen]** → Es
  deliberado: si una actualización de la imagen cambia el contrato, el banco
  debe fallar. Precisamente para eso está.
- **[Un fallo del banco puede ser del entorno y no del producto]** → Los
  mensajes distinguen "no se pudo comprobar" de "se comprobó y está mal".
- **[Levantar contenedores exige que quien ejecute el banco pueda usar Docker]**
  → Mismo requisito que desplegar el proyecto; no añade nada.
