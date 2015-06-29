-- cat test.sql|mysql -u root

use my6502;
delimiter $$


-- -- -- -- -- -- -- -- -- -- -- -- --
--
--    tests
--
-- -- -- -- -- -- -- -- -- -- -- -- --

-- FC58G
drop procedure if exists test;
create procedure test ()
begin
    call test_addressing_modes();
    call test_instructions();
end;


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

# load and run program and 0x300
drop procedure if exists test_run;
create procedure test_run (program text)
begin
    call soft_reset();
    call load_ram(0x300, program);
    call run(0x300, 0);
end;

# run program, assert that acc is a given value
drop procedure if exists assert_a;
create procedure assert_a (program text, check_a tinyint unsigned)
begin
    declare a tinyint unsigned;
    call test_run(concat(program, " FF"));
    select cpu.a into a from cpu;
    if a != check_a then
        update stats set message = concat_ws(" ", "check_a fail:", hex(a), "!=", hex(check_a), "program:", program);
        update stats set halt = null;
    end if;
end;

# run program, assert that x is a given value
drop procedure if exists assert_x;
create procedure assert_x (program text, check_x tinyint unsigned)
begin
    declare x tinyint unsigned;
    call test_run(concat(program, " FF"));
    select cpu.x into x from cpu;
    if x != check_x then
        update stats set message = concat_ws(" ", "check_x fail:", hex(x), "!=", hex(check_x), "program:", program);
        update stats set halt = null;
    end if;
end;

# run program, assert that y is a given value
drop procedure if exists assert_y;
create procedure assert_y (program text, check_y tinyint unsigned)
begin
    declare y tinyint unsigned;
    call test_run(concat(program, " FF"));
    select cpu.y into y from cpu;
    if y != check_y then
        update stats set message = concat_ws(" ", "check_y fail:", hex(y), "!=", hex(check_y), "program:", program);
        update stats set halt = null;
    end if;
end;


-- -- -- -- -- -- -- -- -- -- -- -- --
--
--    test addressing modes
--
-- -- -- -- -- -- -- -- -- -- -- -- --

