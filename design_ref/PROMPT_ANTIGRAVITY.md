# Prompt para Antigravity · Sistema de UI completo (v2.4)

> **Cómo usarlo:** descomprime `paquete_ui.zip` dentro de tu proyecto de Godot como `res://design_ref/`. Luego copia en el chat del agente todo lo que está debajo de la línea. El agente leerá las pantallas desde esa carpeta.

---

## Material de referencia (está en `res://design_ref/`)

| Archivo | Para qué sirve |
|---|---|
| `INDICE.md` | Lista de las 61 pantallas agrupadas por página, con su id y tamaño. **Empieza por aquí.** |
| `pantallas.json` | La misma lista en datos: título, página, tamaño, rutas y **notas de UX de cada pantalla**. Úsala para generar tu plan y tus escenas. |
| `pantallas_png/<id>.png` | Cómo debe verse cada pantalla, a tamaño real. Es la referencia visual que debes igualar. |
| `pantallas_html/<id>.html` | La misma pantalla en HTML estático. Ábrela en un navegador y usa el inspector para leer medidas, colores, radios, sombras y textos exactos. **Si el PNG y tu interpretación difieren, manda el HTML.** |
| `fuente_dc/<id>.dc.html` | El archivo original del lienzo. El bloque `<script data-dc-script>` tiene los **datos de ejemplo separados del diseño** (listas de habilidades, estadísticas, misiones…). Úsalo para definir tus `Resource` de datos. |
| `tokens_estadisticas.js` | Las 16 estadísticas con nombre, abreviatura, color e icono SVG. |
| `hud_referencia.html` / `.png` | El HUD de combate Final v2 con estado editable (`CONFIG` y `STATE`). |
| `fonts/` · `assets/` | Fuente Barlow Semi Condensed (OFL) y el fondo de prueba. |

**Reglas para usar el material:**
1. No conviertas el HTML a Godot línea por línea. Úsalo como **especificación**: reconstruye cada pantalla con `Control`, contenedores, `Theme` y los componentes reutilizables de la sección 4.
2. Detecta lo que se repite entre pantallas (barra del Menú, tarjetas, chips, interruptores, barras de vida, ranuras) y conviértelo en **escenas reutilizables antes** de hacer las pantallas.
3. Los textos y números de las pantallas son **datos de ejemplo**. Nada fijo en las escenas: todo viene de datos.
4. Para cada pantalla terminada, saca una captura del mismo tamaño y compárala con su PNG. Reporta las diferencias que no puedas resolver.
5. Antes de programar, entrégame un **plan por pantalla** a partir de `pantallas.json`: qué componentes usa, qué datos necesita y en qué fase del roadmap va.

## 0. Antes de escribir código: validación con el roadmap (obligatorio)

Este proyecto ya tiene un roadmap y documentos de diseño propios. **No asumas que este prompt manda sobre ellos.**

1. Busca en el repositorio el roadmap y los documentos de diseño o de sistemas (por ejemplo `ROADMAP*`, `docs/`, `design/`, `GDD*`, issues o milestones). Léelos completos.
2. Lee también el proyecto de la wiki web (`mmo.elbalo.lol/wiki`, "Códice & Wiki viva"): su modelo de datos de entradas (tipo, tags, pionero, estado *Publicado*, changelog) y su pipeline de publicación.
3. Entrégame una **tabla de validación** antes de implementar, con una fila por cada sistema de la sección 3 y estas columnas:
   - **Sistema / pantalla**
   - **Estado en el roadmap:** ya planeado · parcialmente · no existe · contradice
   - **Hito o fase** donde encaja
   - **Dependencias técnicas** (servidor, base de datos, wiki, economía)
   - **Riesgos y preguntas abiertas**
4. Si algo **contradice** el roadmap o un documento existente, **detente y pregúntame**; no elijas por tu cuenta.
5. Las reglas de juego de la sección 2 **no se pueden simplificar ni omitir**. Si una no es viable técnicamente, dímelo explícitamente y propón alternativas.
6. Tengo más mecánicas ya definidas fuera de este prompt. Si encuentras huecos, **pregunta** en vez de inventar.

