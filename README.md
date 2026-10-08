# Frantz TopUp — Panel

Aplicación de gestión de un solo archivo (`index.html`, sin build ni dependencias de compilación).

## Autenticación

Login real contra **Supabase Auth** (`signInWithPassword`). La contraseña se valida en el servidor de Supabase sobre TLS y nunca se compara en el navegador. La pantalla de acceso tiene dos pestañas: **Iniciar Sesión** y **Registrarse** (`sb.auth.signUp`); el login acepta "Usuario o Correo" (si escribes el nombre de usuario, se resuelve su correo vía la función `email_por_usuario`). El registro pide Nombre Completo, Nombre de Usuario (min. 3), Correo, Contraseña (min. 6) y Confirmación, guardando nombre/usuario en los metadatos del perfil. Al pie del formulario se muestra el aviso **Modo Red** (los datos del panel se almacenan en `localStorage` del equipo); si Supabase no responde, aparece un acceso simplificado en modo local.

| Rol | Acceso |
|---|---|
| `admin` | Secciones completas: Inicio, Notificaciones, Envío, Facturación, Operaciones, **Movimientos, Red, Deuda, Panel Agencia**, Perfil, Soporte, Seguridad |
| `master` | Inicio, Envío, Operaciones, **Movimientos, Red**, Perfil, Soporte, Seguridad |

Solo existen los roles `admin` y `master` (el rol `trabajador` fue eliminado del panel). Las secciones `deu` y `ag` son de solo-admin y `mov`/`net` requieren rol `master`; si un usuario sin permiso navega a una de esas rutas, se lo devuelve a Inicio con un aviso.

### Base de datos

El esquema está en [`supabase-schema.sql`](./supabase-schema.sql). Pegar completo en **Supabase → SQL Editor → Run**. Crea:

- tabla `profiles` (`id`, `email`, `rol`, `creado_en`)
- trigger `handle_new_user` que crea el perfil al nacer el usuario
- función `es_admin()` con `security definer` — evita la recursión infinita de RLS
- políticas RLS: cada quien ve su perfil; el admin ve todos; **solo el admin puede actualizar roles**, así un usuario no se puede autopromover

### Cambio de contraseña

*Seguridad* → el usuario cambia su propia contraseña con `sb.auth.updateUser({password})`, validado por Supabase con la sesión activa.

Para crear cuentas y resetear contraseñas de otros usuarios se usa el panel de **Supabase → Authentication → Users**. Pasarlo a la web requiere una Edge Function con la `service_role` key, que no puede ir al navegador.

## Correr

Abrir `index.html` en un navegador, o servirlo estáticamente (Vercel, Netlify, Cloudflare Pages, GitHub Pages).

## Limitación conocida

Los datos de negocio (saldos, operaciones, agentes) siguen en `localStorage` bajo la clave `fpanel_v1`, **compartidos por navegador y sin sincronizar entre dispositivos** (aviso "Modo Red" visible en la pantalla de acceso). La autenticación controla *quién ve la interfaz*, pero no aísla los datos por usuario: si admin y master usan el mismo computador, comparten almacenamiento. Separarlos exige migrar esos datos a Supabase con RLS.

Mientras eso no pase, esta app no debe usarse con datos reales de clientes.

## Pendiente

- [ ] Desactivar registros públicos: *Authentication → Providers → Email → Allow new users to sign up*
- [ ] Migrar saldos y operaciones a Supabase con RLS
- [ ] Edge Function para que el admin cree usuarios y resetee contraseñas desde la web
- [ ] CSP y cabeceras de seguridad en el hosting
- [ ] Compartir `www.frantztopup.cl`

Dominio previsto: www.frantztopup.cl
Empresa: Frantz TopUp SPA
