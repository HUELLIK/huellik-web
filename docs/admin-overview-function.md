# admin-overview — primera Edge Function HUËLLIK

Estado: **desplegada y activa** en el proyecto Supabase actual.
Rama de código: `develop/huellik-v2`.
Fecha de activación: 21-11-2026.

## Archivos

- `supabase/functions/admin-overview/index.ts`: endpoint POST de solo lectura, desplegado como versión 1.
- `docs/sql/admin-overview-rpc-applied.sql`: SQL aplicado en Supabase mediante ejecución directa.
- `docs/sql/admin-overview-rpc-draft.sql`: borrador inicial conservado como referencia.

## Verificaciones realizadas

- Supabase devuelve la función `admin-overview` con estado `ACTIVE`, versión 1 y `verify_jwt = true`.
- La RPC `public.huellik_admin_overview_v1()` existe.
- `anon` no tiene permiso EXECUTE; `authenticated` sí, pero la función verifica el rol de propietario internamente.
- La cuenta de propietario confirmada es la única fila con rol `owner`.
- Prueba SQL simulando la identidad de propietario: **correcta**, devuelve exclusivamente recuentos agregados.
- Prueba SQL simulando una cuenta no propietaria: **rechazada** con SQLSTATE `42501` y mensaje `Administrator access required`.
- No se ha utilizado `service_role` dentro del código de la función.
- No se ha abierto el esquema privado `petlink` a `anon` ni a `authenticated`.

## Diseño de seguridad

1. La puerta de enlace de Supabase exige JWT válido (`verify_jwt = true`).
2. La función valida el token con `auth.getUser(token)`.
3. La llamada a Postgres conserva el JWT del usuario; no usa `service_role`.
4. La RPC vuelve a comprobar `auth.uid()` contra `petlink.admin_users` y exige `role = 'owner'`.
5. La RPC tiene `search_path = ''`, referencias cualificadas y devuelve solo recuentos agregados.
6. No se confía en correo, `user_metadata`, parámetros enviados por el navegador ni estado local.
7. Respuestas con `Cache-Control: no-store`; CORS admite el dominio de HUËLLIK y localhost, configurable con `HUELLIK_ALLOWED_ORIGINS`.

## Respuesta prevista

```json
{
  "data": {
    "users": 2,
    "pets": 0,
    "identifiers": 0,
    "orders": 0,
    "subscriptions": 0
  }
}
```

Los recuentos reflejan el estado en el momento de la prueba, no valores fijos.

## Pendiente

- Probar el endpoint HTTP completo desde una sesión real del propietario y desde una cuenta normal. Las pruebas actuales validan la RPC y la barrera JWT configurada, pero no sustituyen una prueba extremo a extremo con sesiones reales.
- Revisar si el dominio de producción definitivo necesita añadirse a `HUELLIK_ALLOWED_ORIGINS`.
- Integrar la llamada en la interfaz privada `/admin` de la rama de desarrollo.

## Límites

- No se ha desplegado la web ni modificado `main`.
- No se ha creado ninguna rama Supabase.
- No se ha contratado ningún servicio.
- No se han añadido pagos ni webhooks.
- La SQL se aplicó directamente con `execute_sql`; no se generó una entrada en el historial de migraciones de Supabase. Se conserva el SQL exacto en el repositorio para trazabilidad.