---

## 1. Objetivo

Implementar en **Godot 4.5 o superior (GDScript)** el sistema de interfaz completo del juego, un MMORPG multiverso, siguiendo el estilo **"Final v2"**:
- Panel grafito pegado al borde inferior con costados inclinados.
- Un solo color de acento, que cambia según el universo.
- Fuente Barlow Semi Condensed con números tabulares.
- Atajos visibles en cada botón.

Todo debe construirse con nodos `Control`, `Theme`, `StyleBoxFlat`, `_draw()` y shaders `canvas_item`, sin texturas para los marcos. La lógica pesada (simulador de daño, combinaciones de energías, planificador de rutas, economía) puede ir en Rust con **godot-rust (gdext)** como GDExtension; la interfaz se queda en Godot.

Accesibilidad: usa el soporte de lector de pantalla de Godot 4.5 (AccessKit) en todos los `Control`.

---

## 2. Reglas de juego que la UI debe respetar (no perder)

### 2.1 Nombres y navegación
- **Menú:** barra superior común a todas las ventanas. Pestañas: Equipo **C** · Poderes **N** · Misiones **L** · Mapa **M** · Códice **J** · Social **O** · Refugio **H** · Comercio **P** (Mercado, Tienda, Pase de batalla). A la derecha: búsqueda global (**Ctrl K**), oro, Prismas con botón «+» (abre la Tienda), Ajustes (**F10**) y cerrar (**Esc**).
- **Códice (J):** es solo el **libro de conocimiento del jugador**. No es el nombre del menú.

### 2.2 Dos monedas
- **Oro:** se gana jugando y no se puede comprar.
- **Prismas:** se compran con dinero real.
- Las dos están siempre visibles en el Menú, cada una con su icono y su color: oro `#f5c35b` (moneda) y Prismas `#7ee8ff` (gema).
- La **Tienda** y el **Pase de batalla** son pantallas **en construcción**: implementa la estructura con una franja «EN CONSTRUCCIÓN» y deja el contenido configurable por datos.
- **Por validar:** la tienda solo vende apariencia y comodidad, nada de poder; el pase da XP con cualquier actividad y lo ganado no caduca.

### 2.3 Conocimiento descubrible (Códice + wiki)
1. **Todo es descubrible:** objetos, criaturas, PNJ, lugares, poderes y fórmulas, recetas, mecánicas e historia.
2. Lo que el jugador no conoce aparece como **«???»** en todo el juego: nombre, icono, tooltip, mapa y chat. Hay un estado intermedio, **«Visto de lejos»**.
3. Al descubrir algo, el jugador elige entre dos caminos:
   - **Guardar el secreto.** Beneficio pequeño: ve el nombre y la ubicación, lo tiene marcado en su mapa y puede **crear y vender «Mapas del hallazgo»** en el mercado.
   - **Publicarlo en la wiki web.** Recibe reconocimiento de **pionero** (Hall of Fame y un título) y un bonus de oro. Después puede **proponer cambios** a la entrada.
4. **Publicar es permanente.** Si otro jugador publica antes, el primero pierde el título de pionero de la wiki. Esto se avisa con claridad en la UI.
5. Si un secreto deja de ser exclusivo (otro jugador lo descubre), se avisa al jugador, porque baja el valor de sus mapas.
6. **Propuestas a la wiki desde el juego:** la comunidad vota y el pionero decide durante las primeras 48 h *(por validar)*.
7. **Pionero de una tienda o PNJ:** el PNJ le hace una **oferta de inversión**. Es una **misión especial solo para ese jugador**; al completarla se convierte en **socio** y gana un **% de todas las transacciones de todos los jugadores** con ese PNJ.
   - Condiciones mostradas en la UI: cobra sin estar conectado (va al almacén del refugio), la participación se puede vender, el contrato se pausa si la tienda cierra y hay un solo socio por puesto.
   - «Pensarlo» guarda la oferta 7 días en el Códice; «Rechazar» la pasa al siguiente descubridor.
