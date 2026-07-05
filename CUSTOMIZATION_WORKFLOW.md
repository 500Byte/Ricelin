# Flujo de Trabajo para Personalización y Desarrollo en Ricelin

Este documento describe la metodología correcta para personalizar, optimizar y mantener tus modificaciones sobre el rice **Ricelin** de forma segura y sin riesgo de perder cambios al actualizar desde upstream.

---

## 🛠 Estructura del Entorno

1. **Directorio del Repositorio Git** (Donde se edita el código):
   `/home/diego/Documents/GitHub/Ricelin`
   
2. **Directorio de Configuración Activa** (Donde el sistema lee los archivos):
   `/home/diego/.config` (gestionado por la propiedad `.ricelin-managed` en cada subcarpeta)

> ⚠️ **IMPORTANTE:** Nunca edites directamente los archivos en `~/.config/quickshell` o `~/.config/hypr`. El instalador de Ricelin sobreescribe estos directorios limpiamente. Modifica siempre los archivos dentro de la carpeta del repositorio Git y luego despliégalos.

---

## 🔄 Flujo de Trabajo Diario

### 1. Realizar Modificaciones en el Repositorio
Todos los cambios de ricing, configuración de teclado, y optimización de rendimiento deben realizarse bajo:
* **Hyprland:** `/home/diego/Documents/GitHub/Ricelin/configs/hypr/`
* **Quickshell (Barra/Widgets):** `/home/diego/Documents/GitHub/Ricelin/configs/quickshell/`

### 2. Desplegar los Cambios a `~/.config`
Para aplicar las modificaciones locales en tu entorno activo de forma segura, ejecuta la capa de despliegue y neutralización de Ricelin:

```bash
python -c "import sys; sys.path.append('/home/diego/Documents/GitHub/Ricelin/installer'); import deploy; deploy.deploy(apply=True); deploy.neutralize(apply=True)"
```

### 3. Recargar el Entorno
Una vez desplegado, recarga los compositores/servicios para ver los cambios aplicados en pantalla:

* **Recargar Hyprland:**
  ```bash
  hyprctl reload
  ```
* **Recargar Quickshell (Pill & Lock):**
  ```bash
  ricelin restart all
  ```

---

## 🌿 Gestión de Ramas en Git y Upstream

Para mantener tus personalizaciones a salvo de actualizaciones del autor original (`Gakuseei`):

1. **Mantén tus cambios en una rama dedicada:**
   Actualmente, tus cambios están guardados en la rama local `personal-custom`.

2. **Para actualizar desde upstream (Gakuseei/Ricelin):**
   ```bash
   # 1. Ve a la rama main limpia
   git checkout main
   
   # 2. Descarga las últimas actualizaciones
   git pull origin main
   
   # 3. Regresa a tu rama personalizada
   git checkout personal-custom
   
   # 4. Aplica tus cambios encima de la nueva base de upstream
   git rebase main
   ```
   *Si ocurre algún conflicto menor durante el rebase (por ejemplo, si el autor cambia las mismas líneas que optimizaste), resuélvelos y ejecuta `git rebase --continue`.*

---

## 🔍 Comprobación de Errores y Diagnóstico

### QML (Quickshell)
Para comprobar errores estáticos en la interfaz sin tener que lanzarla, puedes usar `qmllint` localmente:
```bash
find /home/diego/.config/quickshell/pill/ -name "*.qml" -exec /usr/lib/qt6/bin/qmllint {} +
```

### Hyprland
Para verificar que la sintaxis de Lua y las configuraciones de Hyprland sean correctas:
```bash
hyprland --verify-config
```
