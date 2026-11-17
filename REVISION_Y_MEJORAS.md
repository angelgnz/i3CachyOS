# Revisión de Funcionalidades, Problemas y Mejoras — `i3CachyOS`

> Fecha de revisión: 2026-11-16
> Alcance: `README`, `scripts/i3_config.sh`, `scripts/modules/*.sh`, `scripts/apps/*`

---

## 1. Mapa de Funcionalidades Actuales

El proyecto está organizado en un **dispatcher CLI** (`scripts/i3_config.sh`), **8 módulos de dominio** (`scripts/modules/*.sh`) y **7 scripts auxiliares** (`scripts/apps/*`):

| Dominio | Archivos | Qué hace actualmente |
| :--- | :--- | :--- |
| **CLI y Backups** | `scripts/i3_config.sh` (L33-309) | 16 subcomandos (`setup`, `deps-check`, `deps-install`, `display-manager`, `wal`, `alacritty`, `colorscheme`, `helpers-install`, `screenlayout`, `picom-config`, `touchpad-config`, `polybar-update`, `i3-patch`, `backup-list`, `backup-restore`, `revert`), opciones globales (`--skip-install`, `--yes`, `--dry-run`, `--revert`, `--only-polybar-color`) y manifiestos de backup en `~/.config/i3/.cachyos-i3-backups/<timestamp>/`. |
| **Dependencias** | `scripts/modules/dependencies.sh` (L3-220) | Detecta paquetes/binarios faltantes, ofrece menú interactivo (`1) Instalar`, `2) Continuar`, `3) Detener`) e instala separando repos oficiales y AUR (`yay` -> `paru` -> `sudo pacman`). |
| **Display Manager** | `scripts/i3_config.sh` (L335-607) | Instala `sddm` y `pixie-sddm-git`, desactiva DMs en conflicto (`ly`, `lightdm`, `gdm`, `lxdm`, `xdm`), habilita `sddm.service` y reemplaza fondo (`wallpapers/city.jpg`) y avatar (`avatar/*`) del tema Pixie. |
| **Esquema de color** | `scripts/modules/colorscheme.sh` (L8-493) | Copia fondos de `wallpapers/`, instala template de `pywal` para Alacritty, regenera caché con `wal -i`, traduce el color semilla de `pywal` a un tono Material para Polybar (`colors-dark.sh`) y migra `[colors.*]` de `alacritty.toml` a `colors-base.toml` con `import`. |
| **Parcheo de i3** | `scripts/modules/i3_patch.sh` | Configura atajos (`$mod+a`, `$mod+Shift+e`, `$mod+x`, `$mod+Shift+t`), `border pixel 0`, reglas `floating enable` para Steam Settings (ES/EN), limpia líneas legacy y añade el bloque gestionado (`kwalletd6`, `gsettings` dark, `pantallas.sh`, `i3_polybar_set_theme --current`, `gaps`, `xborders`, `i3-layouts` e `i3_wallpaper`). |
| **Compositor (Picom)** | `scripts/modules/picom.sh` (L3-269) | Ajusta `corner-radius = 12;`, inyecta `opacity-rule` (`Thunar` 75%, `Org.xfce.mousepad` 75%, `code` 90%), añade `xborder` a `blur-background-exclude` y comenta `refresh-rate = 0`. |
| **Pantalla / Multimonitor** | `scripts/modules/screenlayout.sh` | Detecta 1 o más monitores conectados en `xrandr`, elige como primario el de mayor área, detecta resolución y mayor `--rate`, apaga salidas desconectadas aún activas (`--off`), genera `~/.screenlayout/pantallas.sh` y reajusta el wallpaper con `i3_wallpaper`. |
| **Touchpad** | `scripts/modules/touchpad.sh` (L3-57) | Escribe `/etc/X11/xorg.conf.d/30-touchpad.conf` con `NaturalScrolling "True"`. |
| **Polybar & Apps** | `scripts/modules/polybar.sh`, `scripts/modules/helpers.sh`, `scripts/apps/*` | Añade `[module/tray]` y reemplaza `color-switch` en Polybar `shapes`, instala 7 helpers en `~/.config/i3/scripts/` (incluyendo `i3_wallpaper` por aspect ratio/resolución), parchea `i3_autostart` y crea `~/.config/xfce4/helpers.rc` (`TerminalEmulator=alacritty`). |

---

## 2. Problemas y Bugs Detectados

### Críticos (Rompen funcionalidad o corrompen configuración)