8. Hay un panel de **Inversiones** dentro del Códice con ganancias, tráfico, cobros, avisos y ventas de mapas.
9. Integra todo esto con el pipeline existente de la wiki web (`mmo.elbalo.lol/wiki`): mismo modelo de entrada, estado *Publicado*, pionero y changelog.

### 2.4 Poderes (varias ventanas)
- La pestaña Poderes tiene **sub-ventanas**: **Crisol · Atlas · Constelación · Afinidades**. Pueden abrirse una al lado de otra.
- **Crisol:** un poder se forma con 2 o 3 **energías** (hay *n* energías, así que la lista debe escalar), más una **forma** (proyectil, área, cono, aura, trampa) y un **ritmo** (instantáneo, canalizado, retardado).
  - La potencia depende de la **afinidad** con cada energía, y la afinidad sube usándola.
  - Las combinaciones nuevas se marcan como «¡NUEVA!». Hay pistas de PNJ y un botón «Probar en el maniquí».
  - El **conjunto** tiene 1 Núcleo, 6 poderes activos y 2 Ecos pasivos, más un bonus de resonancia cuando una energía se repite.
- **Atlas:** tabla energía × energía (la diagonal son energías puras). Estados: descubierta (con número de fórmulas), pista y desconocida. Debe crecer sola si se añade una energía nueva.
- **Constelación:** árbol pasivo **de la clase**. Sus ramas son energías y cada nodo indica a qué poderes del Crisol afecta. **Se mantiene** junto al Crisol; no lo reemplaza.

### 2.5 Refugio («Bolsillo del Umbral»)
- Es una isla entre universos donde **viven tus personajes en versión chibi** y trabajan.
- **Vista en corte lateral** (la isla vista de lado): superficie con parcelas, nido y portal; debajo, salas dentro de la roca organizadas por pisos. **Es el mismo diseño en PC (horizontal) y en móvil (vertical).** Sustituye a la vista isométrica.
- Sub-ventanas: Refugio (con modo **Construir, B**) · **Producción** · Expediciones · Pispa · Mejoras. Fabricación se abre desde la Forja.
- **Construir:** se llenan huecos de la roca arrastrando salas desde un cajón inferior.
  - La sala que estás colocando muestra si cabe y qué bonus da por vecindad.
  - Dos salas iguales contiguas se **fusionan** en una sala doble.
  - La roca se **excava** para abrir huecos; en lo profundo hay salas «???» que entran al Códice al descubrirse.
- **Habitantes:** se arrastran a una sala; la UI indica dónde rinde más cada uno («ideal +20 %»). Un amigo puede **prestarte un personaje** unas horas.
- **Marca propia:** el Refugio se llama «El Nido» (provisional; alternativa: POKET) y tiene insignia; lo fabricado lleva el **sello de artesano** del jugador.
  - Los chibis son los obreros.
  - Los Prismas sirven solo para acelerar o decorar; nunca son obligatorios.
- **Producción:** cadenas de materias → talleres → productos → destino (mercado, misiones, mejoras, Pispa). Los atascos se ven en rojo con su motivo y soluciones en un clic.
- **Expediciones:** los personajes secundarios suben de nivel en ellas. Tienen decisiones durante el viaje, también desde la app móvil; si el jugador no responde, eligen la opción segura.
- **Pispa:** mascota recolectora, al estilo del gallo de *Arc Raiders*. El jugador elige qué busca y la opción ligada a su misión actual aparece marcada con ★. Tiene bolsa con límite, rasgos, cariño y un diario de hallazgos.
- **Nunca castigar por no entrar:** la producción sin conexión tiene un tope de 12 h y nada se pierde.
- Las sugerencias del refugio deben apuntar a una **meta real** del jugador: una misión, una receta o un personaje.

### 2.6 Iconos de estadísticas
Cada estadística tiene **icono + color propio + texto**; nunca se usa solo el color. Se aplica en el HUD de combate, en Equipo, en las comparaciones, en los tooltips y en la wiki web. Ver el anexo A.

---

## 3. Inventario de pantallas (todas deben existir como escenas)

