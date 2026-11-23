alter table petlink.orders add column if not exists buyer_email text;
alter table petlink.orders add column if not exists buyer_phone text;
alter table petlink.orders add column if not exists shipping_method text;
alter table petlink.orders add column if not exists tracking_url text;
alter table petlink.orders add column if not exists admin_notes text;
create or replace function public.huellik_create_order_v1(p_product_code text,p_product_description text,p_quantity integer,p_unit_price numeric,p_shipping_eur numeric,p_name text,p_email text,p_phone text,p_address text,p_postal_code text,p_city text,p_province text,p_country text default 'España') returns jsonb language plpgsql security definer set search_path='' as $$
declare v_id uuid;v_number text;v_total numeric;
begin
 if p_product_code not in ('metal','flex') or p_quantity not between 1 and 10 then raise exception 'Producto o cantidad no válida';end if;
 if p_unit_price not in (19.90,20.00,21.90,22.00) or p_shipping_eur<0 or p_shipping_eur>20 then raise exception 'Precio no válido';end if;
 if length(trim(coalesce(p_name,'')))<2 or p_email !~* '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}$' or length(trim(coalesce(p_address,'')))<5 or length(trim(coalesce(p_postal_code,'')))<4 or length(trim(coalesce(p_city,'')))<2 then raise exception 'Completa los datos de envío';end if;
 v_total:=round((p_unit_price*p_quantity)+p_shipping_eur,2);v_number:='H-'||to_char(now(),'YYMMDD')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
 insert into petlink.orders(order_number,status,currency,subtotal_eur,shipping_eur,tax_eur,total_eur,shipping_name,shipping_address,buyer_email,buyer_phone,shipping_method) values(v_number,'pending_payment','EUR',p_unit_price*p_quantity,p_shipping_eur,0,v_total,trim(p_name),jsonb_build_object('address',trim(p_address),'postal_code',trim(p_postal_code),'city',trim(p_city),'province',trim(coalesce(p_province,'')),'country',trim(coalesce(p_country,'España'))),lower(trim(p_email)),nullif(trim(p_phone),''),'Pendiente de confirmar') returning id into v_id;
 insert into petlink.order_items(order_id,product_code,description,quantity,unit_price_eur) values(v_id,p_product_code,p_product_description,p_quantity,p_unit_price);
 insert into petlink.notifications(user_id,notification_kind,title,body,delivery_channel) select user_id,'order_update','Nuevo pedido HUËLLIK','Pedido '||v_number||' recibido: '||p_product_description||' x'||p_quantity||'. Total '||v_total||' EUR. Revisar panel admin.','admin' from petlink.admin_users where role='owner';
 return jsonb_build_object('success',true,'order_number',v_number,'total_eur',v_total,'status','pending_payment');
end $$;
create or replace function public.huellik_admin_orders_v1(p_action text,p_order_id uuid default null,p_status text default null,p_tracking_number text default null,p_tracking_url text default null,p_shipping_method text default null,p_admin_notes text default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_user uuid:=auth.uid();v_result jsonb;
begin
 if v_user is null or not exists(select 1 from petlink.admin_users a where a.user_id=v_user and a.role='owner') then raise insufficient_privilege using message='Administrator access required';end if;
 if p_action='list' then
 select coalesce(jsonb_agg(x order by x.created_at desc),'[]'::jsonb) into v_result from (select o.id,o.order_number,o.status,o.currency,o.subtotal_eur,o.shipping_eur,o.total_eur,o.shipping_name,o.shipping_address,o.buyer_email,o.buyer_phone,o.shipping_method,o.tracking_number,o.tracking_url,o.admin_notes,o.created_at,coalesce((select jsonb_agg(jsonb_build_object('product_code',i.product_code,'description',i.description,'quantity',i.quantity,'unit_price_eur',i.unit_price_eur)) from petlink.order_items i where i.order_id=o.id),'[]'::jsonb) items from petlink.orders o order by o.created_at desc limit 100)x;
 return jsonb_build_object('orders',v_result);
 elsif p_action='update' then
 if p_order_id is null or p_status not in ('pending_payment','paid','processing','sent_to_supplier','shipped','delivered','cancelled','refunded') then raise exception 'Estado o pedido no válido';end if;
 update petlink.orders set status=p_status,tracking_number=nullif(trim(p_tracking_number),''),tracking_url=nullif(trim(p_tracking_url),''),shipping_method=nullif(trim(p_shipping_method),''),admin_notes=nullif(trim(p_admin_notes),''),updated_at=now() where id=p_order_id;
 if not found then raise exception 'Pedido no encontrado';end if;return jsonb_build_object('success',true);
 else raise exception 'Acción no válida';end if;
end $$;
revoke all on function public.huellik_create_order_v1(text,text,integer,numeric,numeric,text,text,text,text,text,text,text,text) from public;
grant execute on function public.huellik_create_order_v1(text,text,integer,numeric,numeric,text,text,text,text,text,text,text,text) to anon,authenticated;
revoke all on function public.huellik_admin_orders_v1(text,uuid,text,text,text,text,text) from public,anon;
grant execute on function public.huellik_admin_orders_v1(text,uuid,text,text,text,text,text) to authenticated;