1. **Corrupción de sintaxis (`,,`) en `picom.conf`**
   - **Ubicación**: `scripts/modules/picom.sh:73-112`
   - **Causa raíz**: En `update_picom_opacity_rule`, las dos primeras entradas de `desired_entries` (`L74-75`) ya terminan en `,`, pero el bucle de inserción (`L108-111`) vuelve a concatenar `body += ','`. Además, la expresión regular `opacity-rule\s*=\s*\[` (`L82`) también puede coincidir con bloques comentados (`#opacity-rule = [...]`) si aparecen antes del bloque activo.
   - **Impacto**: Genera dobles comas `,,` inválidas en `picom.conf`.

2. **Contaminación de `stdout` en `copy_wallpapers()` impide ejecutar `wal -i` en la primera corrida**
   - **Ubicación**: `scripts/modules/colorscheme.sh:59-65`, `scripts/i3_config.sh:104,855,874`
   - **Causa raíz**: `log()` escribe en `stdout` (`echo "[INFO] $*"`). Cuando `copy_wallpapers()` copia un wallpaper nuevo (`L59`), escribe `[INFO] Wallpaper copiado: ...` en `stdout` antes de emitir `echo "$dst_dir"` (`L65`). Al capturarse con `wallpaper_dir="$(copy_wallpapers)"` (`i3_config.sh:855,874`), la variable queda con líneas `[INFO]` mezcladas con la ruta.
   - **Impacto**: `regenerate_wal_cache "$wallpaper_dir"` evalúa `[[ ! -d "$wallpaper_dir" ]]`, falla y omite `wal -i` justo la primera vez que se copian los wallpapers. De forma similar, `create_multimonitor_layout_if_needed >/dev/null` (`i3_config.sh:890`) silencia los mensajes `log()` de `screenlayout.sh`.

3. **Detección e instalación fallida de dependencias por confusión entre nombre de paquete y comando**
   - **Ubicación**: `scripts/modules/dependencies.sh:3-22,124-162`, `scripts/i3_config.sh:585,752`
   - **Causa raíz**:
     - `optional_cmds` (`i3_config.sh:752`) incluye nombres de paquetes (`xborder-git`, `wallutils`, `kwallet-pam`) y `command_display_manager` (`i3_config.sh:585`) pasa `pixie-sddm-git`.
     - `dependency_available()` (`dependencies.sh:6-21`) solo consulta con `yay/paru/pacman -Qq` a `polybar-themes-git|themix-full-git|thunar-archive-plugin`; para el resto usa `command_exists` (`command -v`). Como no existen binarios llamados `xborder-git` (`xborders`), `wallutils` (`setwallpaper`), `kwallet-pam` ni `pixie-sddm-git`, siempre se reportan como faltantes.
     - `install_missing_dependencies()` mapea `wal` -> `pywal` (`dependencies.sh:135`), pero en Arch/CachyOS el paquete se llama `python-pywal`.
     - `xborder-git` e `i3-layouts` son paquetes AUR, pero no están listados en el `case` de `aur_packages` (`dependencies.sh:155`), por lo que en entornos sin `yay`/`paru` se intentan instalar como paquetes oficiales.

4. **`--revert` y `backup-restore` fallan con `Permission denied` en archivos `root`**
   - **Ubicación**: `scripts/i3_config.sh:199-242` vs `scripts/i3_config.sh:375-401`
   - **Causa raíz**: `backup_root_file_once` respalda archivos como `/etc/X11/xorg.conf.d/30-touchpad.conf` y `/usr/share/sddm/themes/pixie/assets/*` con `sudo cp -a`, pero `restore_from_manifest` ejecuta `mkdir -p`, `rm -rf "$p1"` y `cp -a "$p2" "$p1"` sin `sudo`.
   - **Impacto**: Con `set -euo pipefail`, revertir cualquier ejecución de `setup`, `display-manager` o `touchpad-config` que haya tocado archivos de sistema aborta por falta de permisos.

5. **`ensure_sddm_theme_config()` nunca se invoca**
   - **Ubicación**: `scripts/i3_config.sh:403-476` vs `scripts/i3_config.sh:569-607`
   - **Causa raíz**: La función `ensure_sddm_theme_config()` configura `[Theme] Current=pixie` en `/etc/sddm.conf`, pero `command_display_manager()` nunca la llama. Además, en `replace_pixie_background()` (`i3_config.sh:525`), si el fondo `background.jpg` ya coincide (`cmp -s`), la función hace `return 0` antes de comprobar y copiar `avatar.jpg` (`L537-566`).
   - **Impacto**: El tema `pixie` no queda activado en `/etc/sddm.conf`, y si `background.jpg` ya está actualizado, nunca se actualiza `avatar.jpg`.

---

### Moderados (Lógica, Idempotencia, Portabilidad y CLI)

6. **Ruta `/home/angel/...` hardcodeada en `i3/config`**
   - **Ubicación**: `scripts/modules/i3_patch.sh:191`
   - **Detalle**: Inyecta `exec --no-startup-id setwallpaper "/home/angel/Images/wallpapers/edger_lucy_neon-16-9.jpg" --mode span`. Falla con cualquier otro usuario o si los fondos están en `~/Imágenes/wallpapers`.

