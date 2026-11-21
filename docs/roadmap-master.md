# HUËLLIK — hoja de ruta maestra

Estado actualizado: 21-11-2026. Rama de trabajo: `develop/huellik-v2`.

## Reglas que no cambian
- Mantener `main` y la web publicada intactas hasta revisión y aprobación explícita.
- No crear ramas/proyectos Supabase de pago ni contratar herramientas.
- No activar cobros reales ni Stripe hasta que el flujo esté completo y probado.
- No exponer `service_role`, datos privados ni permisos administrativos al navegador.
- No borrar ni renombrar tablas históricas; migración gradual y reversible.
- El usuario puede tener perfil digital sin comprar etiqueta física; Plus es opcional en ambos casos.
- Identificadores QR/NFC permanentes y únicos; una etiqueta se sustituye/reasigna mediante flujo autorizado y auditado, sin perder la ficha de la mascota.
- Códigos promocionales administrados por el propietario, descuento porcentual o fijo, con alcance, vigencia y límites; validación y reserva siempre en servidor.
- El mes gratis solo se aplica al plan mensual; no al anual.
- Si una compra incluye un periodo Plus, comunicarlo claramente y no renovar sin aceptación expresa.

## Estado por fases

### 0. Base y seguridad
- [x] Auditar proyecto Supabase y separar esquema público actual de estructura histórica `petlink`.
- [x] Crear rama GitHub `develop/huellik-v2`; preservar `main`.
- [x] Documentar arquitectura, contratos backend y mapa de migración.
- [x] Crear allowlist privada de propietario.
- [x] Desplegar Edge Function `admin-overview` con JWT obligatorio.
- [x] Aplicar RPC de resumen con comprobación de rol owner.
- [x] Probar autorización owner y rechazo de cuenta no propietaria.
- [ ] Probar el endpoint HTTP desde una sesión real del propietario y desde una cuenta normal.
- [ ] Revisar dominio definitivo permitido por CORS.

### 1. Panel de administración
- [x] Construir primera pantalla de resumen de solo lectura.
- [x] Mostrar cuentas, mascotas, identificadores, pedidos y suscripciones.
- [ ] Conectar y probar el acceso desde la cuenta propietaria en la web de preview.
- [x] Módulo promociones: interfaz de creación/edición/listado y desactivación.
  - [x] Definir contrato CRUD y validaciones de servidor.
  - [x] Aplicar tablas privadas y RPC de administración en Supabase.
  - [x] Desplegar Edge Function `admin-promotions` con JWT obligatorio.
  - [x] Probar CRUD de forma transaccional (la prueba se revirtió, no dejó códigos de prueba).
  - [x] Probar rechazo de usuario no propietario en la RPC.
  - [ ] Probar desde la sesión real del propietario en la preview de Vercel.
  - [x] Implementar endpoint autenticado de validación de elegibilidad en servidor.
  - [x] Comprobar vigencia, estado, alcance, primer cliente y límites actuales.
  - [x] Ignorar reservas antiguas (ventana de 30 minutos) en validación y métricas.
  - [ ] Implementar reserva atómica durante create-checkout con precio autoritativo.
- [x] Módulo usuarios: directorio de solo lectura, búsqueda por nombre/correo y paginación.
  - [x] Mostrar fecha de alta, verificación de correo, mascotas actuales, pedidos y último estado de suscripción.
  - [x] Limitar datos personales visibles; no mostrar teléfonos, direcciones ni datos de pago.
  - [x] Proteger con RPC owner-only y Edge Function con JWT.
  - [ ] Probar desde la sesión real del propietario en la preview.
- [ ] Módulo mascotas/QR/NFC: consulta y ciclo de vida auditado.
- [ ] Módulo Plus: derechos, origen, periodo, concesión/revocación con motivo.
- [ ] Módulo pedidos y envíos.
- [ ] Registro de actividad administrativa.