| Grupo | Pantallas |
|---|---|
| Entrada | Launcher (instalación progresiva, notas «qué cambia para ti») · Inicio de sesión (llave de acceso o QR, accesibilidad antes de entrar) · Selección de personaje · Creación (probar la clase 5 min, vista chibi) · Pantalla de carga (consejos según el destino) |
| En el mundo | HUD de combate (modos Combate/Exploración, estadísticas con iconos junto al retrato) · HUD de raid (sanador, con daño previsto) · Diálogo con PNJ · Oferta de inversión · Muerte y reaparición · Menú radial de señales · Antesala de mazmorra · Resumen de mazmorra |
| Menú | Equipo · Poderes (Crisol, Atlas, Constelación, Afinidades) · Misiones (con planificador) · Mapa del multiverso · Códice (Entradas, Mis secretos, Publicados, Inversiones, Propuestas a la wiki) · Social y buscador de grupo · Refugio (7 sub-ventanas) · Mercado · Fabricación · Colecciones · Tienda* · Pase de batalla* · Ajustes · Editor de interfaz y accesibilidad |
| Fuera del juego | App compañera (refugio, expediciones, agenda) · Wiki web (entrada con ficha de estadísticas, pionero y propuestas de cambio) |

\* = en construcción.

---

## 4. Arquitectura en Godot

- `res://ui/theme/hud_theme.tres` + `hud_tokens.gd`: colores, radios y tamaños de la v1, más las estadísticas del anexo A y las dos monedas.
- `res://ui/menu/menu_bar.tscn`: la barra común, reutilizada por todas las ventanas. Cada ventana declara su pestaña activa y su sub-navegación.
- Componentes reutilizables: `stat_row`, `stat_chip`, `currency_label`, `subnav`, `card`, `chip`, `switch`, `ability_slot`, `item_slot`, `chibi_avatar`, `progress_ring`, `under_construction_banner`.
- **Todo dirigido por datos:** ninguna pantalla tiene textos ni números fijos. Usa `Resource` o JSON para estadísticas, energías, entradas del Códice, edificios y ofertas.
- **Estado de conocimiento por jugador:** un servicio único, `KnowledgeService`, con `is_known(id)`, `visibility(id)` (que devuelve `unknown`, `seen`, `known_secret` o `published`) y `display_name(id)` (que devuelve «???» si no se conoce). Todas las vistas lo consultan; ninguna decide por su cuenta.
- **Economía:** `CurrencyService` con oro y Prismas separados, y un registro de transacciones (necesario para el % de los inversores).
- **Refugio:** una vista isométrica con `TileMapLayer` en modo isométrico, edificios en una escena aparte, y un sistema de colocación con validación de cabida y bonus por cercanía.
- **Accesibilidad:** cada `Control` interactivo con nombre accesible, navegación con teclado y mando, modos de daltonismo (cambian los colores, no los iconos), escalado de texto y la opción reducir movimiento.

---

## 5. Plan de trabajo

1. **Tabla de validación con el roadmap** (sección 0) y mis respuestas. No avances sin ellas.
2. Theme, tokens, iconos de estadísticas y componentes base.
3. Menú común y navegación entre ventanas (incluidas las sub-ventanas).
4. HUD de combate y HUD de raid.
5. `KnowledgeService` + Códice + «???» en todo el juego + publicar en la wiki (con el pipeline existente).
6. Oferta de inversión, misión especial e Inversiones.
7. Poderes: Crisol, Atlas y Constelación.
8. Refugio: vista general, construcción, producción, expediciones y Pispa.
9. Resto de ventanas; Tienda y Pase como esqueleto.

Al final de cada etapa, saca capturas y compáralas con los PNG de `design_ref/screens/`.

---

## Anexo A · Estadísticas (icono SVG 24×24 de trazo + color)

