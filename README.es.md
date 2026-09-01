*[Read in English](README.md)*

# ♟ Ajedrez WoW — Addon para WotLK 3.3.5a

Juega ajedrez completo dentro de World of Warcraft, contra la IA o contra otro jugador real del mismo servidor.

---

## 📦 Instalación

1. Copia la carpeta `Chess` completa dentro de:
   ```
   World of Warcraft/Interface/AddOns/Chess/
   ```
2. La estructura debe quedar así:
   ```
   Chess/
   ├── Chess.toc
   └── Chess.lua
   ```
3. Entra al juego y activa el addon en el selector de addons de la pantalla de personajes.

---

## 🎮 Comandos

| Comando | Descripción |
|---|---|
| `/chess` o `/ajedrez` | Abrir/cerrar el tablero |
| `/chess accept` | Aceptar un reto recibido |
| `/chess decline` | Rechazar un reto |
| `/chess resign` | Rendirse en la partida actual |
| `/chess help` | Mostrar ayuda |

---

## 🕹 Cómo jugar

### Contra la IA
1. Abre el tablero con `/chess`
2. Pulsa **"Nueva (Blancas) vs IA"** o **"Nueva (Negras) vs IA"**
3. Haz clic en tu pieza para seleccionarla (se resalta en verde)
4. Los movimientos válidos se muestran en azul (libre) o rojo (captura)
5. Haz clic en el destino para mover

### Contra otro jugador
1. Selecciona a otro jugador como **objetivo** (`/target NombreJugador`)
2. Abre el tablero y pulsa **"Retar objetivo"**
3. El oponente recibirá una notificación en el chat
4. El oponente escribe `/chess accept` para aceptar
5. Quien retó juega con **Blancas**, quien acepta con **Negras**
6. Los movimientos se sincronizan automáticamente

---

## ♟ Piezas (abreviaciones en español)

| Símbolo | Pieza |
|---|---|
| R | Rey (King) |
| D | Dama / Reina (Queen) |
| T | Torre (Rook) |
| A | Alfil (Bishop) |
| C | Caballo (Knight) |
| P | Peón (Pawn) |

- **Dorado** = Piezas Blancas
- **Rojo** = Piezas Negras

---

## 🟩 Colores del tablero

| Color | Significado |
|---|---|
| 🟩 Verde | Pieza seleccionada |
| 🟦 Azul | Movimiento libre disponible |
| 🟥 Rojo | Captura disponible / Rey en jaque |
| 🟨 Amarillo | Último movimiento realizado |

---

## ⚙️ Características

- ✅ Todas las reglas del ajedrez implementadas
- ✅ Enroque corto y largo
- ✅ Captura al paso (en passant)
- ✅ Promoción automática a Reina
- ✅ Detección de Jaque y Jaque Mate
- ✅ Detección de Tablas (ahogado)
- ✅ IA con estrategia greedy + variedad aleatoria
- ✅ Multijugador via mensajes de addon (mismo servidor)
- ✅ Tablero movible arrastrando con clic izquierdo

---

## 🐛 Notas

- Ambos jugadores deben tener el addon instalado y activo para el modo multijugador.
- Los mensajes de addon usan el canal WHISPER — no spam al chat general.
- Compatible con servidores WotLK 3.3.5a (privados y oficial clásico equivalente).