# test all addressing modes for all instruction encoding styles
drop procedure if exists test_addressing_modes;
create procedure test_addressing_modes ()
-- requires LDA, STA, LDX, LDY, INC
begin
    -- instruction style a

    -- immediate
    call assert_a("A9 00", 0x00);  -- LDA #0
    call assert_a("A9 80", 0x80);
    call assert_a("A9 FF", 0xFF);
    -- zero page
    call load_ram(0x00, "AA BB CC DD");
    call load_ram(0x80, "EE");
    call assert_a("A5 00", 0xAA);  -- LDA $00
    call assert_a("A5 01", 0xBB);
    call assert_a("A5 02", 0xCC);
    call assert_a("A5 03", 0xDD);
    call assert_a("A5 80", 0xEE);  -- LDA $80  - unsigned
    -- zero page,X
    call load_ram(0x00, "AA BB CC DD");
    call assert_a("A2 00 B5 00", 0xAA);  -- LDX #0; LDA $00,X
    call assert_a("A2 03 B5 00", 0xDD);  -- LDX #3; LDA $00,X
    call assert_a("A2 01 B5 02", 0xDD);  -- LDX #1; LDA $02,X
    call assert_a("A2 02 B5 FF", 0xBB);  -- LDX #2; LDA $FF,X  - wraparound
    -- absolute
    call load_ram(0x200, "11 22 33 44");
    call assert_a("AD 00 02", 0x11);  -- LDA $200
    call assert_a("AD 03 02", 0x44);  -- LDA $203
    -- absolute,X
    call load_ram(0x00, "AA BB CC DD");
    call load_ram(0x200, "11 22 33 44");
    call assert_a("A2 00 BD 00 02", 0x11);  -- LDX #0; LDA $200,X
    call assert_a("A2 01 BD 02 02", 0x44);  -- LDX #1; LDA $202,X
    call assert_a("A2 02 BD FF 01", 0x22);  -- LDX #2; LDA $1FF,X  - cross page
    call assert_a("A2 FE BD 02 01", 0x11);  -- LDX #$FE; LDA $102,X  - X is unsigned
    call assert_a("A2 02 BD FF FF", 0xBB);  -- LDX #2; LDA $FFFF,X   - wraparound
    -- absolute,Y
    call load_ram(0x00, "AA BB CC DD");
    call load_ram(0x200, "11 22 33 44");
    call assert_a("A0 00 B9 00 02", 0x11);  -- LDY #0; LDA $200,Y
    call assert_a("A0 01 B9 02 02", 0x44);  -- LDY #1; LDA $202,Y
    call assert_a("A0 02 B9 FF 01", 0x22);  -- LDY #2; LDA $1FF,Y  - cross page
    call assert_a("A0 FE B9 02 01", 0x11);  -- LDY #$FE; LDA $102,Y  - Y is unsigned
    call assert_a("A0 02 B9 FF FF", 0xBB);  -- LDY #2; LDA $FFFF,Y   - wraparound
    -- (indirect,X)
    call load_ram(0x00, "00 02 01 02 02 02 03 02");
    call load_ram(0x200, "11 22 33 44");
    call assert_a("A2 00 A1 00", 0x11);  -- LDX #0; LDA ($00,X)
    call assert_a("A2 02 A1 00", 0x22);  -- LDX #2; LDA ($00,X)
    call assert_a("A2 06 A1 00", 0x44);  -- LDX #6; LDA ($00,X)
    call assert_a("A2 02 A1 02", 0x33);  -- LDX #2; LDA ($02,X)
    call assert_a("A2 03 A1 FF", 0x22);  -- LDX #3; LDA ($FF,X)  - wraparound
    -- (indirect),Y
    call load_ram(0x00, "00 02 01 02 02 02 03 02");
    call load_ram(0x200, "11 22 33 44");
    call assert_a("A0 00 B1 00", 0x11);  -- LDY #0; LDA ($00),Y
    call assert_a("A0 02 B1 00", 0x33);  -- LDY #2; LDA ($00),Y
    call assert_a("A0 01 B1 04", 0x44);  -- LDY #1; LDA ($04),Y

    -- instruction style b

    -- immediate
    call assert_x("A2 00", 0x00);  -- LDX #0
    call assert_x("A2 80", 0x80);
    call assert_x("A2 FF", 0xFF);
    -- zero page
    call load_ram(0x00, "AA BB CC DD");
    call load_ram(0x80, "EE");
    call assert_x("A6 00", 0xAA);  -- LDX $00
    call assert_x("A6 01", 0xBB);
    call assert_x("A6 02", 0xCC);
    call assert_x("A6 03", 0xDD);
    call assert_x("A6 80", 0xEE);  -- LDX $80  - unsigned
    -- absolute
    call load_ram(0x200, "11 22 33 44");
    call assert_x("AE 00 02", 0x11);  -- LDX $200
    call assert_x("AE 03 02", 0x44);  -- LDX $203
    -- absolute,Y
    call load_ram(0x00, "AA BB CC DD");
    call load_ram(0x200, "11 22 33 44");
    call assert_x("A0 00 BE 00 02", 0x11);  -- LDY #0; LDX $200,Y
    call assert_x("A0 01 BE 02 02", 0x44);  -- LDY #1; LDX $202,Y
    call assert_x("A0 02 BE FF 01", 0x22);  -- LDY #2; LDX $1FF,Y  - cross page
    call assert_x("A0 FE BE 02 01", 0x11);  -- LDY #$FE; LDX $102,Y  - Y is unsigned
    call assert_x("A0 02 BE FF FF", 0xBB);  -- LDY #2; LDX $FFFF,Y   - wraparound
    -- zero page,Y
    call load_ram(0x00, "AA BB CC DD");
    call assert_x("A0 00 B6 00", 0xAA);  -- LDY #0; LDX $00,Y
    call assert_x("A0 03 B6 00", 0xDD);  -- LDY #3; LDX $00,Y
    call assert_x("A0 01 B6 02", 0xDD);  -- LDY #1; LDX $02,Y
    call assert_x("A0 02 B6 FF", 0xBB);  -- LDY #2; LDX $FF,Y  - wraparound

    -- instruction style c

    -- immediate
    call assert_y("A0 00", 0x00);  -- LDY #0
    call assert_y("A0 80", 0x80);
    call assert_y("A0 FF", 0xFF);
    -- zero page
    call load_ram(0x00, "AA BB CC DD");
    call load_ram(0x80, "EE");
    call assert_y("A4 00", 0xAA);  -- LDY $00
    call assert_y("A4 01", 0xBB);
    call assert_y("A4 02", 0xCC);
    call assert_y("A4 03", 0xDD);
    call assert_y("A4 80", 0xEE);  -- LDY $80  - unsigned
    -- zero page,X
    call load_ram(0x00, "AA BB CC DD");
    call assert_y("A2 00 B4 00", 0xAA);  -- LDX #0; LDY $00,X
    call assert_y("A2 03 B4 00", 0xDD);  -- LDX #3; LDY $00,X
    call assert_y("A2 01 B4 02", 0xDD);  -- LDX #1; LDY $02,X
    call assert_y("A2 02 B4 FF", 0xBB);  -- LDX #2; LDY $FF,X  - wraparound
    -- absolute
    call load_ram(0x200, "11 22 33 44");
    call assert_y("AC 00 02", 0x11);  -- LDY $200
    call assert_y("AC 03 02", 0x44);  -- LDY $203
    -- absolute,X
    call load_ram(0x00, "AA BB CC DD");
    call load_ram(0x200, "11 22 33 44");
    call assert_y("A2 00 BC 00 02", 0x11);  -- LDX #0; LDY $200,X
    call assert_y("A2 01 BC 02 02", 0x44);  -- LDX #1; LDY $202,X
    call assert_y("A2 02 BC FF 01", 0x22);  -- LDX #2; LDY $1FF,X  - cross page
    call assert_y("A2 FE BC 02 01", 0x11);  -- LDX #$FE; LDY $102,X  - X is unsigned
    call assert_y("A2 02 BC FF FF", 0xBB);  -- LDX #2; LDY $FFFF,X   - wraparound

    -- instruction style d

    -- zero page
    call assert_a("A9 00 85 00 E6 00 A5 00", 0x01);  -- LDA #0; STA $00; INC $00; LDA $00
    call assert_a("A9 00 85 80 E6 80 A5 80", 0x01);  -- LDA #0; STA $80; INC $80; LDA $80  - unsigned
    -- zero page,X
    call assert_a("A9 00 85 03 A2 03 F6 00 A5 03", 0x01);  -- LDA #0; STA $03; LDX #3; INC $00,X; LDA $03
    call assert_a("A9 00 85 03 A2 01 F6 02 A5 03", 0x01);  -- LDA #0; STA $03; LDX #1; INC $02,X; LDA $03
    call assert_a("A9 00 85 01 A2 02 F6 FF A5 03", 0x01);  -- LDA #0; STA $01; LDX #2; INC $FF,X; LDA $01  - wraparound
    -- absolute
    call assert_a("A9 00 8D 00 02 EE 00 02 AD 00 02", 0x01);  -- LDA #0; STA $200; INC $200; LDA $200
    call assert_a("A9 00 8D FF 80 EE FF 80 AD FF 80", 0x01);  -- LDA #0; STA $80FF; INC $80FF; LDA $80FF
    -- absolute,X
    call assert_a("A9 00 8D 03 02 A2 03 FE 00 02 AD 03 02", 0x01);  -- LDA #0; STA $203; LDX #3; INC $200,X; LDA $203
    call assert_a("A9 00 8D 03 02 A2 02 FE 01 02 AD 03 02", 0x01);  -- LDA #0; STA $203; LDX #2; INC $201,X; LDA $203
    call assert_a("A9 00 8D 01 02 A2 02 FE FF 01 AD 01 02", 0x01);  -- LDA #0; STA $201; LDX #2; INC $1FF,X; LDA $201  - cross page
    call assert_a("A9 00 8D 00 02 A2 FE FE 02 01 AD 00 02", 0x01);  -- LDA #0; STA $200; LDX #$FE; INC $102,X; LDA $200  - X is unsigned
    call assert_a("A9 00 8D 01 00 A2 02 FE FF FF AD 01 00", 0x01);  -- LDA #0; STA $001; LDX #2; INC $FFFF,X; LDA $001  - wraparound
end;


-- -- -- -- -- -- -- -- -- -- -- -- --
--
--    test instructions
--
-- -- -- -- -- -- -- -- -- -- -- -- --

drop procedure if exists test_instructions;
create procedure test_instructions ()
begin
end;


$$
delimiter ;
