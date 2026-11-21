# HUËLLIK — resolución pública de perfiles v1

Estado: función desplegada en Supabase y conectada a la rama de desarrollo. La migración de mascotas no se ha ejecutado.

## Comportamiento

La función RPC public.resolve_public_pet_profile(p_code text) acepta un código en texto y resuelve:

1. Etiquetas físicas futuras: busca petlink.identifiers.public_code; solo resuelve identificadores en estado active y mascotas con perfil público activo.
2. Enlaces antiguos: cuando se migren las mascotas, podrá resolver petlink.pets.legacy_public_id.
3. Compatibilidad temporal: si la mascota todavía no está migrada, delega el UUID antiguo en public.get_public_pet_profile(uuid).

La ruta de las etiquetas nuevas será https://huellik-web.vercel.app/?tag=<public_code>. Los enlaces actuales ?pet=<public_id> siguen admitidos. El frontend de desarrollo también admite ambos parámetros y prefiere tag si aparecen los dos.

## Datos expuestos

- Nombre, especie, raza, color y descripción pública.
- Estado de mascota perdida.
- Contactos solo desde petlink.pet_contacts cuando is_public = true.
- Alertas médicas solo cuando show_medical_alerts = true.
- No consulta ni devuelve petlink.pet_private_contacts.
- No devuelve UUID interno, propietario, dirección, geolocalización ni eventos de auditoría.

Los identificadores pending, disabled, lost y replaced no resuelven perfiles. La pérdida de la mascota se comunica mediante petlink.pets.lost_mode; el estado lost de un identificador significa que esa etiqueta física no debe seguir sirviendo la ficha.

## Seguridad

La función es SECURITY DEFINER porque necesita leer tablas del esquema privado petlink. Tiene search_path vacío, referencias cualificadas y devuelve únicamente un JSON público construido campo a campo. Se revocó EXECUTE a PUBLIC y se concedió explícitamente a anon y authenticated para que funcione tanto desde un QR sin sesión como desde una sesión iniciada.

El asesor de Supabase marca esta función como SECURITY DEFINER ejecutable por anon/authenticated. Es intencional para un endpoint de perfil público. También aparecen funciones previas con avisos similares; no se modificaron como parte de este trabajo. Los avisos de RLS sin políticas en el esquema privado corresponden a tablas que deliberadamente no permiten acceso directo y usan RPC/backend controlados.

## Pruebas realizadas

Con registros sintéticos dentro de una transacción revertida:

- código de etiqueta activa resuelve la ficha;
- contactos siempre se devuelven como array;
- alerta médica oculta por defecto;
- etiqueta desactivada devuelve not_found;
- mascota privada devuelve not_found.

También se comparó el resultado del enlace antiguo con la RPC anterior: el JSON resultó idéntico para la mascota pública actual. Código desconocido devuelve not_found. Todos los registros sintéticos se revirtieron.

## Estado del despliegue

- Función SQL desplegada en el proyecto Supabase.
- Frontend actualizado únicamente en develop/huellik-v2.
- Preview Vercel desplegada correctamente: https://huellik-web-git-develop-huellik-v2-huellik-web.vercel.app
- main y la web publicada no se han modificado.
- No hay mascotas migradas ni etiquetas físicas registradas todavía.
- No se han creado servicios ni costes nuevos.

## Próximas pruebas

1. Abrir la rama de preview desde un navegador y probar el enlace antiguo con sesión cerrada.
2. Cuando exista inventario real, probar un código QR activo y un identificador desactivado.
3. Tras migrar, comprobar contactos públicos/privados y alertas médicas con ambos valores del interruptor.
4. Probar una mascota privada y una cuenta distinta a su propietario.
