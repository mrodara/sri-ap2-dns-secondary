# Laboratorio DNS primario y secundario con BIND y Docker Compose

Este repositorio prepara un laboratorio aislado con dos servidores BIND y un cliente de consulta. Al recorrerlo aprenderás cómo se publican zonas DNS, cómo un secundario copia sus datos mediante transferencia de zona y cómo comprobar el entorno con Docker y `dig`, mientras practicas un flujo de cambios revisable con Git.

## Objetivos de aprendizaje

- Reconocer los servicios, la red privada y las direcciones del laboratorio.
- Distinguir DNS directo e inverso y leer registros SOA, NS, A, PTR, CNAME y MX.
- Explicar la diferencia entre un servidor primario y uno secundario de una zona.
- Observar qué permiten y qué restringen las ACL de transferencia.
- Crear, inspeccionar, detener y reconstruir servicios con Docker Compose.
- Usar ramas y commits para conservar un historial comprensible de los cambios.

## Inicio rápido

1. Clona el repositorio y entra en su directorio.
2. Comprueba la configuración y arranca el laboratorio.
3. Espera a que BIND esté listo y consulta ambos servidores con `dig`.
4. Detén los contenedores; conserva o elimina el volumen según necesites.

```sh
# Descarga el historial y los archivos del laboratorio; así trabajas sobre una copia local versionada.
git clone https://github.com/mrodara/sri-ap2-dns-secondary.git

# Cambia al directorio recién clonado; los comandos de Compose se ejecutan desde aquí.
cd sri-ap2-dns-secondary

# Valida la sintaxis y la configuración resuelta de Compose antes de crear contenedores.
docker compose config

# Construye las imágenes locales y crea la red, el volumen y los contenedores del laboratorio.
docker compose up -d --build

# Consulta el estado de los servicios para comprobar si los contenedores siguen activos.
docker compose ps
```

`docker compose ps` muestra el estado del proceso, no confirma que BIND ya acepte consultas ni que las transferencias hayan terminado. Continúa con las comprobaciones de esta guía y espera si todavía no hay respuesta.

## Topología

```text
                    red Docker bridge: dns-lab
                   subred 10.53.0.0/24

   ┌──────────────────┐       consulta DNS       ┌──────────────────┐
   │ Cliente           │ ───────────────────────> │ Primario         │
   │ 10.53.0.20        │                          │ 10.53.0.100      │
   │ dns-client        │                          │ dns-primary      │
   └─────────┬────────┘                          └────────┬─────────┘
             │ consulta DNS                                │ NOTIFY / AXFR
             └──────────────────────┐                      ▼
                                    │             ┌──────────────────┐
                                    └────────────>│ Secundario       │
                                                  │ 10.53.0.200      │
                                                  │ dns-secondary    │
                                                  └────────┬─────────┘
                                                           │
                                                  volumen secondary_zones
                                                  montado en /var/lib/bind/slave
```

| Servicio | Nombre de contenedor | IP fija | Función |
|---|---|---:|---|
| `primary` | `dns-primary` (`ns1`) | `10.53.0.100` | Autoridad primaria de las dos zonas y origen de las transferencias. |
| `secondary` | `dns-secondary` (`ns2`) | `10.53.0.200` | Autoridad secundaria; obtiene y conserva las copias de las zonas. |
| `client` | `dns-client` (`client`) | `10.53.0.20` | Cliente de diagnóstico con `dig`, `ping` y herramientas de red. |

Compose crea la red bridge `dns-lab` con subred `10.53.0.0/24` y puerta de enlace `10.53.0.1`. No publica puertos de DNS en el equipo anfitrión: las consultas descritas aquí se ejecutan desde contenedores de la red. El cliente tiene configurados como DNS el primario y el secundario.

## Árbol del repositorio