7. **Doble ejecución en arranque de `i3_nzxt` e `i3_cloud_storage`**
   - **Ubicación**: `scripts/modules/helpers.sh:48-94`, `scripts/modules/i3_patch.sh:162-163`, `scripts/apps/i3_cloud_storage:4-6`
   - **Detalle**: Se insertan tanto en `~/.config/i3/scripts/i3_autostart` como en el bloque gestionado de `~/.config/i3/config`. Además, `i3_cloud_storage` lanza `python /opt/thefanclub/overgrive/overgrive` en primer plano sin `&` ni chequeo `pgrep`.

8. **Conflicto entre selector de temas Polybar e `i3/config`**
   - **Ubicación**: `scripts/modules/i3_patch.sh:170`, `scripts/apps/i3_polybar_set_theme:89-126`
   - **Detalle**: `i3_patch.sh` fija `exec_always --no-startup-id ~/.config/polybar/launch.sh --shapes` en `i3/config`. Al cambiar de tema con `$mod+Shift+t` (`i3_rofi_polybar_theme`), cualquier recarga de i3 vuelve a forzar `--shapes`, desincronizándose de `~/.config/polybar/.current_theme` que leen `i3_rofi_apps` e `i3_rofi_powermenu`. Asimismo, el `launch.sh` de `polybar-themes` no soporta `--panels` ni `--pwidgets`, por lo que `i3_polybar_set_theme` falla al lanzarlos aunque los liste como válidos.

9. **Acumulación de líneas en blanco y backups redundantes en ejecuciones repetidas**
   - **Ubicación**: `scripts/i3_config.sh:667-706`, `scripts/modules/i3_patch.sh:71,149`, `scripts/modules/screenlayout.sh:40`
   - **Detalle**: `append_managed_block` agrega una línea en blanco antes de `$MANAGED_BEGIN` y otra después de `$MANAGED_END`, pero `remove_managed_block` solo elimina entre los marcadores. Cada ejecución añade líneas vacías y crea backups nuevos de `i3/config` y `pantallas.sh` sin verificar antes si hubo cambios con `cmp -s`.

10. **Parser de argumentos CLI dependiente del orden y sin validación de flags**
    - **Ubicación**: `scripts/i3_config.sh:66-102`
    - **Detalle**: Si se pasa un flag antes del subcomando (ej. `./scripts/i3_config.sh --dry-run i3-patch`), `COMMAND` queda en `setup` y `"i3-patch"` entra a `SUBCOMMAND_ARGS`, ejecutando `setup` completo. Los flags desconocidos (ej. `--dryrun`) tampoco generan error y pasan a `SUBCOMMAND_ARGS`.

11. **Problemas en modo `--dry-run` y dependencias implícitas**
    - **Ubicación**: `scripts/i3_config.sh:109,745`, `scripts/modules/i3_patch.sh:65`, `scripts/modules/picom.sh:66`
    - **Detalle**:
      - `mkdir -p "$BACKUP_ROOT"` (`i3_config.sh:109`) se ejecuta siempre antes de revisar `DRY_RUN` o subcomandos de solo lectura (`deps-check`, `backup-list`).
      - Si `~/.config/i3/config` no existe, `setup --dry-run` e `i3-patch --dry-run` fallan porque `ensure_i3_config_exists` no crea el archivo en `DRY_RUN=1` y la línea siguiente aborta si `! -f "$I3_CONFIG"`.
      - `ask_missing_dependency_action` se ejecuta incluso con `--dry-run` si falta `--yes` o `--skip-install`.
      - `update_picom_opacity_rule` (`picom.sh:66`) invoca `python3` incluso en `--dry-run` y sin verificar `command_exists python3`.

12. **Código muerto, permisos y archivos huérfanos**
    - `scripts/apps/i3_screenlayout`: archivo vacío (0 bytes), sin uso.
    - `replace_or_append_line()` (`scripts/i3_config.sh:648-665`): definida pero nunca llamada (y sin soporte `DRY_RUN`).
    - `I3_GAP_SIZE` (`scripts/i3_config.sh:18`): declarada pero no interpolada (`i3_patch.sh:173` usa `gaps inner 12` fijo).
    - `scripts/apps/i3_polybar_set_theme`, `scripts/apps/i3_rofi_polybar_theme` y `scripts/apps/i3_rofi_powermenu` están en el repo con permisos `0644` (sin `+x`).
    - `scripts/apps/i3_nzxt:13-17` mezcla configuración `xinput` de un touchpad específico (`MSFT0001:00 06CB:CE44 Touchpad`) duplicando el alcance de `scripts/modules/touchpad.sh`.

