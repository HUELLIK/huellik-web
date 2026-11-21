# admin-overview — primera Edge Function HUËLLIK

Estado: código preparado en GitHub; NO desplegado y NO aplicado a Supabase.
Rama: `develop/huellik-v2`.

## Archivos

- `supabase/functions/admin-overview/index.ts`: endpoint POST de solo lectura.
- `docs/sql/admin-overview-rpc-draft.sql`: RPC privada de agregados, aún no aplicada.

## Diseño de seguridad

1. La puerta de enlace de Supabase debe exigir JWT válido (`verify_jwt = true`).
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
    "users": 0,
    "pets": 0,
    "identifiers": 0,
    "orders": 0,
    "subscriptions": 0
  }
}
```

Los valores reales se consultan en el momento de la petición; el ejemplo anterior solo muestra la forma.

## Antes de desplegar

- Revisar la configuración real de dominios/orígenes.
- Aplicar la RPC como migración revisada en Supabase; no conceder acceso directo a tablas `petlink`.
- Desplegar la Edge Function con `verify_jwt = true`.
- Confirmar que el runtime dispone de `SUPABASE_PUBLISHABLE_KEYS` o de la clave anon compatible.
- Probar con la cuenta propietaria: respuesta 200.
- Probar sin JWT: respuesta 401.
- Probar con un usuario autenticado no propietario: respuesta 403.
- Probar con un JWT expirado: respuesta 401.
- Comprobar que no hay datos personales en respuestas ni logs.

No se ha creado ninguna rama Supabase, no se ha desplegado código, no se han modificado ajustes de Data API y no se ha ejecutado el SQL.
