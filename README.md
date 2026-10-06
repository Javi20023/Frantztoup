# Frantz TopUp — Panel

Aplicación de gestión de un solo archivo (`index.html`, sin build ni dependencias de compilación).

## Autenticación

Login real contra **Supabase Auth** (`signInWithPassword`). La contraseña se valida en el servidor de Supabase sobre TLS y nunca se compara en el navegador.

| Rol | Acceso |
|---|---|
| `admin` | Secciones completas: Inicio, Notificaciones, Envío, Facturación, Operaciones, **Movimientos, Red, Deuda, Panel Agencia**, Perfil, Soporte, Seguridad |
| `trabajador` | Inicio, Notificaciones, Envío, Facturación, Operaciones, Perfil, Soporte, Seguridad |

Las secciones `mov`, `net`, `deu` y `ag` están en `SOLO_ADMIN` (`index.html`) y se ocultan del menú para trabajadores. Si un trabajador navega a una de esas rutas, se lo devuelve a Inicio con un aviso.

### Base de datos

El esquema está en [`supabase-schema.sql`](./supabase-schema.sql). Pegar completo en **Supabase → SQL Editor → Run**. Crea:

- tabla `profiles` (`id`, `email`, `rol`, `creado_en`)
- trigger `handle_new_user` que crea el perfil al nacer el usuario
- función `es_admin()` con `security definer` — evita la recursión infinita de RLS
- políticas RLS: cada quien ve su perfil; el admin ve todos; **solo el admin puede actualizar roles**, así un trabajador no se puede autopromover

### Cambio de contraseña

*Seguridad* → el usuario cambia su propia contraseña con `sb.auth.updateUser({password})`, validado por Supabase con la sesión activa.

Para crear cuentas y resetear contraseñas de otros usuarios se usa el panel de **Supabase → Authentication → Users**. Pasarlo a la web requiere una Edge Function con la `service_role` key, que no puede ir al navegador.

## Correr

Abrir `index.html` en un navegador, o servirlo estáticamente (Vercel, Netlify, Cloudflare Pages, GitHub Pages).

## Limitación conocida

Los datos de negocio (saldos, operaciones, agentes) siguen en `localStorage` bajo la clave `fpanel_v1`, **compartidos por navegador y sin sincronizar entre dispositivos**. La autenticación controla *quién ve la interfaz*, pero no aísla los datos por usuario: si admin y trabajador usan el mismo computador, comparten almacenamiento. Separarlos exige migrar esos datos a Supabase con RLS.

Mientras eso no pase, esta app no debe usarse con datos reales de clientes.

## Pendiente

- [ ] Desactivar registros públicos: *Authentication → Providers → Email → Allow new users to sign up*
- [ ] Migrar saldos y operaciones a Supabase con RLS
- [ ] Edge Function para que el admin cree usuarios y resetee contraseñas desde la web
- [ ] CSP y cabeceras de seguridad en el hosting
- [ ] Compartir `www.frantztopup.cl`

Dominio previsto: www.frantztopup.cl
Empresa: Frantz TopUp SPA