| Clave | Nombre | Abrev. | Color | Trazo (`path d`) |
|---|---|---|---|---|
| dano | Daño de ataque | DA | `#ff9a4d` | `M14 4h6v6L10 20l-6-6zM4 14l6 6M3 21l2-2` |
| poder | Poder de habilidad | PH | `#a58bff` | `M12 3v5M12 16v5M3 12h5M16 12h5M6 6l3 3M15 15l3 3M18 6l-3 3M9 15l-3 3` |
| armadura | Armadura | ARM | `#e0b04a` | `M12 3l7 3v6c0 4.5-3 7.5-7 9-4-1.5-7-4.5-7-9V6z` |
| resmag | Resistencia mágica | RM | `#4fc8ff` | `M12 3l8 4.5v9L12 21l-8-4.5v-9zM12 8l4 2.3v4.4L12 17l-4-2.3v-4.4z` |
| velatq | Velocidad de ataque | VA | `#ffd36b` | `M5 6l6 6-6 6M12 6l6 6-6 6` |
| celeridad | Celeridad | CEL | `#b8f0ff` | `M7 3h10M7 21h10M8 3c0 5 8 5 8 9s-8 4-8 9M16 3c0 5-8 5-8 9` |
| critico | Golpe crítico | CRÍT | `#ff5d5d` | `M12 3v5M12 16v5M3 12h5M16 12h5M12 9a3 3 0 1 0 0 6a3 3 0 1 0 0-6` |
| velmov | Velocidad de movimiento | VM | `#9fe36a` | `M3 17c4 0 6-2 8-6s5-6 10-6c-1 6-4 12-11 12H3zM8 14l4-4` |
| penarm | Penetración de armadura | PEN | `#ff7a59` | `M3 21L21 3M15 3h6v6M6 9l-2 2 9 9 2-2` |
| penmag | Penetración mágica | PEN M | `#d08bff` | `M3 21L13 11M13 11a4 4 0 1 1 4 4M17 7h.01` |
| robo | Robo de vida | RV | `#ff4d7a` | `M12 3C9 7 6 10 6 14a6 6 0 0 0 12 0c0-4-3-7-6-11zM10 13l2 3 2-3` |
| omni | Omnivampirismo | OMNI | `#e66bc4` | `M8 4C6 7 4 9 4 12a4 4 0 0 0 8 0c0-3-2-5-4-8zM16 8c-2 3-4 5-4 8a4 4 0 0 0 8 0c0-3-2-5-4-8z` |
| alcance | Alcance | ALC | `#c3ccd3` | `M3 12h18M7 8l-4 4 4 4M17 8l4 4-4 4` |
| tenacidad | Tenacidad | TEN | `#9a7bff` | `M12 7a2 2 0 1 0 0-4a2 2 0 1 0 0 4M12 7v14M5 14a7 7 0 0 0 14 0M8 11h8` |
| curacion | Curación y escudos | CUR | `#4fe39a` | `M12 3l7 3v6c0 4.5-3 7.5-7 9-4-1.5-7-4.5-7-9V6zM12 9v6M9 12h6` |
| regen | Regeneración | REG | `#6fe0a0` | `M12 20s-7-4.5-7-10a4 4 0 0 1 7-2.5A4 4 0 0 1 19 10c0 5.5-7 10-7 10zM12 10v5M9.5 12.5h5` |

Reglas de uso:
- Tamaños: 16 px en el HUD, 20 px en comparaciones, 24 px en fichas.
- El color de una estadística no se reutiliza para otra cosa en la misma vista.
- Mejoras y empeoramientos llevan ▲▼ además del verde y el rojo.

## Anexo B · Energías iniciales (la lista es abierta)

Vacío `#b47bff` · Calor `#ff7a45` · Eco `#7fe0ff` · Pulso `#5aa9ff` · Runa `#f5b546` · Savia `#4fe39a` · Hierro `#b8c3ca` · Marea `#3f8fd6` · Sombra `#8a7aa8` · Luz `#fff1a8`

## Anexo D · Refugio móvil y continuidad PC ↔ móvil

- La app móvil es el **refugio jugable**, no solo avisos. Usa el mismo estado del servidor que el PC; debe haber «Seguir en el móvil» y «Seguir en el PC».
- **Zona del pulgar:** la acción principal («Recoger todo») va abajo, a 56 px de alto; nada crítico en la parte superior.
- **Ronda de 2 minutos:** lista guiada con lo pendiente (recoger, decisiones de expedición, replantar, vaciar la bolsa de Pispa) y un estado final «Todo al día».
- **Avisos con presupuesto:** máximo 3 al día, elegidos por el jugador, con horario de silencio. Sin rachas, sin cuentas atrás falsas y sin castigo por no entrar.
- **Sin conexión:** las acciones se encolan y se envían al recuperar la señal.
- **Refugio de bolsillo en PC:** mini-ventana del refugio disponible en colas, antesalas y pantallas de carga (tecla **H**).
- **Descubrimientos:** al descubrir algo, el HUD muestra un aviso («???» → nombre, «eres el 1.º») y lo guarda como secreto en la bandeja **«Por decidir»** del Códice; no interrumpe el combate.

