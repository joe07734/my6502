-- cat test.sql|mysql -u root

use my6502;
delimiter $$


-- -- -- -- -- -- -- -- -- -- -- -- --
--
--    testing
--
-- -- -- -- -- -- -- -- -- -- -- -- --

# call load_ram(0x300, "A9 C1 A2 00 9D 00 04 69 01 E8 E0 0A D0 F6 FF");  -- spaces are required
drop procedure if exists load_ram;
create procedure load_ram (loc smallint unsigned, bytes text)
begin
    declare b tinyint unsigned;
    while length(bytes) > 0 do
        set b = conv(left(bytes, 2), 16, 10);
        set bytes = substring(bytes, 4);
        update ram set ram.value = b where ram.address = loc;
        set loc = loc + 1;
    end while;
end;

drop procedure if exists test_run;
create procedure test_run (bytes text)
begin
    call soft_reset();
    call load_ram(0x300, bytes);
    call run(0x300, 0);
end;

-- FC58G
drop procedure if exists test;
create procedure test ()
begin
-- 300:A9 C1     LDA #'A'
-- 302:A2 00     LDX #0
-- 304:9D 00 04  STA $400,X
-- 307:69 01     ADC #1
-- 309:E8        INX
-- 30A:E0 0A     CPX #10
-- 30C:D0 F6     BNE $304
-- 30F:FF        HALT
    call test_run("A9 C1 A2 00 9D 00 04 69 01 E8 E0 0A D0 F6 FF");
end;


$$
delimiter ;
