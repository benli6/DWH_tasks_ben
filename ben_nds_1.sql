set search_path to nds;


-- Названия не помещаются в колонки
alter table dim.product 
alter column artist
type varchar(200) 
using artist::varchar;

alter table dim.product 
alter column "name"
type varchar(400) 
using "name"::varchar;


-- Задание 1. измерение “Товар”
insert into dim.product (code, name, artist, product_type, product_category, unit_price, unit_cost, status, effective_ts, expire_ts, is_current)
with cte1 as (
   select distinct ftd.film_id, first_value(fd."name") over (partition by film_id order by director_id) as director
    from films_to_director ftd
    join films_director fd on ftd.director_id = fd.id
)
select
  f.id::varchar as code,
  f.title as name,
  coalesce (cte1.director, 'Неизвестно') as artist,
  'Фильм' as product_type,
  coalesce(fg."name", 'Неизвестно')  as product_category,
  f.price as unit_price,
  f.cost as unit_cost,
  case
      when f.status = 'p' THEN 'Ожидается'
      when f.status = 'o' THEN 'Доступен'
      when f.status = 'e' THEN 'Не продаётся'
  end as status,
  f.start_ts as effective_ts,
  f.end_ts as expire_ts,
  f.is_current
from films f
left join films_genre fg on f.genre_id = fg.id 
left join cte1 on cte1.film_id = f.id ;

-- Проверка
select count(*) from dim.product p ; 


-- Задание 2. обновить таблицу “Покупатель”
--добавлена колонка
alter table dim.customer
add column subscriber_class varchar(25);


-- не очень понятно про 365 дней, запрос только по 3 месяцам
update dim.customer as dc
set subscriber_class = subq.subscriber_class
from
(select t.id as id, 
	case 
		when t.perc < 25 then 'R1'
		when t.perc < 50 then 'R2'
		when t.perc < 75 then 'R3'
		when t.perc >= 75 then 'R4'
	end as subscriber_class
from (
	--сумма всех покупок отдельных единиц товаров за 3 месяца по каждому покупателю
	with cte1 as(
		select distinct(si.customer_id) as id, coalesce(
			coalesce(sum(f.price), 0) + coalesce(sum(m.price), 0) + coalesce(sum(b.price),0) , 0) as item_sum 
		from sale_item si 
		left join films f on si.film_id = f.id 
		left join music m on si.music_id = m.id 
		left join book b on si.book_id = b.id 
		where si.dt between	
			(select max(si.dt) - interval '3 months'from sale_item si) and
			(select max(si.dt) as date_end from sale_item si)
		group by si.customer_id
		order by si.customer_id),
	--сумма всех покупок подписок за 3 месяца по каждому покупателю
	cte2 as(
		select distinct(cs.customer_id) as id, coalesce(sum(s.price), 0) as sub_sum
		from customers_subscriptions cs 
		join subscriptions s on cs.subscription_id = s.id  
		where cs."date" between 
			(select max(cs."date") - interval '3 months' from customers_subscriptions cs)  and 
			(select max(cs."date") from customers_subscriptions cs)
		group by cs.customer_id 
		order by cs.customer_id)
	-- расчёт процента по каждому покупателю
	select c.id as id, ((coalesce(item_sum, 0) + coalesce(sub_sum, 0)) * 4) * 100. / 
			(max((coalesce(item_sum, 0) + coalesce(sub_sum, 0)) * 4) over ()) as perc
	from dim.customer c
	full outer join cte2 on c.id = cte2.id
	full outer join cte1 on c.id = cte1.id) as t) as subq
where dc.id = subq.id