```text
.
├── Readme.md                         # Esta guía
├── compose.yml                        # Servicios, IP, red, montajes y volumen
├── client/
│   └── Dockerfile                     # Cliente con herramientas DNS y de red
├── conf/
│   ├── master/
│   │   ├── named.conf.local           # Zonas primarias y política de transferencia
│   │   ├── named.conf.options         # Escucha, consultas y recursión del primario
│   │   └── zones/
│   │       ├── db.aulasri.test        # Datos de la zona directa
│   │       └── db.10.53.0             # Datos de la zona inversa
│   └── slave/
│       ├── named.conf.local           # Zonas secundarias y ACL de notificación
│       └── named.conf.options         # Escucha, consultas y recursión del secundario
└── server/
    ├── Dockerfile                     # Imagen BIND compartida por ambos servidores
    └── docker-entrypoint.sh           # Prepara directorios y arranca el proceso indicado
```

Los ficheros de configuración se montan como solo lectura en los servidores. `compose.yml` conecta el directorio `conf/master/zones` del primario con `/etc/bind/zones`; el secundario recibe sus archivos de zona transferidos en el volumen `secondary_zones`.

## Requisitos y conceptos esenciales

### Requisitos

- Git para clonar el repositorio, crear ramas y registrar cambios.
- Docker Engine y Docker Compose v2, disponibles como `docker compose`.
- Conexión a Internet durante la primera construcción para obtener la imagen base y paquetes indicados en los Dockerfile.
- Recursos suficientes para tres contenedores Linux.

### Docker y Compose

Una imagen es la plantilla construida desde un Dockerfile; un contenedor es un proceso aislado creado a partir de esa imagen. Compose describe servicios relacionados, conecta sus redes y monta archivos o volúmenes. `docker compose up -d --build` construye las imágenes y arranca los servicios en segundo plano; `exec` ejecuta una herramienta dentro de un contenedor activo.

El primario y el secundario usan `server/Dockerfile`, que instala BIND 9, `dig` y utilidades. El cliente usa `client/Dockerfile`, que instala herramientas de diagnóstico y mantiene el contenedor activo mediante `sleep infinity`. `depends_on` ordena iniciar los servicios DNS antes que el cliente, pero no espera a que BIND esté listo ni a que las zonas se hayan transferido.

### DNS, BIND y zonas

DNS traduce nombres a datos; una zona es el conjunto de registros del que un servidor responde con autoridad. BIND (`named`) es el servidor DNS de este laboratorio. Un primario carga los archivos de zona configurados localmente. Un secundario mantiene una copia obtenida del primario por transferencia; no es una simple redirección de consultas.

El servidor escucha en loopback y en su IP del laboratorio, permite consultas desde `10.53.0.0/24` y desactiva recursión. Por tanto, el laboratorio responde por sus zonas autoritativas y no pretende resolver cualquier nombre de Internet.

## Zonas y registros configurados

| Zona | Tipo | Archivo primario | Uso |
|---|---|---|---|
| `aulasri.test` | Directa | `conf/master/zones/db.aulasri.test` | Relaciona nombres con direcciones y otros datos. |
| `0.53.10.in-addr.arpa` | Inversa | `conf/master/zones/db.10.53.0` | Relaciona direcciones de `10.53.0.0/24` con nombres mediante PTR. |

Los registros existentes en la zona directa incluyen:

| Nombre | Tipo y valor | Significado |
|---|---|---|
| `aulasri.test` | SOA `ns1.aulasri.test.` / `admin.aulasri.test.` | Metadatos de autoridad; serial `2026101902`. |
| `aulasri.test` | NS `ns1.aulasri.test.` y `ns2.aulasri.test.` | Declara los dos servidores autoritativos. |
| `ns1.aulasri.test` | A `10.53.0.100` | Dirección del primario. |
| `ns2.aulasri.test` | A `10.53.0.200` | Dirección del secundario. |
| `cliente.aulasri.test` | A `10.53.0.20` | Dirección del cliente. |
| `www.aulasri.test` | A `10.53.0.30` | Dirección de `www`. |
| `app.aulasri.test` | A `10.53.0.31` | Dirección de `app`. |
| `mail.aulasri.test` | A `10.53.0.40` | Dirección del servidor de correo. |
| `web.aulasri.test` | CNAME `www.aulasri.test.` | Alias cuyo destino es `www`. |
| `aulasri.test` | MX 10 `mail.aulasri.test.` | Servidor de correo con prioridad 10. |

