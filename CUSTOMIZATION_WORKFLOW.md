# Flujo de Trabajo para Personalización de Ricelin

Guía de referencia para cualquier agente o desarrollador que trabaje sobre
este rice. Explica dónde editar, cómo desplegar y cómo mantener las
personalizaciones a salvo de actualizaciones upstream.

---

## Regla fundamental

> **Nunca editar archivos directamente en `~/.config/`.**
> El instalador sobreescribe esos directorios en cada deploy.
> Todo cambio va primero al repositorio Git y luego se despliega.

---

## Estructura del entorno

| Propósito | Ruta |
|-----------|------|
| Código fuente (editar aquí) | `/home/diego/Documents/GitHub/Ricelin/` |
| Config activa (solo lectura para el agente) | `/home/diego/.config/hypr/` y `/home/diego/.config/quickshell/` |
| Instalador | `/home/diego/Documents/GitHub/Ricelin/installer/deploy.py` |

### Archivos de configuración por componente

- **Hyprland:** `configs/hypr/`
- **Quickshell (barra/widgets):** `configs/quickshell/`
- **Scripts de sistema:** `configs/hypr/scripts/`

### Archivos gestionados por la UI (no tocar desde el repo)

Estos dos archivos los escribe la propia UI de Settings en tiempo de ejecución.
El deploy los preserva automáticamente — no hace falta incluirlos en commits:

- `configs/hypr/modules/monitors.lua` — configuración de monitor (resolución, Hz, posición)
- `configs/hypr/modules/decoration.lua` — bordes, blur, opacidad

---

## Rama Git activa

Las personalizaciones viven en la rama `personal-custom`, separada de `main` (upstream).

```bash
# Verificar rama activa antes de editar
git -C /home/diego/Documents/GitHub/Ricelin branch
# Debe mostrar * personal-custom
```

---

## Flujo de trabajo diario

### 1. Editar en el repositorio

```bash
# Ejemplo: editar un script de Hyprland
nano /home/diego/Documents/GitHub/Ricelin/configs/hypr/scripts/wallpaper.sh

# Ejemplo: editar un widget de Quickshell
nano /home/diego/Documents/GitHub/Ricelin/configs/quickshell/pill/Wallpaper.qml
```

### 2. Verificar antes de desplegar

```bash
# Self-test del instalador (detecta errores en la lógica de deploy)
python /home/diego/Documents/GitHub/Ricelin/installer/deploy.py

# Verificar sintaxis de Hyprland (no lanza el compositor, solo valida)
hyprland --verify-config

# Verificar QML estáticamente
find /home/diego/Documents/GitHub/Ricelin/configs/quickshell/pill/ \
  -name "*.qml" -exec /usr/lib/qt6/bin/qmllint {} +
```

### 3. Desplegar al entorno activo

```bash
# Solo deploy — para uso diario y redespliegues personales
python -c "
import sys
sys.path.append('/home/diego/Documents/GitHub/Ricelin/installer')
import deploy
deploy.deploy(apply=True)
"
```

> ⚠️ No llamar `deploy.neutralize(apply=True)` en redespliegues personales.
> `neutralize` es para preparar el rice para distribución pública (resetea rutas,
> monitors, etc.) y solo debe usarse en primera instalación o al publicar upstream.

### 4. Recargar el entorno

Después de desplegar, aplicar los cambios en vivo:

```bash
# Solo cambios de Quickshell (barra, widgets, UI)
/home/diego/.config/hypr/scripts/ricelin restart pill

# Cambios de Hyprland (keybinds, reglas de ventana, decoración)
hyprctl reload

# Ambos a la vez (cuando hay cambios en los dos)
/home/diego/.config/hypr/scripts/ricelin restart all
```

> `ricelin` no está en `$PATH` — usar siempre la ruta absoluta:
> `/home/diego/.config/hypr/scripts/ricelin`

### 5. Hacer commit

```bash
cd /home/diego/Documents/GitHub/Ricelin
git add <archivos-modificados>
git commit -m "tipo(scope): descripción breve"
```

---

## Actualizar desde upstream (Gakuseei/Ricelin)

```bash
cd /home/diego/Documents/GitHub/Ricelin

# 1. Ir a main y bajar cambios
git checkout main
git pull origin main

# 2. Volver a la rama personal y aplicar encima del upstream nuevo
git checkout personal-custom
git rebase main
```

Si hay conflictos durante el rebase, resolverlos manualmente y continuar:

```bash
git add <archivo-resuelto>
git rebase --continue
```

---

## Diagnóstico rápido

| Síntoma | Comando |
|---------|---------|
| La barra no se ve o crashea | `journalctl --user -u quickshell -n 50` |
| Hyprland ignora un keybind | `hyprland --verify-config` |
| Un script no encuentra su binario | Verificar que use ruta absoluta (no `$PATH`) |
| Cambios desplegados pero no visibles | Recargar con `ricelin restart pill` o `hyprctl reload` |
| Wallpapers no aparecen en el picker | Directorio correcto: `~/Pictures/Wallpapers/` |

---

## Notas importantes para agentes

- **`$PATH` en Hyprland** es restringido — binarios en `~/.local/bin/` no son
  accesibles desde scripts lanzados por Hyprland. Usar siempre rutas absolutas
  (ej. `/home/diego/.local/bin/rishot`, no `rishot`).
- **Quickshell tiene dos instancias:** `pill` (barra/UI) y `lock` (pantalla de bloqueo).
  Reiniciar solo la instancia afectada para evitar parpadeos innecesarios.
- **`flags.json`** en `~/.local/state/ricelin/flags.json` persiste el estado de la UI
  entre reinicios y está fuera del deploy — no se sobreescribe nunca.
- **Crash de Quickshell al reiniciar** con `Signal: Aborted (6)` en `QWindow::unsetCursor()`
  es inofensivo — bug de Qt6/Wayland en el ciclo de salida, no indica un problema real.
