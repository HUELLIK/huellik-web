# HUËLLIK v2 — plan de desarrollo sin costes adicionales

## Regla de coste
No crear ramas/proyectos de Supabase, no activar servicios de pago, no comprar dominios ni contratar herramientas. Trabajar en la rama GitHub gratuita `develop/huellik-v2`. Las consultas de auditoría a producción serán de solo lectura. Las migraciones y Edge Functions se desarrollan primero en `develop/huellik-v2`; los cambios de backend autorizados se aplican al proyecto Supabase actual. `main` y la web publicada permanecen intactas.

## Decisiones confirmadas
- `petlink` es el nombre histórico de HUËLLIK.
- Mantener QR/NFC digitales y etiquetas físicas.
- Plus opcional para ambas modalidades.
- Periodo Plus incluido en compras solo si se comunica claramente y la renovación posterior requiere aceptación expresa.
- Identificadores permanentes, únicos y reasignables mediante proceso autorizado; cambiar etiqueta no cambia la ficha.
- Administración exclusiva del propietario, sin registro público de administradores.
- Códigos promocionales creados por el propietario con descuento porcentual o fijo, fechas, límites y alcance mensual/anual.
- Mantener `main` y producción intactas hasta pruebas y aprobación final.

## Inventario auditado
Supabase proyecto Huëllik Project, región eu-west-1, PostgreSQL 17.
- `public`: perfiles, mascotas, contactos, historiales, recordatorios y solicitudes Plus; es lo que usa la web actual.
- `petlink`: estructura histórica de usuarios, mascotas, contactos privados, miembros, identificadores, escaneos, pedidos, artículos, suscripciones, notificaciones y auditoría.
- Dos usuarios coinciden entre auth.users, public.profiles y petlink.app_users.
- Hay una mascota y un contacto en public; las tablas de negocio petlink están vacías.
- RLS está habilitado en ambas estructuras. petlink carece de políticas y de privilegio USAGE para anon/authenticated; no abrirlo directamente.
- Funciones Edge desplegadas: `admin-overview`, `admin-promotions`, `validate-promo` y `admin-users`, todas con JWT obligatorio (excepto futuros webhooks firmados).
- No hay buckets de Storage.
- La vista pública de petlink no tiene permisos de lectura para anon/authenticated.
- La RPC pública de perfil es SECURITY DEFINER y actualmente ejecutable por anon/authenticated. Debe limitarse y probarse.
- Los triggers actuales crean perfiles en public y petlink al registrar una cuenta.

## Plan técnico
1. Mapear campos y restricciones de public y petlink; preservar UUID y datos existentes.
2. Definir petlink como futuro esquema de producto solo después de validar migración; conservar compatibilidad de public hasta cambiar frontend.
3. Crear políticas RLS según propiedad y roles familiares; datos privados no accesibles públicamente.
4. Añadir modelo de derechos Plus (entitlements) para suscripción, regalo, promoción o periodo incluido.
5. Añadir promociones con redenciones transaccionales y límites concurrentes.
6. Añadir checkout y webhooks Stripe solo cuando el propietario tenga una cuenta y configure secretos seguros.
7. Implementar panel privado; validar al propietario en backend con allowlist secreta, nunca con user_metadata editable.
8. Implementar ciclo de vida QR/NFC, escaneos, pedidos y notificaciones.
9. Probar y revisar antes de merge o despliegue.

## Reglas
- Nunca guardar service_role ni claves Stripe secret en frontend o Git.
- No usar user_metadata para autorización.
- No aplicar DDL adicional ni desplegar nuevas funciones sin revisar el alcance y contar con autorización.
- No cambiar ajustes de Auth sin revisión.
- No eliminar/renombrar tablas ni copiar datos sin backup y prueba de reversión.
- Ningún pago se activa sin configurar Stripe y probar webhooks firmados e idempotentes.
- La promoción se valida en backend, no en JavaScript del navegador.

## Bloqueos que no requieren gasto ahora
- El identificador de la cuenta del propietario debe fijarse desde un entorno seguro antes de habilitar administración.
- Stripe queda desactivado hasta que el propietario decida abrir/configurar una cuenta.
- Las etiquetas físicas y el proveedor se pueden integrar después; el perfil digital funciona sin ellas.