## Anexo E · El Nido v1: depa, vecindad y spawn compartido

- En la versión 1 el refugio es un **depa** acogedor en corte lateral con todo dentro: azotea-huerto, balcón con macetas, cocina, taller, mesa de mapas, despensa y sótano.
- **Los muebles son las estaciones:** al colocar un mueble-estación, el cuarto cambia de función. Decorar sube el **confort**, que mejora el descanso y la producción.
- Los depas están en una **vecindad** con un **patio común que es el punto de aparición de todos los jugadores** (zona segura). El patio tiene fuente, tablón, buzones, mercadillo de vecinos, portal al mundo y escalera a los depas.
- El edificio muestra qué vecinos están en casa; amigos y gremio se resaltan. Hay proyectos vecinales cooperativos y mudanza gratis semanal para vivir con amigos.
- **Terrenos** (fase posterior, se venderán): una segunda casa alrededor de la vecindad. El depa nunca se pierde. Deja la arquitectura preparada para más de una propiedad por jugador.

## Anexo F · Administración y personajes especiales

- **Consola del equipo** (fuera del cliente o con rol protegido): Resumen, Moderación, Personajes especiales, Economía, Wiki y Registros. Todo queda en un registro de auditoría inmutable.
- **Moderación:** el caso reúne reportes, historial y contexto del chat; motivo obligatorio, vista previa del mensaje al jugador, segunda firma para suspensiones largas y cola de apelaciones.
- **Personajes especiales:** son **personajes que un admin asigna a un espacio libre de un jugador**, con duración y zona. Plantillas: Narrador, Semidiós, Streamer invitado, PNJ viviente, Observador.
  - Poderes configurables: no recibe daño, sin amenaza, volar con cámara libre, invisible y aparecer (con destello visible), viaje instantáneo (la única excepción a «no hay teletransporte»), invocar encuentros de una lista aprobada, anuncios de zona.
  - **Pueden entrar a JcJ, mazmorras y raids** para contar historias, pero no hacen daño ni cuentan en marcadores.
  - Influyen poco: un **«Don menor»** que da +5 de vida a un jugador (1 cada 2 min).
  - No comercian durante la escena; **reciben una recompensa al terminarla**, fijada por el equipo. Lo que dan a otros sale de un presupuesto con tope.
  - **Sin estrella ni etiqueta:** se reconocen por su barra de vida con **borde dorado (inmune)** y su marco de rango (ver Anexo G).
  - Herramientas de transmisión: ocultar nombres de jugadores, retardo de chat, ocultar ubicación. Los jugadores pueden salir de una escena o pedir no aparecer en cámara.
- Valida en el roadmap los roles y permisos (admin, moderador sénior, moderador) antes de implementar.

## Anexo G · Barras de vida y marcos (estilo LoL)

- **Color de la vida:** verde = tú · amarillo = otros jugadores y PNJ neutrales · rojo = amenazas (enemigos, jugadores hostiles) · *propuesta:* turquesa = tu grupo.
- **Insignia de nivel o rango:** a la **izquierda** para todo lo no hostil (tú, jugadores, PNJ neutrales); a la **derecha** para amenazas (enemigos, élites, jefes, jugadores con PK alto).
- **Barra segmentada** (una marca cada X de vida), con tramo blanco para el escudo.
- **Borde de estado:**
  - dorado con brillo = inmune;
  - brillo verde = curándose;
  - rojo discontinuo = desangrándose;
  - doble borde rojo = PK activo (acaba de atacar a un jugador);
  - gris discontinuo = dormido (jugador desconectado);
  - turquesa fino = en zona segura.
