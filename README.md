# Frantz TopUp — Panel

Aplicación de gestión de un solo archivo (`index.html`, sin build ni dependencias de compilación).

## Autenticación

Login real contra **Supabase Auth** (`signInWithPassword`). La contraseña se valida en el servidor de Supabase sobre TLS y nunca se compara en el navegador. La pantalla de acceso tiene dos pestañas: **Iniciar Sesión** y **Registrarse** (`sb.auth.signUp`); el login acepta "Usuario o Correo" (si escribes el nombre de usuario, se resuelve su correo vía la función `email_por_usuario`). El registro pide Nombre Completo, Nombre de Usuario (min. 3), Correo, Contraseña (min. 6) y Confirmación, guardando nombre/usuario en los metadatos del perfil.

| Rol | Acceso |
|---|---|
| `admin` | Secciones completas: Inicio, Notificaciones, Envío, Facturación, Operaciones, **Movimientos, Red, Deuda, Panel Agencia**, Perfil, Soporte, Seguridad |
| `master` | Inicio, Envío, Operaciones, **Movimientos, Red**, Perfil, Soporte, Seguridad |

Solo existen los roles `admin` y `master` (el rol `trabajador` fue eliminado del panel). Las secciones `deu` y `ag` son de solo-admin y `mov`/`net` requieren rol `master`; si un usuario sin permiso navega a una de esas rutas, se lo devuelve a Inicio con un aviso.

### Base de datos

El esquema está en [`supabase-schema.sql`](./supabase-schema.sql). Pegar completo en **Supabase → SQL Editor → Run**. Crea:

- tabla `panel_state`: una fila `panel` con el estado operativo del panel (saldos, operaciones, inventario, configuración) en la nube, sincronizada entre dispositivos vía Realtime
- tabla `profiles` (`id`, `email`, `rol`, `full_name`, `username`, `creado_en`)
- trigger `handle_new_user` que crea el perfil al nacer el usuario
- trigger `panel_state_touch` que registra `updated_at`/`updated_by` en la nube
- funciones `es_admin()` y `es_master()` con `security definer` — evitan la recursión infinita de RLS
- función `email_por_usuario(text)` para login "usuario o correo"
- políticas RLS: cada quien ve su perfil; el admin ve todos; **solo el admin puede actualizar roles**; `panel_state` lo leen los usuarios autenticados y lo escriben solo `admin`/`master`, así un usuario no se puede autopromover

### Cambio de contraseña

*Seguridad* → el usuario cambia su propia contraseña con `sb.auth.updateUser({password})`, validado por Supabase con la sesión activa.

Para crear cuentas y resetear contraseñas de otros usuarios se usa el panel de **Supabase → Authentication → Users**. Pasarlo a la web requiere una Edge Function con la `service_role` key, que no puede ir al navegador.

## Correr

Abrir `index.html` en un navegador, o servirlo estáticamente (Vercel, Netlify, Cloudflare Pages, GitHub Pages).

## Datos en la nube

Toda la operación del panel (saldos, operaciones, movimientos, notificaciones, inventario, perfil y configuración) vive en la tabla `panel_state` de Supabase y se sincroniza **en tiempo real** entre dispositivos (Realtime). Se abandona `localStorage` para los datos de negocio: al iniciar sesión el panel carga el estado desde la nube y cada cambio se guarda con un `upsert` diferido de ~500 ms. Si la fila de la nube aún está vacía, se importa una única vez el `localStorage` heredado (`fpanel_v1`) para no perder los datos actuales y nunca se vuelve a escribir en local.

## Pendiente

- [ ] Desactivar registros públicos: *Authentication → Providers → Email → Allow new users to sign up*
- [ ] Edge Function para que el admin cree usuarios y resetee contraseñas desde la web
- [ ] CSP y cabeceras de seguridad en el hosting
- [ ] Compartir `www.frantztopup.cl`

Dominio previsto: www.frantztopup.cl
Empresa: Frantz TopUp SPA
