-- don't forget to call create_machine() afterwards or you'll have no CPU or RAM

drop database if exists my6502;
create database my6502 character set ascii;

use my6502;

create table ram (
    address smallint unsigned not null primary key,
    value tinyint unsigned not null default 0xFF
) engine = innodb;

create table cpu (
    a tinyint unsigned not null default 0xFF,
    x tinyint unsigned not null default 0xFF,
    y tinyint unsigned not null default 0xFF,
    s tinyint unsigned not null default 0xFF,
    p tinyint unsigned not null default 0x20,
    pc smallint unsigned not null default 0
) engine = innodb;

create table screen (
    screen text character set ascii not null
) engine = innodb;

delimiter $$

create trigger ram_after_update after update on ram
for each row begin
    declare ix integer;
    if NEW.address >= 0x400 and NEW.address < 0x800 then  -- text screen
        set ix = NEW.address - 0x400;
        set ix = ix + 1;  -- DEBUG skip over newline
        update screen set screen = concat(left(screen, ix), char(NEW.value), substring(screen, ix+2));
    end if;
end;

drop procedure if exists create_machine;
create procedure create_machine ()
begin
    declare a int;

    delete from ram;
    set a = 0;
    while a <= 0xFFFF do
        insert into ram (address) values
            (a+0x00),(a+0x01),(a+0x02),(a+0x03),(a+0x04),(a+0x05),(a+0x06),(a+0x07),(a+0x08),(a+0x09),(a+0x0A),(a+0x0B),(a+0x0C),(a+0x0D),(a+0x0E),(a+0x0F),
            (a+0x10),(a+0x11),(a+0x12),(a+0x13),(a+0x14),(a+0x15),(a+0x16),(a+0x17),(a+0x18),(a+0x19),(a+0x1A),(a+0x1B),(a+0x1C),(a+0x1D),(a+0x1E),(a+0x1F),
            (a+0x20),(a+0x21),(a+0x22),(a+0x23),(a+0x24),(a+0x25),(a+0x26),(a+0x27),(a+0x28),(a+0x29),(a+0x2A),(a+0x2B),(a+0x2C),(a+0x2D),(a+0x2E),(a+0x2F),
            (a+0x30),(a+0x31),(a+0x32),(a+0x33),(a+0x34),(a+0x35),(a+0x36),(a+0x37),(a+0x38),(a+0x39),(a+0x3A),(a+0x3B),(a+0x3C),(a+0x3D),(a+0x3E),(a+0x3F);
        set a = a + 0x40;
    end while;

    delete from cpu;
    insert into cpu set pc = 0x300;

    delete from screen;
    insert into screen (screen) values (repeat(concat("\n", repeat(" ", 40)), 24));

    call hard_reset();
end;

drop procedure if exists hard_reset;
create procedure hard_reset ()
begin
    update ram set value = 0xFF;
    update cpu set a = 0xFF, x = 0xFF, y = 0xFF, s = 0xFF, p = 0x20, pc = 0x0300;
end;

$$
delimiter ;