- **Marco de la insignia:** al principio muestra el nivel; con la progresión pasa a marcos de rango (plata, oro…). Roles especiales:
  - administrador = ángel (alas);
  - moderador = caballero (escudo azul);
  - narrador = pluma dorada;
  - creador = cámara violeta;
  - jugador con PK alto = calavera roja «Matahumanos», a la derecha.
- Enemigos: normal (número) · élite (rombo dorado) · jefe (corona, más segmentos).
- Implementar como un componente `HealthPlate` reutilizable (mundo, objetivo, grupo, raid), con `StyleBoxFlat` para los bordes y un shader para el brillo.

## Anexo H · Mundo persistente

1. **Al desconectarte, tu personaje se queda en el mundo.**
2. Hay **zonas seguras intermedias** para salir y volver sin riesgo, y **reconexión rápida de 3 min** si se cae la conexión.
3. Si no extraes, hay consecuencias. La pantalla de salida ofrece:
   - **Extraer** a zona segura (con ruta y tiempo);
   - **Acampar** (fogata, el grupo puede vigilar, riesgo medio);
   - **Salir ya** (riesgo alto; mantener pulsado).
4. Si muere: reaparece en la última zona segura, la **bolsa segura** (3 objetos) se conserva y el resto queda en un **fardo** recuperable durante 30 min.
5. Al volver: pantalla **«Mientras dormías»**, con línea de tiempo, quién te defendió y repetición del ataque.
6. **No hay teletransporte:** se camina o se usan viajes rápidos (caravana, montura, dirigible), cada uno con tiempo, coste y riesgo por tramos. Las postas y atajos se descubren (Códice); un atajo secreto se puede vender como mapa.
7. **Incursiones** rápidas (10–15 min), medias (30–40 min, con salida a mitad) y largas (horas, por tramos con campamentos que guardan el progreso). El botín solo se conserva al extraer; existe la bengala de extracción.
8. El Nido se camina cuando el personaje está extraído; si está en el mundo, se gestiona a distancia. *Por validar.*

## Anexo I · Creadores de contenido y otras pantallas nuevas

- **Estudio de repeticiones 3D:**
  - Repeticiones de raids, mazmorras, arenas, salas concretas y escenas de narrador.
  - Cámaras: libre, seguir jugador, órbita al jefe, cenital, primera persona y ruta guardada.
  - Línea de tiempo con mecánicas, muertes, momentos y marcas propias; velocidad de 0,25× a 2×.
  - Capas activables: áreas de daño, rutas, números, barras de vida, nombres e interfaz.
  - Exportar clip en 16:9 o 9:16; compartir por código.
  - Privacidad: quien no quiere salir aparece como «Aventurero».
- **Trato entre jugadores:** cara a cara, con valor de mercado de cada lado; los objetos no descubiertos se muestran como «???»; doble confirmación que se borra si algo cambia; se pueden vender Mapas del hallazgo.
- **Consola › Economía:** entradas y salidas de oro del día, socios de PNJ con más ingresos, y palancas con simulación previa y segunda firma.

## Anexo C · Preguntas abiertas (pregúntame antes de decidir)

1. Nombre definitivo de la moneda premium. «Prismas» es provisional.
2. Rangos de % para los socios de PNJ y si hay tope por jugador.
3. Bonus exacto por publicar en la wiki (oro, título, ¿% de ventas?) y si caduca.
4. ¿El «Mapa del hallazgo» se agota al usarse o es permanente?
5. ¿Los secretos pueden compartirse solo con el gremio o los amigos?
6. Límite de obreros y salas del refugio por nivel, y qué se puede acelerar con Prismas.
7. Nombre definitivo del Refugio («El Nido» es provisional) y si la app móvil sale junto al juego o después.
8. ¿Cuánto dura un personaje prestado y qué gana quien lo presta?
9. ¿Se puede caminar en El Nido mientras el personaje está en el mundo?
10. Reglas de PK: ¿en qué zonas se permite y cuánto dura la marca de «PK activo» y la de «Matahumanos»?
11. Tamaño de la bolsa segura y duración del fardo al morir.