La zona inversa contiene SOA con serial `2026101901`, los mismos dos NS y estos PTR: `100` a `ns1.aulasri.test.`, `200` a `ns2.aulasri.test.`, `20` a `cliente.aulasri.test.`, `30` a `www.aulasri.test.` y `40` a `mail.aulasri.test.`. En una zona inversa de red /24, el primer octeto variable ocupa el nombre a la izquierda de `0.53.10.in-addr.arpa`.

Los seriales directo e inverso son independientes; compáralos dentro de cada zona, no entre zonas como si debieran coincidir.

## Transferencias y controles de acceso

1. El primario declara ambas zonas `master` y permite transferencias únicamente a `10.53.0.200` mediante `allow-transfer`.
2. El primario envía NOTIFY al secundario explícitamente (`notify explicit` y `also-notify`).
3. El secundario declara ambas zonas `slave`, señala al primario `10.53.0.100` como `masters` y acepta notificaciones solo de esa IP.
4. Tras la notificación o al arrancar, el secundario solicita los registros de zona al primario mediante AXFR (transferencia completa) o IXFR (incremental, cuando esté disponible).
5. Las copias se guardan bajo `/var/lib/bind/slave`. El secundario configura `allow-transfer { none; };` para no ofrecer a otros clientes una copia transferible.

La ACL del primario limita AXFR al secundario conocido; no autoriza a cualquier contenedor de la subred. La ACL del secundario y las opciones de escucha limitan quién puede notificarle y consultar sus zonas. Las transferencias no usan una clave TSIG en esta configuración: la autorización mostrada se basa en la IP de origen. Es una barrera didáctica de red, no un sustituto de autenticación criptográfica en un entorno expuesto.

No hay puertos publicados al anfitrión y la recursión está desactivada. Aun así, esto no convierte una configuración de ejemplo en una política de producción: antes de exponer DNS habría que diseñar y revisar cuidadosamente escucha, ACL, autenticación de transferencia, actualizaciones, firewall y monitorización.

## Construir, iniciar e inspeccionar

Los resultados DNS de esta guía son expectativas derivadas de los archivos de configuración; no se ha observado aquí una ejecución del laboratorio. Si una consulta inicial falla, espera unos segundos y repítela: `depends_on` no es una comprobación de disponibilidad.

```sh
# Comprueba que Compose puede interpretar el modelo; esto detecta errores de sintaxis antes del arranque.
docker compose config --quiet

# Construye las imágenes y deja los tres contenedores ejecutándose en segundo plano.
docker compose up -d --build

# Muestra contenedores, estado y puertos declarados para distinguir ejecución de disponibilidad DNS.
docker compose ps

# Sigue los mensajes de los tres servicios para ver el arranque y posibles errores de BIND.
docker compose logs -f
```

Para salir del seguimiento de logs, pulsa `Ctrl-C`; esto termina el seguimiento en primer plano, no detiene los servicios. También puedes ver solo un servidor con `docker compose logs -f primary` o `docker compose logs -f secondary`.

### Comprobación de BIND y sus archivos

```sh
# Consulta el estado del proceso BIND del primario; se ejecuta dentro del contenedor que lo aloja.
docker compose exec primary rndc status

# Consulta el directorio configurado para las copias transferidas del secundario.
docker compose exec secondary ls -lh /var/lib/bind/slave

# Pide a BIND del secundario el estado de la zona directa para comprobar su serial y estado de carga.
docker compose exec secondary rndc zonestatus aulasri.test

# Pide a BIND del secundario el estado de la zona inversa para comprobar su serial y estado de carga.
docker compose exec secondary rndc zonestatus 0.53.10.in-addr.arpa
```

