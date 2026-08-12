## 1. Corrección del aborto del diagnóstico

- [x] 1.1 Blindar el `read` sobre sustitución de proceso en `doctor.sh` para que una salida vacía no aborte bajo `set -e`. Verificar: con un JSON malformado, el diagnóstico llega al Resumen
- [x] 1.2 Degradar al camino de `wg show` cuando el JSON no parsea, en vez de informar de cero dispositivos. Verificar: la sección 5 no dice "no hay ninguno" cuando sí los hay

## 2. Infraestructura del banco

- [x] 2.1 Crear `tests/run-tests.sh` con `set -euo pipefail`, contadores de superadas/fallidas/omitidas y resumen final. Verificar: `bash -n tests/run-tests.sh`
- [x] 2.2 Implementar la selección de WireGuard: kernel si lo hay, espacio de usuario si no, omitir si ninguno (decisión D1). Verificar: la salida indica cuál se usó
- [x] 2.3 Usar un proyecto y un volumen de Compose propios, y una configuración en directorio temporal (decisión D2). Verificar: tras ejecutar, el `.env` y el volumen de la raíz siguen intactos
- [x] 2.4 Registrar la limpieza con `trap ... EXIT` (decisión D3). Verificar: forzar un fallo a mitad y comprobar que no quedan contenedores ni volúmenes del banco
- [x] 2.5 Contabilizar las pruebas omitidas aparte de las superadas (decisión D6). Verificar: el resumen las muestra por separado

## 3. Pruebas del ciclo de dispositivos

- [x] 3.1 Comprobar que el despliegue deja el túnel operativo, no sólo el panel. Verificar: la prueba consulta la interfaz del túnel
- [x] 3.2 Comprobar el alta en túnel completo: el fichero contiene `AllowedIPs = 0.0.0.0/0`. Verificar: la prueba falla si se cambia el valor esperado
- [x] 3.3 Comprobar el alta en modo sólo-LAN: contiene la subred y no contiene `0.0.0.0/0` ni línea `DNS`. Verificar: idem
- [x] 3.4 Comprobar que un nombre duplicado sale con código 2 y no altera el fichero original. Verificar: comparar la huella del fichero
- [x] 3.5 Comprobar que el listado muestra los dispositivos por su nombre. Verificar: buscar el nombre en la salida
- [x] 3.6 Comprobar que la revocación elimina el peer del servidor y deja intactos los demás. Verificar: contar los peers antes y después
- [x] 3.7 Comprobar que revocar un nombre inexistente falla sin tocar nada. Verificar: código distinto de cero y listado sin cambios

## 4. Prueba de túnel real

- [x] 4.1 Levantar un contenedor cliente con la configuración generada y comprobar que se establece la negociación. Verificar: la salida del cliente muestra una negociación reciente
- [x] 4.2 Comprobar que un cliente revocado deja de negociar: envía pero no recibe. Verificar: contrastar bytes enviados y recibidos
- [x] 4.3 Comprobar el enrutado del modo sólo-LAN: la subred doméstica va por el túnel y la ruta por defecto no. Verificar: inspeccionar la tabla de rutas del cliente
- [x] 4.4 Omitir este grupo con aviso si el entorno no puede levantar el túnel. Verificar: forzar la ausencia de WireGuard y comprobar el mensaje

## 5. Pruebas de copia de seguridad

- [x] 5.1 Comprobar que la copia produce un archivo con el estado del servidor. Verificar: listar el contenido del archivo
- [x] 5.2 Comprobar que restaurar devuelve el estado al de la copia. Verificar: comparar huellas antes y después
- [x] 5.3 Comprobar que un archivo corrupto se rechaza sin tocar el estado. Verificar: la huella no cambia

## 6. Pruebas de las funciones de detección

- [x] 6.1 Crear `tests/lib-test.sh` y las entradas fijas en `tests/fixtures/`. Verificar: `bash -n tests/lib-test.sh`
- [x] 6.2 Cubrir la clasificación de direcciones: privadas, CGNAT, inválidas. Verificar: cada caso con su resultado esperado
- [x] 6.3 Cubrir los escenarios de NAT con trazas fijas: simple, doble, CGNAT, no concluyente (decisión D5). Verificar: los cuatro resultados
- [x] 6.4 Cubrir la degradación sin herramientas: sin `traceroute` y sin `ping`. Verificar: resultado "no concluyente" y sin aborto
- [x] 6.5 Cubrir la medición de MTU contra un enlace de MTU conocido. Verificar: el valor medido coincide con el del enlace
- [x] 6.6 Cubrir la lectura de desviación horaria, incluida su degradación sin referencia. Verificar: ambos casos

## 7. Documentación

- [x] 7.1 Documentar en el README cómo ejecutar el banco y qué comprueba. Verificar: la sección existe
- [x] 7.2 Explicar qué se omite en un equipo sin WireGuard en el kernel. Verificar: la sección lo menciona
- [x] 7.3 Añadir `tests/` a la estructura de ficheros del README. Verificar: aparece en el árbol

## 8. Verificación final

> **Alcance de la verificación.** Es el primer cambio del proyecto que no
> necesita esta nota para excusarse: el banco se ejecutó de verdad y las 20
> comprobaciones de extremo a extremo pasan contra un servidor real, más 24
> comprobaciones de las funciones de detección.
>
> Se comprobó además que el banco **detecta regresiones**: al romper a propósito
> el acotado de `AllowedIPs` del modo sólo-LAN, dos comprobaciones fallaron y el
> banco terminó con código distinto de cero. Revertido el cambio, vuelve a pasar.
>
> Tres fallos del propio banco salieron a la luz al ejecutarlo, y los tres eran
> reales:
> - El hash bcrypt escrito en el fichero de Compose llevaba `$` sin escapar, así
>   que Compose los interpretaba y el panel rechazaba la contraseña. Es la misma
>   trampa que ya documentaba `.env.example`.
> - El contenedor cliente estaba en la red por defecto de Docker y el servidor en
>   la del proyecto de Compose: no se veían.
> - El punto de conexión del cliente apuntaba a un puerto fijo en vez de al
>   puerto propio del banco.
>
> El banco corre con implementación en espacio de usuario porque este kernel no
> soporta WireGuard. En el equipo del usuario usará el módulo del kernel, camino
> que aquí no se puede ejercitar.

- [x] 8.1 `bash -n` sobre todos los scripts, incluidos los del banco. Verificar: sin salida
- [x] 8.2 `shellcheck` a nivel de warning sin avisos. Verificar: incluye `tests/*.sh`
- [x] 8.3 Ejecutar el banco completo y comprobar que todas las pruebas pasan. Verificar: código de salida cero
- [x] 8.4 Comprobar que el banco detecta una regresión introducida a propósito. Verificar: romper una comprobación y ver que el banco falla
- [x] 8.5 Validar el cambio en OpenSpec. Verificar: `openspec validate banco-de-pruebas --strict`
