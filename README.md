# Batalla Real 3D

Juego battle royale 3D para moviles hecho con **Godot 4.x** (renderizador Mobile), estilo simplificado tipo Fortnite.

## Modos de juego

1. **Solo contra el CPU (offline)**: tu contra 3 bots. 4 niveles de dificultad:
   - Facil: bots lentos, poca vida (70), disparan con mucha dispersion.
   - Normal: bots equilibrados (100 vida).
   - Dificil: bots rapidos, 130 vida, buena punteria.
   - Extremo: bots muy rapidos, 160 vida, punteria casi perfecta.
2. **Multijugador por hotspot (hasta 4 moviles)**: no necesita internet.
   - Un movil pulsa **Crear partida (host)**.
   - Los demas moviles se conectan al **punto de acceso (hotspot)** del host y en el juego escriben la **IP del host** (ej. `192.168.43.1`) y pulsan **Unirse**.
   - Las plazas que falten se rellenan con bots.

## Como esta el juego

- Mapa de 190x190 m con edificios generados al azar.
- Zona de tormenta (circulo morado) que se cierra por ciclos y hace dano fuera.
- Combate con disparos, salto, vida, tercer persona.
- Controles tactiles: joystick virtual a la izquierda para moverse, arrastrar en la derecha para mirar, botones DISPARAR y SALTAR.
- Gana el ultimo luchador en pie.

## Como abrirlo

1. Instala **Godot 4.2 o superior** (la version estandar, sin .NET).
2. Abre Godot, pulsa **Importar** y selecciona la carpeta de este proyecto (el archivo `project.godot`).
3. Para probar en tu movil Android:
   - En Godot: Editor > Editor Settings > Export/Android y configura el SDK (o usa "One-click deploy").
   - O exporta el APK: Proyecto > Exportar > Android > Exportar proyecto.
4. Para jugar por hotspot, instala el APK en los moviles, crea el hotspot en un movil (o usa el mismo WiFi) y sigue los pasos del modo multijugador.

## Estructura

- `scenes/Main.tscn` - escena principal (menu + partida).
- `scripts/main.gd` - menu principal (modo y dificultad).
- `scripts/game.gd` - mapa, tormenta, HUD, controles tactiles, red.
- `scripts/fighter.gd` - jugador/bot: movimiento, disparo, IA por dificultad.
- `scripts/bullet.gd` - balas.
- `scripts/net.gd` - conexion LAN (ENet, puerto 7777).