Se espera que el secundario llegue a servir ambas zonas y que el directorio configurado contenga archivos de zona una vez completada la transferencia. En esta configuración la ruta correcta es singular: `/var/lib/bind/slave`. Hay una inconsistencia existente que debes reconocer: `server/Dockerfile` crea `/var/lib/bind/slaves` (plural), mientras que el punto de montaje de Compose, el entrypoint y la configuración de zonas usan `/var/lib/bind/slave` (singular). El contenedor prepara la ruta singular al arrancar, y el volumen se monta allí; no uses el nombre plural como ubicación de las zonas.

### Consultas directas e inversas

Ejecuta las consultas desde el cliente para probar cada servidor directamente. `dig @IP nombre tipo` evita depender del orden de DNS configurado en el contenedor.

```sh
# Abre una consola en el cliente para ejecutar consultas desde la IP autorizada de la red del laboratorio.
docker compose exec client sh
```

Dentro de esa consola, ejecuta:

```sh
# Pregunta al primario por la dirección A de www; se espera 10.53.0.30.
dig @10.53.0.100 www.aulasri.test A +short

# Pregunta al secundario por el mismo registro para comprobar la copia de la zona; se espera 10.53.0.30.
dig @10.53.0.200 www.aulasri.test A +short

# Resuelve el PTR de 10.53.0.30 en el primario; se espera www.aulasri.test.
dig @10.53.0.100 -x 10.53.0.30 +short

# Resuelve el mismo PTR en el secundario para comprobar que también sirve la zona inversa.
dig @10.53.0.200 -x 10.53.0.30 +short

# Solicita el SOA directo a ambos servidores para comparar el serial esperado 2026101902.
dig @10.53.0.100 aulasri.test SOA +short
dig @10.53.0.200 aulasri.test SOA +short

# Solicita el SOA inverso a ambos servidores para comparar el serial esperado 2026101901.
dig @10.53.0.100 0.53.10.in-addr.arpa SOA +short
dig @10.53.0.200 0.53.10.in-addr.arpa SOA +short
```

En las dos consultas `SOA` de cada zona se espera el mismo serial en primario y secundario después de sincronizarse. Si se modifica un registro en el primario, hay que aumentar el serial de esa zona para que los secundarios detecten el cambio; el serial no es una fecha que BIND actualice automáticamente.

### Transferencia autorizada y denegada

El primario solo autoriza AXFR cuando la solicitud llega desde `10.53.0.200`. Por ello, haz la consulta desde el contenedor secundario para probar el camino permitido:

```sh
# Solicita la zona directa desde el secundario al primario; se espera una transferencia AXFR completa.
docker compose exec secondary dig @10.53.0.100 aulasri.test AXFR

# Solicita la zona inversa desde el secundario al primario para comprobar su autorización independiente.
docker compose exec secondary dig @10.53.0.100 0.53.10.in-addr.arpa AXFR
```

El resultado esperado es que aparezcan los registros de la zona y el marcador de fin de transferencia. Después comprueba desde el cliente que no está autorizado para AXFR:

```sh
# Intenta transferir la zona desde el cliente; se espera que el primario responda REFUSED.
docker compose exec client dig @10.53.0.100 aulasri.test AXFR

# Intenta AXFR contra el secundario; su allow-transfer none también debe rechazarlo.
docker compose exec client dig @10.53.0.200 aulasri.test AXFR
```

`REFUSED` es el resultado DNS esperado según las ACL. La forma exacta del mensaje de `dig` puede variar según la versión, pero no debe aparecer una transferencia completa desde el cliente. No ejecutes `AXFR` contra un servidor ajeno: es una operación de diagnóstico para zonas que administras.

Para salir de la consola del cliente escribe `exit`.

## Detener, reiniciar y reconstruir

