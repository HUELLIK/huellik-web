# Dependencia SQL de promociones

El módulo de administración usa dos tablas privadas:
- `petlink.promo_codes`
- `petlink.promo_redemptions`

El archivo `docs/sql/promo-tables-v1-draft.sql` crea únicamente estas tablas e índices y activa RLS. No concede permisos de lectura o escritura a roles de navegador. El RPC `huellik_admin_promotions_v1` es una función SECURITY DEFINER con `search_path = ''`, comprobación de `auth.uid()` y referencias cualificadas; debe ser propiedad de un rol que pueda operar sobre `petlink`.

No aplicar el borrador comercial completo para habilitar solo promociones. Revisar primero la existencia de tablas y columnas en el proyecto actual. Las tablas de pedidos y suscripciones referenciadas ya forman parte del esquema histórico.