### 2. Zona del cliente y perfiles
- [ ] Revisar y completar “Mi cuenta / Gestionar” sin romper el flujo actual.
- [ ] Alta, edición y eliminación segura de mascotas.
- [ ] Campos de perfil: nombre, especie, raza, sexo, nacimiento, color, descripción y foto.
- [ ] Contactos múltiples y visibilidad individual.
- [ ] Privacidad de perfil y vista pública QR con campos expresamente compartidos.
- [ ] Mantener compatibilidad con enlaces existentes `?pet=<public_id>`.

### 3. Identificación y recuperación
- [ ] Añadir microchip de 15 dígitos.
- [ ] Pasaporte/documentación de mascota.
- [ ] Modo perdido y mensaje de recuperación.
- [ ] Alertas de escaneo al propietario con privacidad adecuada.
- [ ] QR/NFC permanentes, activación, sustitución, pérdida y reasignación auditada.
- [ ] Escaneo sin cuenta para quien encuentra la mascota, sin exponer datos privados.

### 4. HUËLLIK Plus
- [ ] Modelo de derechos (entitlements) para suscripción, compra incluida, regalo, promoción o concesión administrativa.
- [ ] Plan mensual y anual.
- [ ] Periodo de prueba gratuito solo en mensual.
- [ ] Historial de salud.
- [ ] Recordatorios y calendario.
- [ ] Exportación PDF.
- [ ] Compartir ficha con permisos.
- [ ] Chat/función de comunicación prevista, tras definir privacidad y alcance.
- [ ] Renovaciones solo con consentimiento y comunicación transparente.

### 5. Tienda, pedidos y proveedores
- [ ] Catálogo y variantes de etiquetas QR/NFC.
- [ ] Compra de etiqueta física y opción digital.
- [ ] Vincular una compra a un identificador sin perder el perfil de mascota.
- [ ] Gestión de pedidos, preparación, envío y seguimiento.
- [ ] Negociación y selección de proveedor de etiquetas.
- [ ] Etiquetas personalizadas: comparar costes de preparación/moldes, muestras, mínimos y envío.
- [ ] Políticas de devolución, garantía y soporte.

### 6. Promociones y pagos
- [ ] CRUD administrativo de códigos promocionales.
- [ ] Descuento fijo o porcentual configurable.
- [ ] Alcance Plus mensual/anual y productos elegibles.
- [ ] Inicio/caducidad, límite global y por usuario, primer cliente opcional.
- [ ] Reserva transaccional y protección contra usos concurrentes (pendiente de catálogo/precios definitivos y checkout).
- [ ] Integrar Stripe solo cuando el propietario decida configurar cuenta y secretos.
- [ ] Checkout, webhooks firmados e idempotentes, reembolsos y cancelaciones.
- [ ] Activar Plus solo tras pago confirmado o concesión autorizada.
- [ ] No acumular descuentos salvo decisión futura explícita.

### 7. Pruebas, privacidad y lanzamiento
- [ ] Pruebas RLS con propietario, usuario normal y visitante anónimo.
- [ ] Pruebas móviles (iPhone/Android), QR, NFC, formularios y accesibilidad.
- [ ] Revisar Auth, protección de contraseñas filtradas y funciones SECURITY DEFINER.
- [ ] Revisar RGPD, privacidad, cookies, condiciones de compra, desistimiento y garantías.
- [ ] Verificar recuperación de cuenta, errores, correos y soporte.
- [ ] Preview completa y checklist de regresión.
- [ ] Revisión del propietario y aprobación explícita antes de publicar/merge a `main`.

## Implementación actual
- `admin.html`: resumen de solo lectura y módulo de promociones conectado a `admin-promotions`.
- `index.html`: muestra el acceso a Administración solo cuando la función de servidor autoriza la cuenta.
- `supabase/functions/admin-overview`: endpoint activo, JWT obligatorio.
- `supabase/functions/admin-promotions`: endpoint activo, JWT obligatorio; tablas privadas y RPC aplicadas.
- `supabase/functions/admin-users`: endpoint activo, JWT obligatorio; directorio owner-only de solo lectura.
- `public.pets` sigue siendo la fuente actual del recuento de mascotas; no se ha migrado información a `petlink.pets`.