```sh
# Detiene y elimina contenedores y red de Compose; conserva el volumen con nombre de las zonas secundarias.
docker compose down

# Vuelve a iniciar los servicios existentes; útil para comprobar el comportamiento de un reinicio.
docker compose up -d

# Reinicia los contenedores actuales sin reconstruir sus imágenes; úsalo para recargar procesos tras cambios compatibles.
docker compose restart

# Reconstruye las imágenes desde los Dockerfile y arranca de nuevo los servicios.
docker compose up -d --build
```

`docker compose restart` reinicia los contenedores actuales, mientras que `docker compose up -d --build` vuelve a construir imágenes cuando cambian los Dockerfile. Para cambios en archivos montados de configuración, reinicia o recrea los servicios para que BIND lea la configuración actualizada. Revisa los logs y repite las consultas después de cada operación.

### Persistencia y limpieza

`secondary_zones` es un volumen Docker con nombre montado en `/var/lib/bind/slave` del secundario. Sobrevive a `docker compose down` y permite conservar copias transferidas entre recreaciones de contenedores. Los archivos del primario, en cambio, viven en el repositorio y se montan desde `conf/master/zones` como solo lectura.

```sh
# Elimina contenedores y red y conserva los datos del volumen para el próximo arranque.
docker compose down

# Elimina también los volúmenes declarados por este proyecto; úsalo solo cuando quieras borrar las copias persistentes.
docker compose down --volumes
```

**Advertencia de pérdida de datos:** `docker compose down --volumes` borra el volumen `secondary_zones` y, con él, las copias persistentes del secundario. El secundario podrá volver a solicitarlas al primario en un siguiente arranque, pero la limpieza elimina el estado guardado y sirve para probar una transferencia desde cero. No uses esa opción si necesitas conservar el volumen.

## Solución de problemas

| Síntoma | Qué comprobar |
|---|---|
| `docker compose ps` muestra contenedores activos, pero `dig` falla al principio | `depends_on` no espera la disponibilidad de BIND. Revisa `docker compose logs primary secondary` y repite la consulta después del arranque. |
| El primario responde, pero el secundario aún no tiene zona | Revisa logs del secundario y `rndc zonestatus` para ambas zonas. Comprueba que `masters` apunte a `10.53.0.100`, que el primario permita `10.53.0.200` y que los servicios estén en `dns-lab`. |
| AXFR funciona desde el secundario pero no desde el cliente | Es el comportamiento esperado: el primario autoriza solo la IP secundaria y el secundario prohíbe transferencias a clientes. |
| Un nombre no devuelve la dirección esperada | Consulta el primario y el secundario por separado con `dig @IP`; revisa el registro y el serial en `conf/master/zones/db.aulasri.test`. |
| Una resolución inversa falta o apunta a otro nombre | Revisa el PTR en `conf/master/zones/db.10.53.0` y consulta la zona `0.53.10.in-addr.arpa`. |
| Cambiaste un registro y el secundario mantiene el valor anterior | Aumenta el serial de la zona modificada; observa el NOTIFY y vuelve a comparar SOA. Los seriales directo e inverso son independientes. |
| No encuentras archivos donde esperabas | Usa `/var/lib/bind/slave` (singular). Dockerfile contiene también una creación de `/var/lib/bind/slaves` (plural), pero esa no es la ruta configurada ni montada para las zonas. |
| El comando `docker compose` no existe | Comprueba que tienes Compose v2 integrado en Docker Engine; este repositorio usa el subcomando `docker compose`. |

## Flujo de trabajo con Git

Git registra versiones de los archivos del repositorio. Una rama permite preparar un cambio sin mezclarlo de inmediato con la rama base; un commit guarda un conjunto revisable de cambios. El índice (staging) permite elegir qué archivos entran en cada commit.

