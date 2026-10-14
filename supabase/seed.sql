-- Seed Adriano Lanches (gerado de data/produtos.json)
insert into public.lojas (slug, nome, modo, config) values ('adriano-lanches','Adriano Lanches','aberta','{"taxa_entrega":10,"frete_gratis_acima":null,"pedido_minimo":0,"horario":{"abre":"19:00","fecha":"01:00"},"tempo_entrega":"40-60 min","tempo_retirada":"20-30 min","whatsapp":null,"chave_pix":null,"endereco":"Praça Miguel Rossafa, 5566 — Zona III, Umuarama/PR","formas_pagamento":["pix","dinheiro","cartao"]}'::jsonb) on conflict (slug) do update set nome=excluded.nome, config=excluded.config;
with l as (select id from public.lojas where slug='adriano-lanches')
insert into public.categorias (loja_id, slug, nome, ordem) select l.id, v.slug, v.nome, v.ordem from l, (values ('prensados-salsicha','Lanches com Salsicha',1),('lanches-hamburguer','Lanches com Hambúrguer',2),('bebidas','Bebidas',3)) v(slug,nome,ordem) on conflict (loja_id, slug) do nothing;
create temp table seed_prod (ref int, cat text, nome text, descricao text, preco numeric, ordem int, destaque boolean, tags text[], upgrade_ref int);
insert into seed_prod values
(1,'prensados-salsicha','Simples','Pão, salsicha, milho e alface.',26,1,false,array[]::text[],2),
(2,'prensados-salsicha','Simples com Batata Palha','Pão, salsicha, milho, alface e batata palha.',28,2,false,array[]::text[],3),
(3,'prensados-salsicha','Especial com Bacon','Pão, salsicha, milho, alface, batata palha e bacon.',32,3,false,array[]::text[],4),
(4,'prensados-salsicha','Especial com Bacon e Catupiry','Pão, salsicha, milho, alface, batata palha, bacon e catupiry.',38,4,true,array[]::text[],10),
(5,'prensados-salsicha','Especial com Catupiry','Pão, salsicha, milho, alface, batata palha e catupiry.',32,5,false,array[]::text[],4),
(6,'prensados-salsicha','Especial com Calabresa','Pão, salsicha, milho, alface, batata palha e calabresa.',32,6,false,array[]::text[],7),
(7,'prensados-salsicha','Especial com Bacon e Calabresa','Pão, salsicha, milho, alface, batata palha, bacon e calabresa',38,7,false,array[]::text[],13),
(8,'prensados-salsicha','Especial com Frango','Pão, salsicha, milho, alface, batata palha e frango.',32,8,false,array[]::text[],9),
(9,'prensados-salsicha','Especial com Frango e Bacon','Pão, salsicha, milho, alface, batata palha e frango e bacon.',38,9,false,array[]::text[],10),
(10,'prensados-salsicha','Especial com Frango, Bacon e Catupiry','Pão, salsicha, milho, alface, batata palha, frango, bacon e catupiry.',43,10,true,array['favorito']::text[],13),
(11,'prensados-salsicha','Especial com Frango e Calabresa','Pão, salsicha, milho, alface, batata palha, frango e calabresa.',38,11,false,array[]::text[],13),
(12,'prensados-salsicha','Especial com Frango ao Catupiry','Pão, salsicha, milho, alface, batata palha, frango e catupiry.',38,12,false,array[]::text[],10),
(13,'prensados-salsicha','Especial Big','Pão, salsicha, milho, alface, batata palha, frango, catupiry, bacon e calabresa.',47,13,true,array['mais-pedido']::text[],null),
(14,'lanches-hamburguer','X-Salada','Pão, hambúrguer, alface, milho, tomate, presunto e mussarela.',33,14,true,array[]::text[],15),
(15,'lanches-hamburguer','X-Bacon','Pão, hambúrguer, alface, milho, tomate, presunto, mussarela e bacon.',40,15,false,array[]::text[],24),
(16,'lanches-hamburguer','X-Egg','Pão, hambúrguer, alface, milho, tomate, presunto, mussarela e ovo.',40,16,false,array[]::text[],24),
(17,'lanches-hamburguer','X-Catupiry','Pão, hambúrguer, alface, milho, tomate, presunto, mussarela e catupiry.',40,17,false,array[]::text[],24),
(18,'lanches-hamburguer','X-Calabresa','Pão, hambúrguer, alface, milho, tomate, presunto, mussarela e calabresa.',40,18,false,array[]::text[],24),
(19,'lanches-hamburguer','X-Frango','Pão, alface, milho, tomate, 2 mussarela e filé de frango.',41,19,false,array[]::text[],null),
(20,'lanches-hamburguer','Misto Quente','Pão, 2 presunto e 2 mussarela',24,20,false,array[]::text[],21),
(21,'lanches-hamburguer','Bauru','Pão, tomate, milho, 2 presunto e 2 mussarela.',25,21,false,array[]::text[],14),
(22,'lanches-hamburguer','X-Picanha','Pão, milho, tomate, 2 mussarela e picanha.',46,22,false,array[]::text[],23),
(23,'lanches-hamburguer','X-Picanha c/ Cheddar','Pão, milho, tomate, 2 mussarela, picanha e cheddar.',50,23,false,array['premium']::text[],null),
(24,'lanches-hamburguer','X-Tudo','Pão, hambúrguer, alface, milho, tomate, presunto, mussarela, frango, bacon, calabresa, catupiry e ovo.',49,24,true,array['monstro']::text[],null),
(25,'lanches-hamburguer','X-Galinha','Pão, alface, milho, tomate, presunto, mussarela e frango desfiado.',37,25,false,array[]::text[],null),
(26,'lanches-hamburguer','X-Burg','Pão, hambúrguer, presunto e mussarela.',30,26,false,array[]::text[],14),
(27,'lanches-hamburguer','X-Cheddar','Pão, hambúrguer, alface, milho, tomate, presunto, mussarela e cheddar.',40,27,false,array[]::text[],24),
(28,'lanches-hamburguer','X-Vegetariano','Pão, alface, milho, tomate, hambúrguer de grão-de-bico e 2 fatias de mussarela.',32,28,false,array['veggie']::text[],29),
(29,'lanches-hamburguer','X-Vegetariano Catupiry','Pão, hambúrguer de grão-de-bico, alface, milho, tomate e 2 fatias de mussarela e catupiry',38,29,false,array['veggie']::text[],null),
(30,'lanches-hamburguer','X-Vegetariano Cheddar','Pão, hambúrguer de grão-de-bico, alface, milho, tomate e 2 fatias de mussarela e cheddar.',38,30,false,array['veggie']::text[],null),
(31,'bebidas','Suco Prats 900ml',null,20,31,false,array[]::text[],null),
(32,'bebidas','Festysuco Laranja 900ml',null,20,32,false,array[]::text[],null),
(33,'bebidas','Energético Monster',null,14,33,false,array[]::text[],null),
(34,'bebidas','Água Mineral','Com ou sem gás',5,34,false,array[]::text[],null),
(35,'bebidas','H2O',null,8,35,false,array[]::text[],null),
(36,'bebidas','Coca-Cola KS 290ml',null,6,36,false,array[]::text[],null),
(37,'bebidas','Fanta KS 290ml',null,6,37,false,array[]::text[],null),
(38,'bebidas','Sprite KS 290ml',null,6,38,false,array[]::text[],null),
(39,'bebidas','Coca-Cola Lata 350ml',null,8,39,false,array[]::text[],null),
(40,'bebidas','Fanta Lata 350ml',null,8,40,false,array[]::text[],null),
(41,'bebidas','Guaraná Antarctica Lata 350ml',null,8,41,false,array[]::text[],null),
(42,'bebidas','Sprite Lata 350ml',null,8,42,false,array[]::text[],null),
(43,'bebidas','Guaraná Antarctica Zero Lata 350ml',null,8,43,false,array[]::text[],null),
(44,'bebidas','Coca-Cola Zero Lata 350ml',null,8,44,false,array[]::text[],null),
(45,'bebidas','Coca-Cola 600ml',null,13,45,false,array[]::text[],null),
(46,'bebidas','Guaraná Antarctica 600ml',null,13,46,false,array[]::text[],null),
(47,'bebidas','Guaraná Antarctica 2L',null,18,47,false,array[]::text[],null),
(48,'bebidas','Coca-Cola 2L',null,18,48,false,array[]::text[],null),
(49,'bebidas','Energético Monster Zero',null,14,49,false,array[]::text[],null),
(50,'bebidas','Coca-Cola Zero 2L',null,18,50,false,array[]::text[],null),
(51,'bebidas','Itubaína Long Neck 355ml',null,8,51,false,array[]::text[],null);
alter table public.produtos add column if not exists seed_ref int;
insert into public.produtos (loja_id, categoria_id, nome, descricao, preco, ordem, destaque, tags, seed_ref)
select l.id, c.id, s.nome, s.descricao, s.preco, s.ordem, s.destaque, s.tags, s.ref
from seed_prod s join public.lojas l on l.slug='adriano-lanches' join public.categorias c on c.loja_id=l.id and c.slug=s.cat;
update public.produtos p set upgrade_para = u.id from seed_prod s join public.produtos u on u.seed_ref = s.upgrade_ref where p.seed_ref = s.ref and s.upgrade_ref is not null and u.loja_id = p.loja_id;
alter table public.produtos drop column seed_ref;
drop table seed_prod;