13. **Desincronización entre `README` y código**
    - **Ubicación**: `README:1-127`
    - **Detalle**: Omite `scripts/modules/touchpad.sh`, el subcomando `touchpad-config`, la opción `--only-polybar-color`, y 3 helpers de `scripts/apps/` (`i3_polybar_set_theme`, `i3_rofi_polybar_theme`, `i3_rofi_powermenu`). Además, lista solo 6 de las 17 dependencias opcionales y describe únicamente `corner-radius = 12` en Picom (omitiendo `opacity-rule`, `blur-background-exclude`, `refresh-rate` y los cambios de Polybar/XFCE/Steam).

---

## 3. Plan de Mejoras Priorizado

### Fase 1: Bugs Críticos y Reversibilidad
- [x] **Corregir `picom.sh`**: quitar las comas duplicadas en `desired_entries` dentro de `update_picom_opacity_rule`, ignorar bloques comentados al buscar `opacity-rule` / `blur-background-exclude`, y validar `command_exists python3` antes de ejecutar Python.
- [x] **Enviar `log()` a `stderr`**: cambiar `log() { echo "[INFO] $*" >&2; }` en `scripts/i3_config.sh:104` para no contaminar valores devueltos por `stdout` (`copy_wallpapers`, `detect_wallpaper_dir`, `collect_missing_dependencies`) y quitar el `>/dev/null` en `command_screenlayout`.
- [x] **Corregir detección e instalación en `dependencies.sh`**: consultar paquetes con `pacman -Qq` (incluyendo `xborder-git`, `wallutils`, `kwallet-pam`, `pixie-sddm-git`, `polybar-themes-git`, `themix-full-git`, `thunar-archive-plugin`) o mapear paquete -> binario real, corregir `wal` -> `python-pywal`, y agregar `xborder-git` e `i3-layouts` a `aur_packages`.
- [x] **Soportar archivos `root` en `restore_from_manifest`**: detectar rutas sin permiso de escritura de usuario (ej. `/etc/...`, `/usr/share/...`) para usar `sudo` al restaurar/eliminar durante `--revert` y `backup-restore`, y usar `grep -Fxq` en el manifiesto.
- [x] **Activar tema Pixie y corregir retorno temprano en `i3_config.sh`**: invocar `ensure_sddm_theme_config` dentro de `command_display_manager` y evitar que `replace_pixie_background` retorne antes de procesar `avatar/*` cuando `background.jpg` ya coincide.

### Fase 2: Idempotencia, Portabilidad y Experiencia CLI
- [x] **Eliminar valores hardcodeados en `i3_patch.sh`**: reemplazar `/home/angel/Images/wallpapers/...` por `"$(detect_wallpaper_dir)/edger_lucy_neon-16-9.jpg"`, interpolar `${I3_GAP_SIZE}` en `gaps inner`, y evitar lanzar `i3_nzxt`/`i3_cloud_storage` por duplicado si ya están en `i3_autostart`.
- [x] **Respetar tema activo de Polybar al iniciar/recargar i3**: usar un lanzador o wrapper en `i3/config` que lea `~/.config/polybar/.current_theme` (con fallback a `shapes`) y validar disponibilidad real en `i3_polybar_set_theme`.
- [x] **Idempotencia estricta sin backups innecesarios ni líneas vacías**: construir las ediciones de `i3/config` y `pantallas.sh` en temporales y comparar con `cmp -s` antes de respaldar/escribir; evitar que `append_managed_block` acumule saltos de línea extra.
- [x] **Mejorar parser CLI y `--dry-run` en `i3_config.sh`**: aceptar flags globales antes o después del subcomando, rechazar flags desconocidos (`--*`), posponer `mkdir -p "$BACKUP_ROOT"` hasta `ensure_backup_session`, no pedir interacción en `--dry-run`, y permitir simular `i3-patch`/`setup` cuando aún no existe `~/.config/i3/config`.

### Fase 3: Limpieza Arquitectónica y Documentación
- [x] **Modularizar Display Manager**: extraer la lógica de SDDM/Pixie de `scripts/i3_config.sh` hacia `scripts/modules/display_manager.sh`.
- [x] **Limpiar código muerto y permisos**: eliminar `scripts/apps/i3_screenlayout` (vacío) y `replace_or_append_line`, separar el ajuste de touchpad fuera de `scripts/apps/i3_nzxt`, y aplicar `chmod +x` a todos los scripts ejecutables de `scripts/apps/`.
- [x] **Sincronizar `README`**: documentar `touchpad.sh`, `touchpad-config`, `--only-polybar-color`, todos los helpers de `scripts/apps/`, las dependencias reales y todas las modificaciones que aplica `setup`.