```sh
# Comprueba rama y archivos modificados antes de empezar para saber cuál es tu estado de partida.
git status --short --branch

# Crea y cambia a una rama de documentación para aislar el trabajo de la rama base.
git switch -c docs/guia-laboratorio-dns

# Inspecciona los cambios del README antes de prepararlos para detectar errores de contenido.
git diff -- Readme.md

# Añade solo el README al índice para que el commit no incluya archivos accidentales.
git add Readme.md

# Revisa exactamente qué contenido quedará guardado en el siguiente commit.
git diff --cached

# Registra la guía con un mensaje convencional que identifica su propósito documental.
git commit -m "docs: add DNS lab guide"

# Consulta el historial reciente para comprobar el commit y su mensaje.
git log --oneline --decorate -5

# Publica la rama en GitHub y configura el seguimiento para futuros push y pull.
git push -u origin docs/guia-laboratorio-dns
```

Después del `push`, abre una solicitud de cambios (pull request) desde la interfaz del repositorio: selecciona tu rama como origen y la rama base indicada por el proyecto como destino. Describe qué enseña la guía y cómo se revisó; pide revisión antes de integrar. Un pull request propone cambios para discusión, pero no modifica la rama base hasta que una persona con permisos los integre.

Si ya existe la rama de trabajo, no vuelvas a crearla con `-c`; cambia a ella con `git switch docs/guia-laboratorio-dns`. Antes de publicar, confirma que el remoto y la rama base son los esperados para tu curso.

## Ejercicios para estudiantes

1. Explica qué diferencia hay entre la respuesta del primario y la copia que ofrece el secundario. Apoya la explicación comparando sus SOA.
2. Consulta los registros A de `ns1`, `ns2` y `cliente` en ambos servidores; verifica si las respuestas coinciden con la tabla de zonas.
3. Compara los PTR de `.100`, `.200` y `.20` con sus nombres directos. ¿Qué datos faltan para las otras direcciones de la subred?
4. Cambia un registro A en la copia de trabajo, incrementa el serial de la zona y razona qué pasos permitirían observarlo en el secundario. No publiques cambios en un servidor compartido.
5. Ejecuta AXFR desde `secondary` y desde `client`. Explica por qué el origen de la consulta cambia el resultado y qué dirección autoriza el primario.
6. Detén y arranca el proyecto sin borrar el volumen. Después, elimina el volumen en un entorno de práctica y compara el comportamiento de la transferencia.
7. Crea una rama, realiza un cambio documental pequeño, revisa el diff y prepara un commit sin incluir archivos ajenos.

## Seguridad y alcance

- La red del laboratorio es privada para los contenedores y no publica el puerto 53 en el anfitrión.
- Las consultas se limitan a la subred declarada; la recursión está desactivada.
- El primario permite transferencias únicamente al secundario configurado; el secundario no permite transferencias a clientes.
- La autorización de transferencia se basa en IP; no hay TSIG configurado. No expongas este ejemplo directamente a redes no confiables.
- Los contenedores usan `container_name` fijo, que puede entrar en conflicto con otra copia simultánea del mismo Compose en el mismo motor Docker.
- La zona `.test` es de laboratorio y no debe confundirse con un dominio público.

## Lista de reproducibilidad

- [ ] Docker Engine y `docker compose` están disponibles.
- [ ] Cloné el repositorio desde la URL indicada y estoy en su directorio.
- [ ] `docker compose config --quiet` terminó correctamente.
- [ ] `docker compose ps` muestra los tres servicios activos.
- [ ] Los logs no muestran errores de carga de zonas y el secundario informa ambas zonas.
- [ ] Consulté los registros directos e inversos en primario y secundario.
- [ ] Comparé SOA dentro de cada zona y comprobé la transferencia permitida desde el secundario.
- [ ] Comprobé que el cliente recibe `REFUSED` al intentar AXFR.
- [ ] Sé que `docker compose down` conserva el volumen y `docker compose down --volumes` lo elimina.
- [ ] Revisé `git diff`, preparé solo los archivos deseados y guardé el cambio en una rama y commit propios.
